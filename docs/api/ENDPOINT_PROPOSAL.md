# VIO API Endpoint Proposal

Status: **Proposal for joint review. Not yet an approved API contract.**

This proposal describes the backend needed by the planned VIO frontend, based on the product brief and current `schema.sql`. It is not a demo API. Institutional catalogue, student registration, timetable, and authority data must come from an approved school integration or configured source. If that source is unavailable, the API reports an explicit unavailable state; the frontend must not present fictional records as live data.

## Conventions

- Proposed API style: JSON REST under `/api/v1`.
- JSON uses `snake_case` fields to match the SQL. Timetable evidence uses multipart upload.
- Timestamps are ISO 8601 UTC strings; dates are `YYYY-MM-DD`; IDs are opaque UUIDs.
- Proposed session transport is a secure, HttpOnly, SameSite cookie. The browser never receives an identity hash or internal student account ID. This transport choice needs approval.
- Student email is accepted only during verification, normalized and HMACed server-side, then discarded. It is not persisted in the application database.
- Lecturer/authority links are one-time credentials. Proposed redemption exchanges the token in the request body for a short-lived restricted cookie. Tokens must not enter analytics or logs.
- All non-public endpoints require the appropriate authenticated session and role. Authorization is enforced by the backend, never by hiding UI controls.
- Success shape: `{ "data": ..., "meta": ... }`; omit `meta` when empty.
- Lists use cursor pagination: `?limit=&cursor=`. Maximum page size remains to be set.
- Mutating actions should accept an `Idempotency-Key` header to prevent duplicate submits after retries.

