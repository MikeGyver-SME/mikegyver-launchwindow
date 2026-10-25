// Cloudflare Worker: caches Launch Library 2 so the app and widget don't
// hit its unauthenticated limit (15 req/hr, per TheSpaceDevs) directly.
// Patreon-authenticated mode: if the LL2_TOKEN secret is set on the
// Worker (Cloudflare encrypted variable, NEVER in code, NEVER in the
// app, NEVER in the repo), both upstream fetches send it as
// "Authorization: Token <token>". The token must stay server-side:
// the app never sees it, and /health only reports authenticated:
// true/false, never the value. If the token is present and valid,
// LL2 should raise the budget (Patreon tier quoted at 45/hr) and tie
// it to the token instead of the shared Cloudflare egress IP.
// Verify by checking Worker /throttle: your_request_limit should
// flip from 15 to 45. If it still shows 15, the token is not wired
// or the auth scheme is wrong — do not paste the token anywhere to
// debug it; check the secret binding and the scheme instead.
// No cron triggers: on the free plan, cron quotas fail deploys. This is
// lazy refresh only — it polls LL2 when /launches is requested and the
// cached copy is older than TTL_SECONDS, and serves the stale copy
// instead of an error when LL2 is down or rate-limited.
// Routes:
//   /         -> "Launch Window API" (no upstream fetch)
//   /health   -> JSON worker health (no upstream fetch, so it never 429s
//                for an upstream reason): { status, service, cache:
//                "fresh"|"stale"|"empty", cachedAt, ttlSeconds }
//   /launches -> cached LL2 launch list, or an error only when the cache
//                is empty AND upstream fails. A 429 here means LL2
//                rate-limited the Worker's shared Cloudflare egress IP;
//                the app falls back to direct LL2 in that case.
//   /throttle -> LL2's own api-throttle status AS SEEN FROM THE WORKER:
//                { your_request_limit, limit_frequency_secs, current_use,
//                next_use_secs, ident }. This is the only way to see the
//                Worker's own budget — fetching api-throttle from a
//                browser/phone shows THAT caller's IP, not the Worker's.
//                Cached 60s so diagnosing it doesn't itself hammer LL2;
//                use it sparingly anyway, in case LL2 counts this call
//                toward the limit (LL2 does not document that either way).
const LL2 = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=25&mode=detail";
const LL2_THROTTLE = "https://ll.thespacedevs.com/2.3.0/api-throttle/";
const TTL_SECONDS = 900;
const THROTTLE_TTL_SECONDS = 60;
// After an upstream 429, do NOT touch LL2 again for this long, even if
// /launches is hit repeatedly. Without this, every app open, widget
// refresh and browser check re-burns the shared egress IP's budget and
// the rolling 15/hr window can never clear. A blocked Worker serves
// stale cache if it has one, else a 429 immediately, with no upstream
// fetch at all.
const BLOCKED_TTL_SECONDS = 900;
const CACHED_AT_HEADER = "x-launchwindow-cached-at";

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}

