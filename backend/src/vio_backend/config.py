from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    database_url: str | None
    api_prefix: str = "/api/v1"

    @classmethod
    def from_environment(cls) -> "Settings":
        return cls(database_url=os.getenv("DATABASE_URL"))
