// Cloudflare Worker: caches Launch Library 2 so the app and widget don't
// hit its unauthenticated limit (15 req/hr, per TheSpaceDevs) directly.
// No cron triggers: on the free plan, cron quotas fail deploys. This is
// lazy refresh only — it polls LL2 when /launches is requested and the
// cached copy is older than TTL_SECONDS, and serves the stale copy
// instead of a 502 when LL2 is down or rate-limited.
const LL2 = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=25&mode=detail";
const TTL_SECONDS = 300;
const CACHED_AT_HEADER = "x-launchwindow-cached-at";

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}

function jsonError(status, body) {
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
    if (url.pathname !== "/launches") {
      return new Response("Launch Window API", { status: 200, headers: corsHeaders() });
    }

    const cache = caches.default;
    const cacheKey = new Request(url.origin + "/launches");
    const cached = await cache.match(cacheKey);
    const cachedAt = cached ? Number(cached.headers.get(CACHED_AT_HEADER) || 0) : 0;
    const fresh = cached && Date.now() - cachedAt < TTL_SECONDS * 1000;
    if (fresh) return cached;

    try {
      const upstream = await fetch(LL2, { headers: { "User-Agent": "LaunchWindow/1.0" } });
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
      // Stale is better than nothing for a countdown: a 5-minute-old
      // launch list is useful, a 502 is not.
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
      return jsonError(502, { error: "upstream", detail: String(err) });
    }
  },
};
