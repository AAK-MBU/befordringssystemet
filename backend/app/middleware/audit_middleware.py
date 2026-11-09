"""Middleware that audit-logs API calls into PortalAuditLog."""

import json
import time
import traceback

from fastapi import Request
from starlette.concurrency import run_in_threadpool
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from app.core.database import SessionLocal
from app.schemas.audit import AuditLogCreate
from app.services.audit_log_service import create_audit_log


# Routes with no audit value.
#
# /me is here because it is not occasional: the SvelteKit guard probes it on
# every page load *and* on every /backend/* call it proxies, so logging it
# would roughly double the table with rows that record nothing a user did.
_SKIPPED_PATHS = frozenset(
    {
        "/",
        "/health",
        # Probed by the container healthcheck every 30 seconds — ~2,900 rows a
        # day recording nothing anyone did. External monitoring makes it more.
        "/health/ready",
        "/me",
        "/docs",
        "/redoc",
        "/openapi.json",
        # The same endpoints as the edge proxy may present them.
        #
        # This match is on the path alone and says nothing about the caller, so
        # the container healthcheck hitting 127.0.0.1:8000/health/ready is
        # already covered. What is NOT covered by the bare spellings is a
        # monitor calling the PUBLIC url, .../api/health/ready: whether the app
        # then sees "/health/ready" or "/api/health/ready" depends on whether
        # nginx strips the prefix, which lives in a config outside this repo.
        #
        # Listing both spellings is cheaper than depending on the answer, and
        # removes a trap where adding uptime monitoring quietly starts writing
        # a row per poll, for ever.
        "/api/health",
        "/api/health/ready",
        "/api/me",
        "/api/docs",
        "/api/redoc",
        "/api/openapi.json",
    }
)


# Paths serving reference data only — the dropdown contents behind the UI.
#
# Opening one case page fetches thirteen of these, and the revurdering page
# thirteen of its fourteen calls, so they made up the bulk of the table while
# answering neither question it exists for: none of them takes a CPR or returns
# citizen data, so they cannot show who accessed whose record.
#
# Only their *successful* calls are dropped. A 401 or 403 here is an
# access-control event and matters regardless of how dull the data is — these
# are the endpoints reachable without knowing a CPR, so they are where a stale
# or stolen key would show up first. A 500 explains a page that renders empty.
#
# WARNING: this is keyed on the path prefix, so an endpoint added under /lookup
# that returns personal data would silently stop being audited. There is a
# matching warning on the router in api/v1/endpoints/lookup.py.
_REFERENCE_PATH_PREFIXES = ("/lookup/",)


# Query parameters whose values must never reach the table.
#
# /auth/callback carries the OIDC authorization code and state; short-lived,
# but they are credentials, and an audit table is exactly the sort of
# long-lived, widely-readable place they should not accumulate in.
_REDACTED_PARAMS = frozenset({"code", "state", "id_token", "access_token", "token"})

_REDACTED_VALUE = "[redacted]"


