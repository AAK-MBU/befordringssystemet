import type { Handle } from "@sveltejs/kit";

import {
  getLoginUrl,
  LOGIN_ATTEMPT_COOKIE,
  probeSession,
  serializeLoginAttempt,
  serializeLoginAttemptCleared,
  serializeReturnTo
} from "$lib/server/auth";
import { loggedOutPage } from "$lib/server/loggedOut";
import { noAccessPage } from "$lib/server/noAccess";


/**
 * Paths that must stay reachable without a session.
 *
 * Most of these are the endpoints that *establish* a session — /api/auth passes
 * login and logout through to the backend, and /callback is the OIDC return leg
 * carrying the authorization code. Guarding either would deadlock the flow into
 * a redirect loop.
 *
 * /health is here for a different reason: it is the container healthcheck's
 * probe, and the healthcheck has no session and cannot get one. Guarded, it
 * would answer 401 to an anonymous non-document request — correctly, by the
 * rule below — and the container would report unhealthy for ever. See
 * routes/health/+server.ts.
 */
const PUBLIC_PATHS = ["/callback", "/api/auth", "/health"];


function matchesPath(pathname: string, candidate: string) {
  return pathname === candidate || pathname.startsWith(`${candidate}/`);
}


function isPublicPath(pathname: string) {
  if (PUBLIC_PATHS.some((publicPath) => matchesPath(pathname, publicPath))) {
    return true;
  }

  // When the login URL is same-origin (the default /api/auth/login, served by
  // the reverse proxy rather than by SvelteKit) it must not be guarded. If the
  // proxy is missing, that path falls through to SvelteKit's 404 — guarding it
  // would instead redirect it to itself forever.
  const loginUrl = getLoginUrl();

  return loginUrl.startsWith("/") && matchesPath(pathname, loginUrl);
}


/**
 * Whether this request is a top-level page navigation.
 *
 * Only a navigation should start a login. A browser issues plenty of requests
 * the user never asked for — /favicon.ico on any page, prefetches, in-page
 * fetch()es — and sending one of those to the IdP accomplishes nothing on its
 * own. The damage is the login-attempt marker it leaves behind: the user's next
 * real navigation then looks like a login that came back without a session, and
 * the guard reports a failure that never happened. The marker is cleared as
 * that report renders, so the attempt after it succeeds — which makes the whole
 * thing look intermittent.
 */
function isDocumentRequest(request: Request) {
  const dest = request.headers.get("sec-fetch-dest");

  if (dest) {
    return dest === "document";
  }

  // No Sec-Fetch-Dest (older clients, curl): fall back to content negotiation,
  // erring towards "navigation" so that logging in still works.
  return (request.headers.get("accept") ?? "").includes("text/html");
}


/**
 * Send the user to the IdP, remembering where they were headed.
 *
 * Built as an explicit Response rather than a thrown redirect() so that the
 * Set-Cookie travels with the 302 unambiguously — the destination cookie is
 * only useful if it survives this exact hop.
 */
function loginRedirect(url: URL) {
  const secure = url.protocol === "https:";
  const headers = new Headers({ location: getLoginUrl() });

  headers.append(
    "set-cookie",
    serializeReturnTo(`${url.pathname}${url.search}`, secure)
  );
  headers.append("set-cookie", serializeLoginAttempt(secure));

  return new Response(null, { status: 302, headers });
}


/**
 * Reported when a completed login round trip left the browser still anonymous.
 *
 * Almost always the backend's session cookie failing to persist, so name the
 * thing to go and look at rather than bouncing to the IdP again.
 */
function loginLoopDiagnostic() {
  const headers = new Headers({ "content-type": "text/plain; charset=utf-8" });

  headers.append("set-cookie", serializeLoginAttemptCleared());

  return new Response(
    "Login gennemført, men der blev ikke oprettet en session.\n\n" +
      "Session-cookien fra API'et nåede ikke browseren. Tjek at /auth/callback " +
      "returnerer en Set-Cookie header, og at reverse proxy'en videresender den.\n\n" +
      "Genindlæs siden for at prøve igen.",
    { status: 503, headers }
  );
}


/** Path B2C returns the browser to once it has ended the session. */
export const LOGGED_OUT_PATH = "/logged-out";


export const handle: Handle = async ({ event, resolve }) => {
  // Answered before the guard runs, and before resolve(): whoever lands here
  // has just had their session destroyed, so probing for one would only bounce
  // them back into the login they just left. Rendered here rather than as a
  // route so it does not inherit the application shell — see statusPage.ts.
  if (event.url.pathname === LOGGED_OUT_PATH) {
    return loggedOutPage();
  }

  if (isPublicPath(event.url.pathname)) {
    return resolve(event);
  }

  const probe = await probeSession(event.request.headers.get("cookie"));

  if (probe.status === "unavailable") {
    // Bouncing to the IdP when the API is merely down would present an outage
    // as a login loop, so fail loudly instead.
    console.error(`[auth] session probe unavailable — ${probe.reason}`);

    return new Response("Kunne ikke kontakte API'et", { status: 503 });
  }

  if (probe.status === "anonymous") {
    // /backend/* is fetch()ed by already-loaded pages. A 302 to the IdP would
    // resolve to its HTML login page and blow up in response.json(), so answer
    // with a status the caller can act on. Checked by path rather than by
    // header so it holds for any client, not just browsers.
    if (matchesPath(event.url.pathname, "/backend")) {
      return new Response(null, { status: 401 });
    }

    // Anything else that is not a navigation gets the same treatment, and in
    // particular does not consume the login attempt — see isDocumentRequest.
    if (!isDocumentRequest(event.request)) {
      return new Response(null, { status: 401 });
    }

    // Already been through the IdP and still no session — retrying would just
    // loop, so say what went wrong instead.
    if (event.cookies.get(LOGIN_ATTEMPT_COOKIE)) {
      console.warn(
        `[auth] still anonymous at ${event.url.pathname} with the login-attempt ` +
          "marker set — reporting a failed login round trip"
      );

      return loginLoopDiagnostic();
    }

    return loginRedirect(event.url);
  }

  // Authenticated, but the IdP assigned no roles for this system. Roles are
  // granted centrally (Systemregisteret -> IdP claim), so there is nothing to
  // do in-app: show what to do about it and resolve nothing else.
  if (probe.user.roles.length === 0) {
    // Logged, because the guard is now the only place this is visible: a denied
    // user cannot reach /whoami to see their own claims either.
    console.warn(`[auth] no roles for ${probe.user.sub} — access denied`);

    // Same reasoning as the anonymous branch: /backend/* is fetch()ed by
    // already-loaded pages, so answer with a status rather than an HTML page
    // that would blow up in response.json().
    if (matchesPath(event.url.pathname, "/backend")) {
      return new Response(null, { status: 403 });
    }

    return noAccessPage(probe.user);
  }

  event.locals.user = probe.user;

  return resolve(event);
};
