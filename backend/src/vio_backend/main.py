from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from vio_backend.config import Settings
from vio_backend.database import make_engine, make_session_factory, session_dependency


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings.from_environment()
    app.state.settings = settings
    app.state.session_factory = None
    app.state.engine = None
    if settings.database_url:
        engine = make_engine(settings.database_url)
        app.state.engine = engine
        app.state.session_factory = make_session_factory(engine)
    yield
    if app.state.engine is not None:
        await app.state.engine.dispose()


app = FastAPI(title="VIO API", version="0.1.0", lifespan=lifespan)


@app.get("/health/live", tags=["health"])
async def liveness() -> dict[str, str]:
    return {"status": "alive"}


@app.get("/health/ready", tags=["health"])
async def readiness(request: Request) -> dict[str, str]:
    factory = request.app.state.session_factory
    if factory is None:
        raise HTTPException(status_code=503, detail="Database is not configured")
    try:
        async with factory() as session:
            await session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is unavailable") from exc
    return {"status": "ready", "database": "connected"}


@app.get("/api/v1/universities", tags=["catalogue"])
async def list_universities(session: AsyncSession = Depends(session_dependency)) -> dict:
    result = await session.execute(
        text("SELECT short_name, name FROM universities ORDER BY name")
    )
    return {"data": [dict(row) for row in result.mappings().all()]}


@app.get("/api/v1/universities/{short_name}/catalogue", tags=["catalogue"])
async def get_catalogue(short_name: str, session: AsyncSession = Depends(session_dependency)) -> dict:
    result = await session.execute(
        text("""
            SELECT f.name AS faculty, d.name AS department,
                   c.code AS course_code, c.title AS course_title, c.level,
                   ce.semester, ce.is_elective
            FROM universities u
            JOIN faculties f ON f.university_id = u.id
            JOIN departments d ON d.faculty_id = f.id
            JOIN courses c ON c.department_id = d.id
            LEFT JOIN curriculum_entries ce
              ON ce.course_id = c.id AND ce.department_id = d.id
            WHERE lower(u.short_name) = lower(:short_name)
            ORDER BY f.name, d.name, c.level, c.code, ce.semester
        """),
        {"short_name": short_name},
    )
    return {"data": [dict(row) for row in result.mappings().all()]}
