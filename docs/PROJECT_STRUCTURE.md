# Proposed Repository Structure

This is a reviewable VIO repository scaffold with backend and frontend areas. It does not choose a programming language, framework, hosting provider, model provider, or API format. The structure can be adjusted before implementation.

```text
vio/
|-- backend/
|   |-- src/
|   |   |-- api/                  # HTTP or other transport adapters
|   |   |-- application/          # Use-case orchestration
|   |   |-- domain/               # Deterministic rules and core concepts
|   |   |-- infrastructure/
|   |   |   |-- database/         # Neon/PostgreSQL access
|   |   |   |-- identity/         # Sign-in and identity hashing adapters
|   |   |   |-- model-panel/      # Model calls and output validation
|   |   |   |-- notifications/    # Email and secure-link delivery adapters
|   |   |   `-- evidence/         # Timetable and report evidence handling
|   |   `-- workers/              # Escalation, evaluation, retention jobs
|   |-- tests/
|   |   |-- unit/
|   |   |-- integration/
|   |   |-- contract/
|   |   |-- privacy/
|   |   `-- fixtures/             # Synthetic sensitive-workflow fixtures only
|   `-- scripts/                  # Local development and maintenance tasks
|-- database/
|   |-- erd.mermaid
|   |-- schema.sql
|   `-- seed.sql
|-- frontend/
|   |-- src/
|   |   |-- app/                  # Frontend routing and app shell
|   |   |-- features/             # Student, lecturer, authority, dashboard workflows
|   |   |-- shared/
|   |   |   |-- api/              # API client and agreed/generated contract types
|   |   |   |-- components/       # Shared UI components
|   |   |   `-- types/            # Shared frontend types
|   |   `-- assets/
|   `-- tests/
|-- docs/
|   |-- api/                      # API proposal and approved contract
|   |-- architecture/
|   |-- data/                     # Data-source provenance and freshness
|   |-- DECISIONS.md
|   |-- PROGRESS.md
|   |-- PROJECT_STRUCTURE.md
|   |-- frontend-handoff/
|   `-- operations/
|-- README.md
`-- LICENSE
```

The SQL scripts live in `database/`. The frontend is part of this repository, with implementation owned by frontend developers. Both trees are scaffolded without choosing a language or framework. Empty directories are tracked with `.gitkeep` until implementation files are added.

## Separation

- `api` handles transport concerns; it should not make scoring or gate decisions.
- `application` coordinates workflows across domain rules and adapters.
- `domain` owns deterministic scoring, eligibility, and gate logic.
- `infrastructure` contains replaceable integrations with PostgreSQL, identity services, model providers, notifications, and evidence storage.
- `workers` contains scheduled work such as escalation and assurance checks.
- Tests are separated by scope, with privacy checks called out explicitly.
- `frontend` is organized around user-facing features and a shared API client; it consumes an agreed backend contract and does not implement policy decisions.

The structure is a proposal for review, not approval of any reserved technology or product decision.