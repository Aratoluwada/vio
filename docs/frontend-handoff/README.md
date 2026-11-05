# VIO Frontend Handoff

## Scope

VIO contains both backend and frontend areas in this repository. Frontend developers own implementation under `frontend/`; this backend work must produce the contract they integrate with. The target is a real service, not a demo-only frontend or demo dataset. School integrations may block official catalogue/registration data; represent that as unavailable rather than fabricating production records.

The detailed browser routes and screen-by-screen interactions are in [FRONTEND_FLOWS.md](FRONTEND_FLOWS.md). The concrete API path and payload proposal is in [ENDPOINT_PROPOSAL.md](../api/ENDPOINT_PROPOSAL.md). Endpoint names are proposals for us to agree together, not a frozen contract yet.

## User-Facing Flows

### Public dashboard

- Show aggregate accountability statistics only.
- Show only published aggregate output; held, disputed, or merely cleared findings must not appear as public individual items.
- Never display lecturer names, student identities, report text, tracking codes, or individual reporter/confirmation records.
- Omit groups below the approved minimum. The minimum is still undecided; do not hardcode the current seed placeholder as policy.

### Student

- Sign in using a university student email and a one-time code or magic link. The allowed domain comes from university configuration.
- Collect department and level, and ask the student to reconfirm them each academic session.
- Support timetable upload and show verification progress without exposing or retaining the image longer than the backend allows.
- Let the student choose a registered course, incident date, slot, category, and factual description of at most 2,000 characters.
- After successful filing, show a tracking code and a status timeline.
- Let eligible students confirm a finding. Do not offer confirmation to a student who filed a report on that same finding.
- The student-facing timeline may show status and progress, but never another student's identity or confirmation details.

### Lecturer

- Provide a private entry point for advance class notices and replies to a finding.
- Show only the relevant course, incident date, category, and anonymised summary.
- Do not show reporters, confirmers, their account details, or raw identity data.

### Authority

- Provide a private, single-use, expiring-link entry point without a normal password flow for the delivery link.
- Show the tier-2 information authorized for that recipient, including a lecturer name only when the backend grants tier-2 access.
- Support acknowledgement and response, and show the delivery's escalation context.
- Never expose student identities or reporter/confirmation records.

## Status and Interaction Expectations

- Render statuses and permitted actions returned by the backend; do not derive clearance, score, or delivery eligibility in frontend code.
- A held or disputed finding has no public display or new delivery. Explain its status neutrally and do not imply that a claim has been substantiated.
- A rejected submission should receive a safe, user-facing explanation from the backend; do not expose internal model prompts, security signals, or private evidence.
- Handle loading, empty, validation, submission, expired-link, unauthorized, unavailable, and retry states.
- Do not display raw model confidence or model reasoning as if it were a decision.

## Privacy and Security Boundaries

- Never put student emails, identity hashes, account IDs, reporter IDs, or confirmer IDs in public pages, URLs, analytics, or client logs.
- Do not treat obscuring a field in the UI as access control; the backend must enforce authorization.
- Do not log secure-link tokens. Handle them only as required for the authorized action and show a useful expired/used-link state.
- Public output must remain aggregated and non-accusatory. Lecturer names are private tier-2 data only.

## Review Before Frontend Integration

Agree the endpoint paths and payloads, session/link security, role permissions, timeline visibility, data integration behavior, upload rules, dashboard privacy thresholds, and appeal eligibility together. The endpoint proposal lists specific unresolved decisions and current schema gaps. Frontend developers may scaffold screens against typed interfaces, but must not mistake proposed routes or fictional seed data for a live integration contract.