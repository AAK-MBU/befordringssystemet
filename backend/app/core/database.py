"""Database setup.

This module configures the SQLAlchemy database connection used by the API.

It is responsible for:

- Creating the SQLAlchemy engine
- Creating a reusable session factory
- Providing a FastAPI dependency for database sessions
- Defining the shared Base class for SQLAlchemy models

Other parts of the application should not usually create database connections
directly. They should use the get_db dependency instead.
"""

from collections.abc import Generator
from urllib.parse import quote_plus

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import settings


class Base(DeclarativeBase):
    """Base class for SQLAlchemy ORM models.

    All SQLAlchemy model classes should inherit from this class.

    Example:
        class Bevilling(Base):
            __tablename__ = "Bevilling"

            ...
    """

    pass


# SQL Server ODBC connection strings can contain characters that need to be
# URL-encoded before they are passed into SQLAlchemy.
#
# quote_plus makes the connection string safe to use inside the SQLAlchemy URL.
odbc_connection = quote_plus(settings.db_connection_string)


# Create the SQLAlchemy engine.
#
# The engine manages the actual connection pool to the database.
#
# mssql+pyodbc tells SQLAlchemy:
# - use Microsoft SQL Server
# - connect through pyodbc
#
# pool_pre_ping=True checks whether a database connection is still alive before
# using it. This helps avoid errors from stale/dead pooled connections.
engine = create_engine(
    f"mssql+pyodbc:///?odbc_connect={odbc_connection}",
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    pool_recycle=1800,
    # How long a request waits for a FREE connection once all 30 are busy.
    # Lowered from the 30s default: the edge proxy gives up around 60s and the
    # SvelteKit server is waiting on this, so a request that queues for half a
    # minute and then still has to run its query has already lost. Failing at
    # 10s surfaces "the pool is saturated" while someone is still watching.
    pool_timeout=10,
)


# Longest a statement will wait for ANOTHER session's lock before giving up.
#
# 10 seconds, chosen against the longest legitimate wait rather than the
# shortest: the nightly usp_upsert_*_from_stg procedures each wrap their whole
# merge in one transaction, and saving a bevilling takes a brief write lock, so
# a shorter value would turn ordinary write bursts into errors for whoever
# happened to read at the wrong moment.
_LOCK_TIMEOUT_MS = 10_000


@event.listens_for(engine, "connect")
def _set_lock_timeout(dbapi_connection, connection_record):
    """Make a blocked statement fail instead of waiting for ever.

    Without this, ONE locked table takes down the entire API, and this is how:

      1. A request reads a locked row and waits. SQL Server's default
         LOCK_TIMEOUT is -1 — wait indefinitely.
      2. A waiting request still holds its pooled connection.
      3. Request by request, all 30 connections end up held by statements
         waiting on an answer that is not coming.
      4. Every OTHER endpoint now fails too — not because anything it touches
         is locked, but because there is no connection left to borrow.

    Step 4 is the damage. On 9 Nov 2026 a transaction left open at 03:13 held
    row locks on Elev; by morning the pool was exhausted and the whole site was
    down for five and a half hours. /min-side, which touches none of it, failed
    inside bind.connect() having never issued a query.

    With a timeout the blocked statement raises after 10 seconds and — the part
    that matters — RETURNS ITS CONNECTION TO THE POOL. The pool keeps cycling,
    unrelated endpoints keep working, and the blast radius stays on the data
    that is actually locked.

    Note this bounds LOCK WAITS only, not execution time: a slow query that is
    blocked by nothing still runs to completion. It is not a query budget.

    Set per connection rather than per session because the setting belongs to
    the connection, and pooled connections are reused across requests.
    """

    cursor = dbapi_connection.cursor()

    try:
        cursor.execute(f"SET LOCK_TIMEOUT {_LOCK_TIMEOUT_MS}")
    finally:
        cursor.close()


# Create a session factory.
#
# SessionLocal is not a database session itself.
# It is a factory that creates new Session objects when called.
#
# autoflush=False:
#     SQLAlchemy will not automatically flush pending changes before queries.
#
# autocommit=False:
#     Changes must be explicitly committed.
SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)


def get_db() -> Generator[Session, None, None]:
    """Create and clean up a database session.

    This function is used as a FastAPI dependency.

    FastAPI will:

    1. Call get_db()
    2. Use the yielded database session inside the endpoint
    3. Continue after yield when the request is finished
    4. Close the database session in the finally block

    Yields:
        A SQLAlchemy database session.

    Notes:
        The finally block always runs after the request is done, even if an
        error occurs. This makes sure the database session is closed properly.
    """

    db = SessionLocal()

    try:
        yield db

    finally:
        db.close()
