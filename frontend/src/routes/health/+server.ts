import type { RequestHandler } from "./$types";


/**
 * Liveness probe for the container healthcheck.
 *
 * Exists because there was no path the healthcheck could legitimately ask for.
 * It used to probe `/`, which fails for two unrelated reasons at once:
 *
 *   1. It asked for `http://localhost:80`, which resolves to [::1] first, while
 *      the server binds 0.0.0.0 — IPv4 only. The check never got as far as HTTP;
 *      it was refused at the TCP layer. (curl retries the next address and wget
 *      does not, which is why the API's check looked fine and this one did not.)
 *
 *   2. Even reaching it, `/` is behind the auth guard. An anonymous non-document
 *      request gets 401 by design — see isDocumentRequest in hooks.server.ts —
 *      and `wget --spider` exits non-zero on a 4xx. Fixing only the address
 *      would have swapped one permanent failure for another.
 *
 * So the container reported `unhealthy` from the day the check was written,
 * whatever the application was actually doing. That is worse than having no
 * check: during the outage on 9 Nov 2026 the frontend's status said `unhealthy`
 * while the fault was entirely in the API's connection pool, and it sent the
 * investigation to the wrong container for some time.
 *
 * Listed in PUBLIC_PATHS so the guard lets it through unauthenticated.
 *
 * LIVENESS ONLY. A 200 means this Node process is up and routing requests. It
 * deliberately does not call the API: the frontend is useless without the
 * backend, but conflating the two would make this container go unhealthy for
 * the other one's fault — which is the confusion above, inverted. The API has
 * its own /health/ready for whether it can serve.
 */
export const GET: RequestHandler = () => {
  return new Response(JSON.stringify({ status: "ok" }), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
};
