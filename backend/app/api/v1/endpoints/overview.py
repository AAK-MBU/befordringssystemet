from fastapi import APIRouter, Depends, Query

from app.api.dependencies import DbSession, aktiv_session
from app.services.overview_service import OverviewService


router = APIRouter(prefix="/overview", tags=["Overview"])


@router.get("/alle_bevillinger")
def get_alle_bevillinger(db: DbSession):
    """Get all bevillinger (every status) for the overview table."""

    return OverviewService(db=db).get_alle_bevillinger()


@router.get("/search")
def search_elever(db: DbSession, q: str = Query(default="", min_length=0)):
    """Global search box: find a student by CPR or name.

    Not gated by RequireEdit — anyone with access to the system may look a
    student up; only writing is restricted.
    """

    return OverviewService(db=db).search_elever(q)


@router.get("/aktive_bevillinger")
def get_active_bevillinger(db: DbSession):
    return OverviewService(db=db).get_active_bevillinger()


@router.get("/fejlede_bevillinger")
def get_fejlede_bevillinger(db: DbSession):
    return OverviewService(db=db).get_fejlede_bevillinger()


@router.get("/revurderinger")
def get_revurderinger(db: DbSession):
    return OverviewService(db=db).get_revurderinger()


@router.get("/genbehandlinger")
def get_genbehandlinger(db: DbSession):
    return OverviewService(db=db).get_genbehandlinger()


@router.get("/counts")
def get_worklist_counts(db: DbSession):
    """Row counts for the four worklists, for the badges in the nav.

    One statement instead of four full dataset reads. See
    OverviewService.get_worklist_counts for why that mattered.
    """
    return OverviewService(db=db).get_worklist_counts()


@router.get("/koerselsgodtgoerelse_modtagere")
def get_koerselsgodtgoerelse_modtagere(db: DbSession):
    """Recipients of kørselsgodtgørelse for currently active egenbefordring.

    Backs the monthly list on the Links page. Returns JSON; the CSV the
    caseworker downloads is formatted by the frontend so this stays reusable.
    """

    return OverviewService(db=db).get_koerselsgodtgoerelse_modtagere()


@router.get("/new_applications")
def get_new_applications(db: DbSession):
    return OverviewService(db=db).get_new_applications()


@router.get("/min_side")
def get_min_side(db: DbSession, claims=Depends(aktiv_session)):
    """Bevillinger assigned to the currently signed-in caseworker.

    Filters by the OIDC email claim matched against Sagsbehandler.email and
    PPR_Sagsbehandler.email (migration 035). Returns only actionable cases:
    Påbegyndt, Afslag, or Aktiv with a revurdering/genbehandling flag.
    """

    email = getattr(claims, "email", None)

    return OverviewService(db=db).get_min_side(email)


@router.get("/min_side_count")
def get_min_side_count(db: DbSession, claims=Depends(aktiv_session)):
    """Row count for the Min side nav badge."""

    email = getattr(claims, "email", None)

    return {"min_side": OverviewService(db=db).get_min_side_count(email)}
