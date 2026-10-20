from sqlalchemy import Boolean, Float, Integer, String, Unicode, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


DB_SCHEMA = "befordring"


class Status(Base):
    __tablename__ = "Status"
    __table_args__ = {"schema": DB_SCHEMA}

    status_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    status_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Hjemmel(Base):
    __tablename__ = "Hjemmel"
    __table_args__ = {"schema": DB_SCHEMA}

    hjemmel_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    hjemmel_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Afgoerelsesbrev(Base):
    __tablename__ = "Afgoerelsesbrev"
    __table_args__ = {"schema": DB_SCHEMA}

    afgoerelsesbrev_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    afgoerelsesbrev_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Sagsbehandler(Base):
    __tablename__ = "Sagsbehandler"
    __table_args__ = {"schema": DB_SCHEMA}

    sagsbehandler_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    sagsbehandler_tekst: Mapped[str] = mapped_column(String, nullable=False)
    # Matched against the signed-in user's OIDC email claim to resolve which
    # caseworker they are — that is what Min side filters on. Nullable: rows
    # created before migration 035 have none, and a caseworker without one
    # simply sees an empty Min side rather than an error.
    email: Mapped[str | None] = mapped_column(String, nullable=True)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class PPRSagsbehandler(Base):
    __tablename__ = "PPR_Sagsbehandler"
    __table_args__ = {"schema": DB_SCHEMA}

    ppr_sagsbehandler_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    ppr_sagsbehandler_tekst: Mapped[str] = mapped_column(String, nullable=False)
    # Matched against the signed-in user's OIDC email claim to resolve which
    # caseworker they are — that is what Min side filters on. Nullable: rows
    # created before migration 035 have none, and a caseworker without one
    # simply sees an empty Min side rather than an error.
    email: Mapped[str | None] = mapped_column(String, nullable=True)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Skolematrikel(Base):
    __tablename__ = "Skolematrikel"
    __table_args__ = {"schema": DB_SCHEMA}

    matrikel_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    matrikel_navn: Mapped[str] = mapped_column(String, nullable=False)
    matrikel_adresse: Mapped[str] = mapped_column(String, nullable=False)
    skolekode: Mapped[int] = mapped_column(Integer, nullable=False)
    er_matrikel_hovedadresse: Mapped[bool] = mapped_column(Boolean, nullable=False)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)


class Hjaelpemiddel(Base):
    __tablename__ = "Hjaelpemiddel"
    __table_args__ = {"schema": DB_SCHEMA}

    hjaelpemiddel_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    hjaelpemiddel_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Tidspunkt(Base):
    __tablename__ = "Tidspunkt"
    __table_args__ = {"schema": DB_SCHEMA}

    tidspunkt_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tidspunkt_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Befordringstype(Base):
    __tablename__ = "Befordringstype"
    __table_args__ = {"schema": DB_SCHEMA}

    befordringstype_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    befordringstype_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class KoerselstypeTillaeg(Base):
    __tablename__ = "KoerselstypeTillaeg"
    __table_args__ = {"schema": DB_SCHEMA}

    tillaeg_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tillaeg_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Ungdomsuddannelse(Base):
    __tablename__ = "Ungdomsuddannelse"
    __table_args__ = {"schema": DB_SCHEMA}

    ungdomsuddannelse_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ungdomsuddannelse_navn: Mapped[str] = mapped_column(Unicode, nullable=False)
    ungdomsuddannelse_adresse: Mapped[str] = mapped_column(String, nullable=False)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)


class Ugedag(Base):
    __tablename__ = "Ugedag"
    __table_args__ = {"schema": DB_SCHEMA}

    dag_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    dag_tekst: Mapped[str] = mapped_column(String, nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(String, nullable=True)
    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)


class Rutetype(Base):
    __tablename__ = "Rutetype"
    __table_args__ = {"schema": DB_SCHEMA}

    rutetype_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    # Bounded Unicode, unlike the unbounded String on the other lookup tables:
    # Rutetype was created by migration 003 rather than in the base schema, and
    # that migration declared NVARCHAR(255) / NVARCHAR(1000). See migration 020,
    # which brings older databases up to the same shape.
    rutetype_tekst: Mapped[str] = mapped_column(Unicode(255), nullable=False)
    beskrivelse: Mapped[str | None] = mapped_column(Unicode(1000), nullable=True)

    # Also from 003: the only lookup table whose aktiv carries a database
    # default (DF_Rutetype_aktiv). Mirrored here so the model matches the table.
    aktiv: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("1"),
    )
