# Progress

## Current State

- Repository groundwork only; no application or database implementation has started.
- Project name confirmed as **VIO (Voice It Out)**. CampusVoice is not used.
- Backend and frontend folder scaffolds are present. Frontend implementation is owned by frontend developers; no language or framework has been selected.
- A versioned REST endpoint catalog and screen-by-screen frontend journeys are drafted for joint review. Paths and payloads are proposals, not yet approved.
- `schema.sql` and `seed.sql` are present. They have not been run: local PostgreSQL is not installed, and no Neon database connection is available in this workspace. Local PostgreSQL is not required if the scripts are run in Neon.
- `workflow.mermaid` is not present. The available `erd.mermaid` includes `moderators` and `moderation_log`, while the current `schema.sql` uses automated panel tables; reconcile the ERD before treating it as current.
- Decisions 1-5 in `DECISIONS.md` are pending. No defaults have been assumed.

## Milestones

| Milestone | Status | Notes |
| --- | --- | --- |
| M0: Foundation | In progress | SQL files are present but need execution in Neon and a smoke-test query set. No database scripts or smoke tests have been run. |
| M1: Decisions | Not started | Awaiting approval of the five reserved decision areas. |
| M2-M9 | Not started | Do not begin until prior milestones are completed and approved. |

## Untested / Not Yet Verified

- PostgreSQL extension availability (`pgcrypto`, `citext`) in Neon
- Schema and seed execution against Neon
- Smoke-test queries
- All application behavior and privacy controls