### Error shape

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Check the highlighted fields and try again.",
    "fields": { "description": ["Must be 2000 characters or fewer."] },
    "request_id": "opaque-request-reference"
  }
}
```

Proposed common codes: `invalid_request`, `validation_failed`, `unauthenticated`, `forbidden`, `not_found`, `expired_link`, `link_already_used`, `rate_limited`, `duplicate_submission`, `registration_required`, `verification_required`, `conflict`, `service_unavailable`, `internal_error`. Messages must never expose SQL errors, prompts, model output, or internal security signals.

## Public Catalogue and Dashboard

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `GET /universities` | Public | Configured universities and whether student sign-in is enabled. No private contacts. |
| `GET /universities/{university_id}/faculties` | Public | Selectable faculties. |
| `GET /faculties/{faculty_id}/departments` | Public | Selectable departments. |
| `GET /academic-sessions` | Public | Configured current/selectable sessions, or an explicit unavailable response. |
| `GET /public/dashboard` | Public | Published aggregate data only, with approved filters. Never return finding IDs, lecturer names, student IDs, report text, or supporter details. |
| `GET /public/dashboard/filters` | Public | Available date range and filter values without revealing suppressed groups. |

Example dashboard row:

```json
{
  "data": [{
    "period": "2026-10",
    "department": "Department label",
    "category": "class_not_held",
    "findings": 12
  }]
}
```

Dimensions, labels, and the small-group threshold require approval. The seed threshold is a placeholder, not policy.

## Student Authentication and Profile

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `POST /auth/student/email-challenges` | Public | Body `{ "university_id": "uuid", "email": "student@school.example" }`. Send a one-time code/link; return challenge ID, masked destination, expiry, and resend time. Do not reveal whether an account exists. |
| `POST /auth/student/email-challenges/verify` | Public | Verify `{ "challenge_id": "uuid", "code": "..." }` or an agreed magic-link flow. Set session cookie; return minimal session summary. |
| `GET /auth/session` | Authenticated | Return role and setup state, never email, identity hash, or internal account ID. |
| `DELETE /auth/session` | Authenticated | Revoke current session. |
| `GET /student/profile` | Student | Department, level, confirmed session, verification state, and available next actions. |
| `PUT /student/profile` | Student | Set department and level from configured catalogue. |
| `POST /student/profile/confirm-session` | Student | Body `{ "academic_session": "2026/2027" }`; reconfirm current department/level. |
| `GET /student/courses?academic_session=...` | Student | Only courses the backend can verify this student is registered for. Registration synchronization is a school-integration dependency. |

Example `GET /auth/session` response:

```json
{
  "data": {
    "role": "student",
    "setup_state": "timetable_required",
    "academic_session": "2026/2027",
    "available_actions": ["upload_timetable"]
  }
}
```

Proposed setup states: `profile_required`, `session_confirmation_required`, `timetable_required`, `verification_processing`, `ready`, `verification_unavailable`. The state is authoritative; frontend must not reconstruct it from individual factors.

## Timetable Verification

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `POST /student/timetable-verifications` | Student | Multipart `file` plus session metadata. Enforce file type/size, strip metadata, extract codes, compare curriculum, delete image per approved retention policy. Return verification ID and processing/completed state. |
| `GET /student/timetable-verifications/{verification_id}` | Student | Poll status and result. Never return a stored image URL. |

Example result:

```json
{
  "data": {
    "verification_id": "uuid",
    "status": "completed",
    "passed": true,
    "matched_course_count": 4,
    "next_action": "continue"
  }
}
```

Upload limits/storage, whether extracted codes are shown, deletion timing, and match thresholds need approval. The current schema has verification factors but no upload job/status table.

## Reports, Findings, Confirmation, and Tracking

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `GET /student/report-options` | Student | Return allowed categories, description limit, date bounds, registered courses, and form options. |
| `GET /courses/{course_id}/timetable-slots?date=YYYY-MM-DD` | Student | Applicable slots for an eligible registered course/date, or explicit no-schedule state. |
| `POST /student/reports` | Student | Validate and process report. Request below. Return tracking code, safe status/timeline, and permitted actions. |
| `GET /student/reports` | Student | Cursor-paginated reports belonging only to the current student. |
| `GET /student/reports/{tracking_code}` | Student | Return the authenticated owner's report and curated display-safe timeline. Tracking code alone grants no access. |
| `GET /student/findings/confirmable` | Student | Only findings the current student may confirm. Backend checks registration, same-finding report, duplicate confirmation, and status. |
| `GET /student/findings/{finding_id}` | Student | Non-identifying details only if current student may view them. |
| `POST /student/findings/{finding_id}/confirmations` | Student | Add confirmation and optional factual comment. Backend enforces eligibility and reporter/confirmer independence. |
| `POST /student/findings/{finding_id}/appeals` | Student | Appeal only a report/finding the current student is entitled to appeal. Identity is derived from session. |

Example report request:

```json
{
  "course_id": "uuid",
  "incident_date": "2026-10-12",
  "slot_id": null,
  "category": "class_not_held",
  "description": "Factual account of the missed class.",
  "notice_given": null
}
```

Example response:

```json
{
  "data": {
    "tracking_code": "VIO-opaque-code",
    "status": "collecting",
    "message": "Your report was received. It has not been established as a finding.",
    "timeline": [{
      "event": "received",
      "occurred_at": "2026-10-12T12:30:00Z",
      "label": "Report received"
    }],
    "available_actions": []
  }
}
```

Never return reporter/student IDs, identity hashes, supporter identity, model prompts/reasoning, raw anomaly signals, or raw score breakdown. The schema has no dedicated timeline/event table; an application projection or append-only event table needs a decision. The schema currently accepts `notice_given`, while the brief describes notice checking through `class_notices`; reconcile before implementation.

## Lecturer Secure Access

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `POST /auth/lecturer/link-sessions` | Public with link token | Redeem `{ "token": "..." }` once; set short-lived restricted cookie. |
| `GET /lecturer/findings/{finding_id}` | Lecturer session | Course, date, category, anonymised summary, reply deadline, allowed actions only. |
| `POST /lecturer/findings/{finding_id}/replies` | Lecturer session | Submit `{ "reason": "other", "body": "..." }`; validate link scope/window/length. |
| `POST /lecturer/findings/{finding_id}/appeals` | Lecturer session | Submit appeal; derive lecturer identity from link session and enforce max rounds. |
| `GET /lecturer/courses` | Lecturer session | Courses authorized for notices; depends on course/lecturer data. |
| `POST /lecturer/class-notices` | Lecturer session | Submit `{ "course_id": "uuid", "kind": "cancelled", "for_date": "2026-10-12", "new_start": null, "note": "..." }`. |

## Authority Secure Access and Delivery

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `POST /auth/authority/link-sessions` | Public with link token | Redeem one-time delivery link and set short-lived restricted cookie. |
| `GET /authority/deliveries/{delivery_id}` | Authority session | Clearance-authorized details, status, due date, routing step, permitted actions. Lecturer name only when tier-2 authorization permits it. |
| `POST /authority/deliveries/{delivery_id}/acknowledgement` | Authority session | Acknowledge receipt. |
| `POST /authority/deliveries/{delivery_id}/responses` | Authority session | Submit `{ "outcome": "action_taken", "body": "..." }`. |
| `POST /authority/deliveries/{delivery_id}/appeals` | Authority session | Submit appeal; derive authority identity from session and enforce round limits. |

## Operational Endpoints

| Method and path | Auth | Behavior |
| --- | --- | --- |
| `GET /health` | Public or infrastructure-only; decide at deployment | Liveness only. No secrets or private configuration. |
| `GET /ready` | Infrastructure-only | Dependency readiness; keep private or sanitized. |

Scoring, gate, model panel, delivery scheduling, evaluation, and escalation are backend services/workers, not frontend endpoints. The browser requests user actions and reads permitted state; it cannot set scores, statuses, votes, or routing steps.

## Status Contract

Finding enum in SQL: `collecting`, `held`, `cleared`, `published`, `rejected`, `disputed`. Delivery enum: `queued`, `sent`, `viewed`, `acknowledged`, `responded`, `escalated`, `expired`.

The API should supply audience-safe `label`, `description`, and `available_actions` instead of requiring the frontend to interpret internal states. `cleared` is not automatically public; public output is aggregated and published only. `held`, `rejected`, and `disputed` never create new deliveries or public allegations.

## Decisions Required Before Contract Freeze

1. Approve or rename `/api/v1` paths and JSON REST style.
2. Choose cookie sessions or bearer tokens and approve one-time link redemption/session behavior.
3. Decide whether frontend timeline events use a new table or a projection; never expose the internal decision log directly.
4. Define sources/synchronization for university catalogue, sessions, student registrations, timetable slots, lecturers, and authorities. School collaboration may block these integrations; API unavailable states must be specified.
5. Approve upload limits, storage, deletion timing, and whether extracted codes are displayed.
6. Approve dashboard dimensions and small-group suppression policy.
7. Define appeal eligibility by actor/status and exactly which events each role sees.
8. Reconcile schema gaps: no explicit timeline table; `notice_given` versus `class_notices`; no explicit `pending_panel` finding state; and no student-facing projection for scoring/panel progression.

Until these are approved, this endpoint list is concrete for discussion and frontend planning but is not an implementation-ready contract.