class AuditLogMiddleware(BaseHTTPMiddleware):
    """Writes one PortalAuditLog row per business-relevant request.

    The row holds the caller's identity, method and path, query parameters,
    status code, duration, client IP, user agent and — on failure — an error
    message read out of the response body. Logging happens in a session opened
    for the purpose, and a failure to log never affects the response.

    Two kinds of request are left out: the noise endpoints in _SKIPPED_PATHS,
    and reference-data reads that succeeded. See _should_log.
    """

    async def dispatch(self, request: Request, call_next):
        """Run the request onwards and audit-log the outcome.

        The caller's identity is taken from `request.state.api_key_name` when
        the request authenticated with an API key, otherwise from the OIDC
        session's email or sub claim; an unauthenticated request is logged with
        None. A response with status 400 or above has its body read so the
        error message can be stored — where the body is a stream it is read in
        full and the response rebuilt, so the caller still receives it. An
        exception from a route handler is logged as 500 and re-raised.

        Whether the finished request earns a row is decided by _should_log,
        which is why that check happens after the handler rather than before:
        for reference data the outcome is what decides.

        Args:
            request: The incoming request.
            call_next: The next link in the middleware chain.

        Returns:
            The response from the next link — for error responses with a
            streamed body, a new Response carrying the same content, status
            code and headers.
        """
        if request.url.path in _SKIPPED_PATHS:
            return await call_next(request)

        start_time = time.perf_counter()

        # Identity comes from the OIDC session claims, populated by
        # SessionMiddleware, which sits outside this middleware. The email
        # claim is preferred — readable, and stable enough to trace — with the
        # IdP's opaque subject as the fallback.
        session = request.scope.get("session") or {}
        claims = session.get("oidc_claims") or {}
        user_ident = claims.get("email") or claims.get("sub")

        query_params = self._redacted_query_params(request)
        ip_address = self._get_client_ip(request)
        user_agent = request.headers.get("user-agent")

        response = None
        status_code = None
        error_message = None

        try:
            response = await call_next(request)
            status_code = response.status_code

            if status_code >= 400:
                response, error_message = await self._read_error(response)

        except Exception as exc:
            status_code = 500
            error_message = f"{type(exc).__name__}: {exc}"

            print(f"[AuditMiddleware] Exception: {error_message}")
            traceback.print_exc()

            raise

        finally:
            # Everything here is inside a try: assembling the row must not be
            # able to break the response either. _write guards the database
            # call, but building AuditLogCreate can raise on its own — a
            # validation error, an unexpected None — and this block runs while
            # an exception from the handler may already be propagating.
            try:
                if self._should_log(request.url.path, status_code):
                    await self._log(
                        request,
                        status_code=status_code,
                        error_message=error_message,
                        duration_ms=round(
                            (time.perf_counter() - start_time) * 1000, 2
                        ),
                        user_ident=user_ident,
                        query_params=query_params,
                        ip_address=ip_address,
                        user_agent=user_agent,
                    )

            except Exception as audit_error:
                print(f"[AuditMiddleware] Failed to build audit row: {audit_error}")
                traceback.print_exc()

        return response

    # -------------------------
    # Helpers
    # -------------------------

    @staticmethod
    def _should_log(path: str, status_code: int | None) -> bool:
        """Decide whether a finished request is worth a row.

        Everything is logged except reference-data reads that succeeded — see
        _REFERENCE_PATH_PREFIXES for why those are the one exception, and why
        only the successful ones. An unknown outcome is kept: not knowing how a
        call ended is itself worth recording.
        """
        if not path.startswith(_REFERENCE_PATH_PREFIXES):
            return True

        return status_code is None or status_code >= 400

    async def _log(
        self,
        request: Request,
        *,
        status_code: int | None,
        error_message: str | None,
        duration_ms: float,
        user_ident: str | None,
        query_params: str | None,
        ip_address: str | None,
        user_agent: str | None,
    ) -> None:
        """Assemble the row and write it."""
        # Machine callers (RPA, OS2Forms) hold no OIDC session; require_auth
        # puts the matched key's name on request.state so those calls are
        # attributed rather than logged as anonymous.
        api_key_name = getattr(request.state, "api_key_name", None)

        audit_data = AuditLogCreate(
            bruger_ident=api_key_name or user_ident,
            api_key_name=api_key_name,
            action=self._get_action(request),
            method=request.method,
            path=request.url.path,
            query_params=query_params,
            status_code=status_code,
            duration_ms=duration_ms,
            error_message=error_message,
            ip_address=ip_address,
            user_agent=user_agent,
        )

        # Off the event loop: the driver is synchronous, and blocking here
        # would stall every other in-flight request for the length of the
        # insert.
        await run_in_threadpool(self._write, audit_data)


    @staticmethod
    def _get_action(request: Request) -> str | None:
        """The matched route's name, for the Action column.

        The router sits inside this middleware, so the match is only on the
        scope by the time this runs. Starlette puts the route itself on
        scope["route"]; scope["endpoint"] is read as a fallback because that
        key has been the stable one across versions. A request that matched
        nothing — a 404 — has neither, and gets no action.
        """
        route = request.scope.get("route")
        name = getattr(route, "name", None)

        if name:
            return name

        endpoint = request.scope.get("endpoint")

        return getattr(endpoint, "__name__", None)


    @staticmethod
    def _write(audit_data: AuditLogCreate) -> None:
        """Commit one audit row in its own session.

        Always attempts to log, but a failed write must not poison the
        response, so everything is caught and reported to the application log
        instead.
        """
        db = None

        try:
            db = SessionLocal()
            create_audit_log(db, audit_data)
            db.commit()

        except Exception as log_error:
            print(f"[AuditMiddleware] Failed to log: {log_error}")
            traceback.print_exc()

            if db is not None:
                try:
                    db.rollback()
                except Exception:
                    pass

        finally:
            if db is not None:
                try:
                    db.close()
                except Exception:
                    pass

    def _redacted_query_params(self, request: Request) -> str | None:
        """The request's query parameters as JSON, credentials removed.

        Returns:
            A JSON object of the parameters, with the values of
            credential-bearing keys replaced. None when the call had none, so
            the column holds NULL rather than "{}".
        """
        if not request.query_params:
            return None

        params = {
            key: (_REDACTED_VALUE if key.lower() in _REDACTED_PARAMS else value)
            for key, value in request.query_params.items()
        }

        return json.dumps(params, ensure_ascii=False)

    def _get_client_ip(self, request: Request) -> str | None:
        """The client's IP from x-forwarded-for, x-real-ip, or the connection.

        Every browser call arrives via the SvelteKit proxy, so the connection's
        host is that container rather than the user; the forwarded headers are
        what carry the real address. They are also caller-supplied, and the API
        is reachable directly on the internal network, so treat the value as
        an indication rather than proof.

        Returns:
            The first address in x-forwarded-for, else x-real-ip, else the host
            of the connection the request arrived on, or None.
        """
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()

        real_ip = request.headers.get("x-real-ip")
        if real_ip:
            return real_ip

        if request.client:
            return request.client.host

        return None

    async def _read_error(self, response: Response) -> tuple[Response, str | None]:
        """Read an error response's body so its message can be logged.

        Returns:
            The response to hand back — rebuilt from the collected bytes when
            the body was a stream, since reading it leaves it empty — and the
            extracted error message.
        """
        if hasattr(response, "body_iterator"):
            body = b""

            async for chunk in response.body_iterator:
                body += chunk

            rebuilt = Response(
                content=body,
                status_code=response.status_code,
                headers=dict(response.headers),
                media_type=response.media_type,
            )

            return rebuilt, self._extract_error(body, response.status_code)

        if hasattr(response, "body"):
            return response, self._extract_error(response.body, response.status_code)

        return response, f"HTTP {response.status_code} error"

    def _extract_error(self, body: bytes, status_code: int) -> str:
        """Pull a readable error message out of an error response's body.

        The body is expected to be FastAPI's JSON with a `detail` key. Where
        `detail` is a string it is used as-is; where it is a list of validation
        errors, the first error's `msg` is used together with its `loc` path.

        Returns:
            The error message, or "HTTP <code> error" when the body is empty,
            is not JSON, or carries no usable `detail`.
        """
        if not body:
            return f"HTTP {status_code} error"

        try:
            payload = json.loads(body.decode("utf-8"))

            if isinstance(payload, dict) and "detail" in payload:
                detail = payload["detail"]

                if isinstance(detail, str):
                    return detail

                if isinstance(detail, list) and detail:
                    item = detail[0]

                    if isinstance(item, dict):
                        message = item.get("msg")
                        location = item.get("loc", [])

                        if location:
                            path = " -> ".join(map(str, location))
                            return f"{message} (field: {path})"

                        return message

                return str(detail)

        except Exception:
            pass

        return f"HTTP {status_code} error"
