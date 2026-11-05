# VIO Frontend Flows

This document defines the expected frontend experience, not backend processing internals. Endpoint paths and payloads are proposed in [the API endpoint proposal](../api/ENDPOINT_PROPOSAL.md) and require joint approval before frontend implementation depends on them.

The frontend is part of the VIO repository under `frontend/`; frontend developers own its implementation. The target is a real deployment architecture, not a demo-only frontend or demo dataset. School integrations and official institutional data may be unavailable; show that as an explicit setup/unavailable state rather than fake production behavior.

## Browser Routes

| Browser route | Audience | Screen purpose |
| --- | --- | --- |
| `/` | Public | Identify VIO and offer dashboard and student sign-in entry points |
| `/dashboard` | Public | Browse aggregate accountability data |
| `/sign-in` | Student | Select university and request one-time email verification |
| `/sign-in/verify` | Student | Enter code or complete link verification |
| `/setup` | Student | Declare department/level and confirm academic session |
| `/setup/timetable` | Student | Upload timetable and view verification outcome |
| `/student` | Student | Setup state, own reports, registered courses, and primary actions |
| `/student/reports/new` | Student | File a factual report |
| `/student/reports/:trackingCode` | Student | View own report and safe status timeline |
| `/student/findings` | Student | Browse findings the backend says are confirmable |
| `/student/findings/:findingId` | Student | Read non-identifying detail and confirm if allowed |
| `/lecturer/access` | Lecturer | Redeem private one-time link |
| `/lecturer/findings/:findingId` | Lecturer | Read anonymised summary, reply, or appeal |
| `/lecturer/notices` | Lecturer | Post advance notice for a course/date |
| `/authority/access` | Authority | Redeem private one-time delivery link |
| `/authority/deliveries/:deliveryId` | Authority | Review authorized delivery, acknowledge, respond, or appeal |
| `/access-expired` | Link recipient | Explain expired, used, invalid, or revoked link and give a safe next step |

Protected routes return to sign-in and then the intended route after authentication. Secure-link routes must not display protected information until backend redemption succeeds. Do not put access tokens in analytics or client logs.

## Public Visitor Flow

1. The home screen names the service VIO and makes “View dashboard” and “Student sign in” the primary choices.
2. The dashboard loads aggregate data. Filters are shown only when supplied by the backend.
3. Every chart/table has a plain-language title, period, and meaning. An empty result is a normal empty state, not evidence that no problems exist.
4. There is no drill-down to individual reports or incidents. Never show lecturer/student/reporter/confirmer names or IDs, tracking codes, or report text.

## Student Sign-In and Setup

1. On `/sign-in`, student chooses a university and enters a school email. Explain that email verifies eligibility and is not shown on reports.
2. After request, replace the form with verification UI: masked destination, code field if codes are used, resend countdown, and a way to correct the address. Do not reveal whether the email already has an account.
3. After successful verification, route by backend-provided setup state: profile/session setup to `/setup`, timetable verification to `/setup/timetable`, or completed setup to `/student`.
4. On `/setup`, student selects department and level from configured options and confirms the current academic session. If the university catalogue/session is unavailable, state that setup is blocked pending data; do not invent choices.
5. On `/setup/timetable`, state accepted file formats/size from backend configuration, show upload progress, and offer remove/retry. Show processing, then a completed result. Only show extracted/matched codes if the backend explicitly permits it.
6. If timetable verification fails, explain that a student may continue with reduced verification only when the backend says that action is allowed. Do not claim reports are forbidden unless told by the backend.
7. `/student` summarizes setup completeness, available registered courses, the student's own recent reports, and a primary “File a report” action. Do not reveal other students' activity.

## Student Report Journey

1. `/student/reports/new` presents only registered courses returned by the backend. Do not imply the student is registered for the whole catalogue.
2. Collect course, incident date, timetable slot where available, category, and factual description. Show the 2,000-character maximum and live remaining count. Do not ask the student to enter a lecturer name.
3. Before submit, show a review step with all chosen fields and an edit action. Explain that one report is a claim, not an established finding.
4. On submit, prevent accidental double click and show progress. Preserve values after recoverable network failure. Present server validation/rate-limit/duplicate/registration errors in context using safe server messages.
5. On success, show the tracking code once, a copy action, and a link to `/student/reports/:trackingCode`. Explain neutrally that the report is being assessed and is not yet a finding or public accusation.
6. The tracking page shows only this student's report and a curated timeline returned by the backend. Do not derive timeline events from internal logs or reveal model prompts/votes, other supporters, anomaly signals, score breakdowns, or identity data.

## Student Confirmation Journey

1. `/student/findings` lists only findings the backend says the student may confirm. Each row has course, date, category, neutral anonymised summary, and display-safe status.
2. Detail explains what confirmation means; it must not be framed as a vote on a lecturer's character.
3. The backend filters out unregistered courses, findings the student reported, duplicates, and statuses where confirmation is not allowed. The frontend still handles a race where eligibility changes before submit.
4. Student can add an optional factual comment within the returned limit and confirm. On success, refresh status and show a neutral confirmation.
5. Do not show confirmation counts unless the backend explicitly provides a privacy-safe count.

## Lecturer Journey

1. Lecturer opens a private link on `/lecturer/access`. Submit it to backend redemption; do not treat possession of the URL as continuing authorization.
2. On success, show only course, incident date, category, anonymised summary, reply deadline, and allowed actions.
3. Lecturer can submit a reasoned reply or appeal. Show character limits, review-before-submit, progress, success, and safe validation/errors.
4. `/lecturer/notices` collects authorized course, notice kind, date, optional new start time, and short note. After success, show the posted notice and date.
5. Never show student identities, raw reports, tracking codes, confirmation comments, or identity-linked metadata. Used, expired, revoked, or unauthorized links go to `/access-expired` without confirming whether an underlying person/finding exists.

## Authority Journey

1. Authority opens a one-time delivery link on `/authority/access` and redeems it with the backend.
2. Successful access opens the delivery task. Show only data allowed for that clearance tier. A lecturer name may appear only in authorized tier-2 delivery data; student identities and report/confirmation records never appear.
3. Authority can acknowledge receipt, submit a response with an allowed outcome, or file an appeal. Use review/confirm before final submit and show resulting delivery state.
4. Show status and escalation context as returned by the backend; the frontend never calculates or triggers escalation.
5. For disputed findings or open appeals, explain that new delivery actions are unavailable until backend permissions change.

## Shared Interaction and Presentation Rules

- Provide relevant loading, empty, success, validation, forbidden, expired-link, unavailable, and retry states on every workflow.
- Render backend statuses and `available_actions`; never calculate trust, supporter thresholds, clearance, publication, routing, escalation, or appeal outcomes in frontend code.
- Distinguish `collecting`, `held`, `cleared`, `published`, `rejected`, and `disputed`. `Cleared` is not the same as `published`.
- Held/disputed reports are not public and have no new delivery. Use neutral language and never imply a claim is substantiated before the backend says so.
- Do not display raw model confidence or reasoning as a decision.
- Do not retry non-idempotent actions automatically unless using the agreed idempotency key.
- Support keyboard operation, visible focus, labeled inputs, screen-reader announcements for async status, and narrow-screen layouts.

## Folder Ownership

`frontend/` is part of this repository, reserved for frontend developers. The current structure is framework-neutral: feature folders map to user workflows; `shared/api` owns the eventual API client; `shared/types` owns agreed/generated request and response types; `tests` holds frontend checks. Do not select a UI framework or install packages until the frontend team agrees on that stack.