// Upstream headers. The token, when set as a Worker secret, is added
// here and nowhere else. No response ever includes it.
function upstreamHeaders(env) {
  const headers = { "User-Agent": "LaunchWindow/1.0" };
  const token = env && env.LL2_TOKEN ? String(env.LL2_TOKEN).trim() : "";
  if (token) headers["Authorization"] = `Token ${token}`;
  return headers;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const cache = caches.default;
    const cacheKey = new Request(url.origin + "/launches");

    // Health check: deliberately does NOT fetch upstream, so it is safe
    // to hit as often as needed while diagnosing a 429 on /launches.
    if (url.pathname === "/health") {
      const cached = await cache.match(cacheKey);
      const cachedAtMs = cached ? Number(cached.headers.get(CACHED_AT_HEADER) || 0) : 0;
      const cacheState = !cached
        ? "empty"
        : Date.now() - cachedAtMs < TTL_SECONDS * 1000
          ? "fresh"
          : "stale";
      const blockedEntry = await cache.match(new Request(url.origin + "/blocked"));
      const blockedAtMs = blockedEntry
        ? Number(blockedEntry.headers.get(CACHED_AT_HEADER) || 0)
        : 0;
      const blocked = Boolean(blockedEntry) && Date.now() - blockedAtMs < BLOCKED_TTL_SECONDS * 1000;
      return jsonResponse(200, {
        status: "ok",
        service: "launchwindow",
        cache: cacheState,
        cachedAt: cachedAtMs ? new Date(cachedAtMs).toISOString() : null,
        ttlSeconds: TTL_SECONDS,
        blocked,
        blockedUntil: blocked
          ? new Date(blockedAtMs + BLOCKED_TTL_SECONDS * 1000).toISOString()
          : null,
        // Boolean only — the token value is never returned.
        authenticated: Boolean(env && env.LL2_TOKEN),
      });
    }

    // Throttle status from the Worker's own IP. Cached 60s, and the
    // cached copy is returned with its age, so a repeated check in
    // that minute does not make another upstream call at all.
    if (url.pathname === "/throttle") {
      const throttleKey = new Request(url.origin + "/throttle");
      const throttleCached = await cache.match(throttleKey);
      const throttleAt = throttleCached
        ? Number(throttleCached.headers.get(CACHED_AT_HEADER) || 0)
        : 0;
      if (throttleCached && Date.now() - throttleAt < THROTTLE_TTL_SECONDS * 1000) {
        return throttleCached;
      }
      try {
        const upstream = await fetch(LL2_THROTTLE, {
          headers: upstreamHeaders(env),
        });
        const response = new Response(upstream.body, {
          status: upstream.status,
          headers: {
            "content-type": "application/json",
            "cache-control": `public, max-age=${THROTTLE_TTL_SECONDS}`,
            [CACHED_AT_HEADER]: String(Date.now()),
            ...corsHeaders(),
          },
        });
        if (upstream.ok) ctx.waitUntil(cache.put(throttleKey, response.clone()));
        return response;
      } catch (err) {
        return jsonResponse(502, { error: "throttle", detail: String(err) });
      }
    }

    if (url.pathname !== "/launches") {
      return new Response("Launch Window API", { status: 200, headers: corsHeaders() });
    }

    const cached = await cache.match(cacheKey);
    const cachedAt = cached ? Number(cached.headers.get(CACHED_AT_HEADER) || 0) : 0;
    const fresh = cached && Date.now() - cachedAt < TTL_SECONDS * 1000;
    if (fresh) return cached;

    // Backoff: if LL2 recently 429'd us, do NOT fetch upstream again
    // until the block expires. Serve stale cache if there is one, else
    // fail fast with a 429 and no upstream call at all. This is what
    // lets the shared egress IP's rolling window actually clear.
    const blockedKey = new Request(url.origin + "/blocked");
    const blockedEntry = await cache.match(blockedKey);
    const blockedAt = blockedEntry
      ? Number(blockedEntry.headers.get(CACHED_AT_HEADER) || 0)
      : 0;
    const blocked = Boolean(blockedEntry) && Date.now() - blockedAt < BLOCKED_TTL_SECONDS * 1000;
    if (blocked) {
      if (cached) {
        return new Response(cached.body, {
          status: 200,
          headers: {
            "content-type": "application/json",
            "x-launchwindow-stale": "true",
            "x-launchwindow-blocked": "true",
            ...corsHeaders(),
          },
        });
      }
      return jsonResponse(429, {
        error: "upstream",
        detail: "upstream 429 (backoff, no upstream fetch)",
      });
    }

    let upstreamStatus = 0;
    try {
      const upstream = await fetch(LL2, { headers: upstreamHeaders(env) });
      upstreamStatus = upstream.status;
      if (!upstream.ok) throw new Error(`upstream ${upstream.status}`);
      const response = new Response(upstream.body, {
        status: 200,
        headers: {
          "content-type": "application/json",
          "cache-control": `public, max-age=${TTL_SECONDS}`,
          [CACHED_AT_HEADER]: String(Date.now()),
          ...corsHeaders(),
        },
      });
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
      return response;
    } catch (err) {
      // Stale is better than nothing for a countdown: a 15-minute-old
      // launch list is useful, an error is not.
      if (cached) {
        return new Response(cached.body, {
          status: 200,
          headers: {
            "content-type": "application/json",
            "x-launchwindow-stale": "true",
            ...corsHeaders(),
          },
        });
      }
      // On a 429, record the block so the next 15 minutes of /launches
      // hits do not touch LL2 at all. Without this, repeated hits keep
      // the rolling window full forever.
      if (upstreamStatus === 429) {
        const blockedResponse = new Response("blocked", {
          status: 200,
          headers: {
            "content-type": "text/plain",
            "cache-control": `public, max-age=${BLOCKED_TTL_SECONDS}`,
            [CACHED_AT_HEADER]: String(Date.now()),
            ...corsHeaders(),
          },
        });
        ctx.waitUntil(cache.put(blockedKey, blockedResponse.clone()));
      }
      // Preserve a 429 as a 429 (not a generic 502) so the browser
      // console and the app can tell "LL2 rate-limited us" apart from
      // "the Worker itself failed".
      return jsonResponse(upstreamStatus === 429 ? 429 : 502, {
        error: "upstream",
        detail: String(err),
      });
    }
  },
};
