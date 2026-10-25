// Cloudflare Worker: caches Launch Library 2 so the app and widget don't
// hit its unauthenticated limit (15 req/hr, per TheSpaceDevs) directly.
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
const LL2 = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=25&mode=detail";
const TTL_SECONDS = 900;
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
      return jsonResponse(200, {
        status: "ok",
        service: "launchwindow",
        cache: cacheState,
        cachedAt: cachedAtMs ? new Date(cachedAtMs).toISOString() : null,
        ttlSeconds: TTL_SECONDS,
      });
    }

    if (url.pathname !== "/launches") {
      return new Response("Launch Window API", { status: 200, headers: corsHeaders() });
    }

    const cached = await cache.match(cacheKey);
    const cachedAt = cached ? Number(cached.headers.get(CACHED_AT_HEADER) || 0) : 0;
    const fresh = cached && Date.now() - cachedAt < TTL_SECONDS * 1000;
    if (fresh) return cached;

    let upstreamStatus = 0;
    try {
      const upstream = await fetch(LL2, { headers: { "User-Agent": "LaunchWindow/1.0" } });
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
