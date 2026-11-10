"""Main FastAPI application entrypoint.

This module creates and configures the FastAPI application.

It is responsible for:

- Creating the app instance
- Setting API metadata for Swagger/OpenAPI
- Configuring CORS
- Registering the API routers
- Exposing basic root and health-check endpoints
"""

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from starlette.middleware.sessions import SessionMiddleware

from oidc_auth import IDTokenClaims
from oidc_auth.integrations import create_oidc_router

from app.api.dependencies import edit_role_names, ppr_role_names
from app.api.v1.api import api_router
from app.core.config import settings
from app.api.dependencies import DbSession, aktiv_session
from app.core.database import engine
from app.utils.identitet import visningsnavn
from app.core.oidc import oidc_config
from app.middleware.audit_middleware import AuditLogMiddleware


class UTF8JSONResponse(JSONResponse):
    """JSON response class with explicit UTF-8 charset.

    Notes:
        This makes API responses explicitly declare UTF-8 encoding.

        That is useful when returning Danish characters such as æ, ø and å.
    """

    media_type = "application/json; charset=utf-8"


# Create the FastAPI application.
#
# The metadata below is shown in Swagger/OpenAPI docs.
app = FastAPI(
    title="Befordrings applikation",
    description="API for Befordrings applikation",
    version="1.0.0",
    default_response_class=UTF8JSONResponse,
    root_path="/api"
)


# Order matters, and it reads backwards: Starlette wraps the *last* middleware
# added as the outermost layer.  So the audit middleware is added first to end
# up innermost, with SessionMiddleware around it — that way request.session is
# already populated when the audit middleware reads the caller's claims, and
# scope["route"] is set by the router just inside it.
app.add_middleware(AuditLogMiddleware)

# Session middleware must be added before CORS so that it ends up as an inner
# layer of the middleware stack.  The session cookie carries OIDC state between
# the /auth/login redirect and the /auth/callback return.
# same_site="lax" is required for the IdP redirect to send the cookie back.
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.session_secret,
    same_site="lax",
)

# allow_origins=["*"] is convenient in development and should be restricted
# in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Register OIDC login / callback / logout routes.
#
# create_oidc_router already applies the /auth prefix internally, so routes
# are mounted at /auth/login, /auth/callback and /auth/logout.
#
# OIDC_REDIRECT_URI points at the *frontend's* /callback, not at the
# /auth/callback below. The frontend owns the return leg so it can restore the
# page the user originally asked for, then forwards the code here.
app.include_router(
    create_oidc_router(
        oidc_config,
        post_logout_redirect=settings.oidc_post_logout_redirect,
    )
)

# Register all API v1 routers. See app/api/v1/api.py for the list.
app.include_router(api_router)


@app.get("/")
def root():
    """Root endpoint.

    Returns:
        A simple message confirming that the API is running.

    Notes:
        This is useful for quickly checking the API in a browser.
    """

    return {"message": "Befordrings Application API is running"}


@app.get("/me", tags=["auth"])
def me(user: IDTokenClaims = Depends(aktiv_session)) -> dict:
    """Return the OIDC claims for the currently logged-in user.

    Raises 401 if there is no active OIDC session, or if the session has
    passed its nightly 01:00 boundary — aktiv_session rather than
    get_current_user, because the frontend decides whether someone is logged
    in by probing this endpoint.
    """
    return {
        "sub": user.sub,
        # visningsnavn, not user.name: the prod IdP has no "name" claim and
        # spells it "displayname", so the user menu showed an email address
        # there while dev showed a name. See app/utils/identitet.
        "name": visningsnavn(user),
        "email": user.email,
        "roles": list(user.roles),
        "groups": list(user.groups),
        "organisation": user.organisation,
        "mapped_claims": user.mapped_claims,
        # Resolved here so the UI does not have to re-implement the rule and
        # drift from it: EDIT_ROLES is configurable, and this is the same
        # comparison require_edit performs when a write actually arrives.
        # Purely for presentation — hiding a control is not enforcement.
        "can_edit": bool(
            {str(role).lower() for role in user.roles} & edit_role_names()
        ),
        # Resolved the same way, against the wider PPR_ROLES. True for PPR
        # Medarbejder ("user-read"), who may set a bevilling's PPR-sagsbehandler
        # and tick "PPR vurderet" — and nothing else. Separate from can_edit so
        # the UI can enable those controls without implying the rest is
        # editable.
        "can_act_as_ppr": bool(
            {str(role).lower() for role in user.roles} & ppr_role_names()
        ),
        # The whole validated ID token payload. The curated fields above cover
        # the common cases; this is what to read when an expected claim is
        # missing from them because the IdP names it something else.
        "raw": user.raw,
    }


@app.get("/health/ready", tags=["health"])
def readiness_check(db: DbSession) -> dict:
    """Whether the API can actually SERVE, as opposed to merely being up.

    /health answers "is the process running". It returns a literal dict and
    touches nothing, so it cannot fail while the API is unable to answer a
    single real request — which is exactly what happened on 9 Nov 2026: a
    transaction left open at 03:13 exhausted the connection pool, every
    endpoint returned 500 for five and a half hours, and `docker ps` reported
    the container healthy the whole time. A check that cannot go red during a
    total outage is worse than none, because it actively points the
    investigation somewhere else.

    This one borrows a pooled connection and runs the cheapest statement there
    is. That is deliberately a test of the POOL as much as of the database: a
    SELECT 1 touches no table, so no lock can block it, but it still has to get
    a connection — and having none is the failure mode that took the site down.

    What it does NOT catch: the lock itself, in the window before the pool
    fills. Overnight there is no traffic to consume connections, so a lock
    taken at 03:13 only turns this red once people start working. Detecting the
    lock earlier needs a probe that reads the affected tables, which is a
    scheduled job's work, not a 30-second healthcheck's.

    The pool counters are returned on success and on failure, because
    "checked_out: 30, available: 0" is the one line that identifies this
    failure immediately, and reading it out of a traceback took an hour.
    """

    pool = engine.pool

    status = {
        "size": pool.size(),
        "checked_out": pool.checkedout(),
        "available": pool.checkedin(),
        "overflow": pool.overflow(),
    }

    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:
        # 503, not 500: the API is working as designed and cannot reach its
        # database. That distinction is what a proxy and a healthcheck act on.
        return JSONResponse(
            status_code=503,
            content={"status": "unavailable", "pool": status, "error": str(exc)},
        )

    return {"status": "ready", "pool": status}


@app.get("/health", tags=["health"])
async def health_check():
    """Health-check endpoint.

    Returns:
        A simple status response.

    Notes:
        LIVENESS only — "the process is running and serving HTTP". It touches
        nothing, so it stays 200 even when the API cannot answer a single real
        request. Use /health/ready for "can it serve", and point container
        healthchecks and monitoring at that one; see the note there.
    """

    return {"status": "ok"}
