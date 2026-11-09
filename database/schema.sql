-- =====================================================================
-- VIO (Voice It Out): PostgreSQL 15+ schema
-- Principles:
--   1. A single report is a claim; a FINDING (clustered, confirmed, moderated)
--      is what gets routed and published.
--   2. Students sign in with a student school email and are identified only by a salted hash.
--      Raw emails, matric numbers and names are NEVER stored.
--   3. Tunable numbers live in tables (trust_weights, platform_settings),
--      not in code.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------- ENUMS ----------------------------------------------------
CREATE TYPE report_category AS ENUM (
  'class_not_held', 'practical_not_held', 'outline_incomplete',
  'poor_delivery', 'unfair_assessment', 'unresolved_complaint',
  'other_academic', 'institutional'
);
CREATE TYPE finding_status   AS ENUM ('collecting', 'held', 'cleared', 'published', 'rejected', 'disputed');
CREATE TYPE delivery_status  AS ENUM ('queued', 'sent', 'viewed', 'acknowledged', 'responded', 'escalated', 'expired');
CREATE TYPE authority_role   AS ENUM ('hod', 'dean', 'student_affairs', 'dvc_academic', 'registry', 'vice_chancellor');
CREATE TYPE verification_factor AS ENUM ('school_email', 'phone_otp', 'timetable_match');
CREATE TYPE notice_kind      AS ENUM ('cancelled', 'rescheduled', 'extra_class');
CREATE TYPE account_status   AS ENUM ('active', 'suspended');
CREATE TYPE response_outcome AS ENUM ('action_taken', 'explanation_accepted', 'disputed', 'no_action');
CREATE TYPE reply_reason     AS ENUM ('illness', 'official_duty', 'rescheduled', 'venue_issue', 'disputed', 'other');
CREATE TYPE slot_type        AS ENUM ('lecture', 'practical', 'tutorial');
CREATE TYPE evidence_kind    AS ENUM ('timetable_image', 'photo', 'document', 'other');
CREATE TYPE panel_role       AS ENUM ('extractor', 'safety', 'consistency', 'red_team', 'summary_check');
CREATE TYPE vote_verdict     AS ENUM ('pass', 'block', 'abstain');
CREATE TYPE breaker_state    AS ENUM ('closed', 'open');            -- closed = normal operation
CREATE TYPE golden_label     AS ENUM ('genuine', 'fake', 'abusive', 'injection', 'coordinated');
CREATE TYPE eval_source      AS ENUM ('nightly', 'canary', 'pre_deploy');
CREATE TYPE appellant_kind   AS ENUM ('lecturer', 'authority', 'student');
CREATE TYPE appeal_status    AS ENUM ('open', 'upheld', 'overturned', 'dismissed');

-- ---------- 1. INSTITUTION STRUCTURE ---------------------------------
CREATE TABLE universities (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text   NOT NULL UNIQUE,
  short_name   text   NOT NULL UNIQUE,
  email_domain citext            -- used for school-email verification
);

CREATE TABLE faculties (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  university_id uuid NOT NULL REFERENCES universities(id) ON DELETE CASCADE,
  name          text NOT NULL,
  UNIQUE (university_id, name)
);

CREATE TABLE departments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  faculty_id uuid NOT NULL REFERENCES faculties(id) ON DELETE CASCADE,
  name       text NOT NULL,
  UNIQUE (faculty_id, name)
);

CREATE TABLE courses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  code          text NOT NULL,
  title         text NOT NULL,
  level         smallint NOT NULL CHECK (level IN (100, 200, 300, 400, 500, 600)),
  UNIQUE (department_id, code)
);

-- Which courses a department offers at which level (shared courses appear in
-- several departments). Used to check a student's timetable overlap.
CREATE TABLE curriculum_entries (
  department_id uuid NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  course_id     uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  level         smallint NOT NULL,
  semester      smallint NOT NULL CHECK (semester IN (1, 2)),
  is_elective   boolean NOT NULL DEFAULT false,
  source        text NOT NULL DEFAULT 'manual'
                CHECK (source IN ('manual', 'handbook', 'timetable', 'courseform')),
  PRIMARY KEY (department_id, course_id, level)
);

-- Official ("general") timetable fed into the system.
CREATE TABLE timetable_slots (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id        uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  academic_session text NOT NULL,                       -- e.g. '2026/2027'
  semester         smallint NOT NULL CHECK (semester IN (1, 2)),
  day_of_week      smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  start_time       time NOT NULL,
  end_time         time NOT NULL,
  venue            text,
  kind             slot_type NOT NULL DEFAULT 'lecture',
  CHECK (end_time > start_time)
);
CREATE INDEX timetable_slots_course_idx ON timetable_slots (course_id, academic_session);

-- Lecturers are PRIVATE: visible only to the relevant authority (tier-2 delivery).
CREATE TABLE lecturers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  full_name     text NOT NULL,
  email         citext UNIQUE
);

CREATE TABLE course_lecturers (
  course_id        uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  lecturer_id      uuid NOT NULL REFERENCES lecturers(id) ON DELETE CASCADE,
  academic_session text NOT NULL,
  PRIMARY KEY (course_id, lecturer_id, academic_session)
);

-- ---------- 2. AUTHORITIES & ROUTING ---------------------------------
-- HOD rows are scoped to a department, Dean rows to a faculty,
-- all other roles are university-wide.
CREATE TABLE authorities (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  university_id uuid NOT NULL REFERENCES universities(id) ON DELETE CASCADE,
  role          authority_role NOT NULL,
  faculty_id    uuid REFERENCES faculties(id),
  department_id uuid REFERENCES departments(id),
  full_name     text   NOT NULL,
  email         citext NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  CHECK (
    (role = 'hod'  AND department_id IS NOT NULL) OR
    (role = 'dean' AND faculty_id    IS NOT NULL) OR
    (role NOT IN ('hod', 'dean'))
  )
);
-- HODs rotate: only one ACTIVE holder per department / faculty / university role.
CREATE UNIQUE INDEX one_active_hod  ON authorities (department_id) WHERE role = 'hod'  AND is_active;
CREATE UNIQUE INDEX one_active_dean ON authorities (faculty_id)    WHERE role = 'dean' AND is_active;
CREATE UNIQUE INDEX one_active_uni_role ON authorities (university_id, role)
  WHERE role NOT IN ('hod', 'dean') AND is_active;

-- Escalation ladder per category: step 1 gets it first, wait_days later step 2, ...
-- Resolve target: hod -> course.department's HOD; dean -> that faculty's Dean;
-- others -> the university-level authority with that role.
CREATE TABLE routing_steps (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  university_id  uuid NOT NULL REFERENCES universities(id) ON DELETE CASCADE,
  category       report_category NOT NULL,
  step_order     smallint NOT NULL CHECK (step_order >= 1),
  authority_role authority_role NOT NULL,
  wait_days      smallint NOT NULL CHECK (wait_days > 0),
  UNIQUE (university_id, category, step_order)
);

-- ---------- 3. STUDENT IDENTITY (hashed) -----------------------------
-- Sign-in is by student school email only (other domains rejected).
-- identity_hash = HMAC-SHA256(server_secret, normalised school email).
-- The raw email is NOT stored. It enforces one account per student.
-- department_id / level are self-declared and weighed by the timetable check.
CREATE TABLE student_accounts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  university_id uuid NOT NULL REFERENCES universities(id),
  department_id uuid NOT NULL REFERENCES departments(id),
  level         smallint NOT NULL,
  identity_hash bytea NOT NULL,
  status        account_status NOT NULL DEFAULT 'active',
  confirmed_session text,                         -- department/level re-confirmed each session
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (university_id, identity_hash)
);

CREATE TABLE student_verifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  uuid NOT NULL REFERENCES student_accounts(id) ON DELETE CASCADE,
  factor      verification_factor NOT NULL,
  passed      boolean NOT NULL,
  score       numeric(5,2),            -- e.g. timetable overlap count/ratio
  verified_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (student_id, factor)
);

-- Which courses a student is registered for this session.
-- Only registered students may report on / confirm a course.
CREATE TABLE student_course_registrations (
  student_id       uuid NOT NULL REFERENCES student_accounts(id) ON DELETE CASCADE,
  course_id        uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  academic_session text NOT NULL,
  PRIMARY KEY (student_id, course_id, academic_session)
);

-- ---------- 4. TUNABLE CONFIG ----------------------------------------
CREATE TABLE trust_weights (
  factor verification_factor PRIMARY KEY,
  weight numeric(5,2) NOT NULL CHECK (weight >= 0)
);

CREATE TABLE platform_settings (
  key   text PRIMARY KEY,
  value numeric NOT NULL,
  note  text
);

-- Trust score = base (unverified) + weights of passed factors.
CREATE VIEW student_trust AS
SELECT s.id AS student_id,
       0.20 + COALESCE(SUM(w.weight) FILTER (WHERE v.passed), 0) AS trust_score  -- 0.20 base: tunable
FROM student_accounts s
LEFT JOIN student_verifications v ON v.student_id = s.id
LEFT JOIN trust_weights w         ON w.factor = v.factor
GROUP BY s.id;

-- ---------- 5. MODEL REGISTRY, SAFETY SWITCHES, EVALUATION ----------
-- Every model/prompt version that can vote is pinned here. Panel members should
-- come from DIFFERENT model families so their errors are not correlated.
CREATE TABLE model_registry (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role           panel_role NOT NULL,
  provider       text NOT NULL,
  model          text NOT NULL,
  version        text NOT NULL,
  prompt_version text NOT NULL,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role, provider, model, version, prompt_version)
);

-- Automatic circuit breakers. When evaluation or drift checks fail, a breaker
-- opens and the system degrades to a safer tier (e.g. stop private delivery).
CREATE TABLE circuit_breakers (
  name        text PRIMARY KEY,                  -- 'publish', 'private_delivery', 'model_panel'
  state       breaker_state NOT NULL DEFAULT 'closed',
  reason      text,
  tripped_at  timestamptz,
  reset_after timestamptz
);

-- Labelled cases used for nightly evaluation, canary runs and pre-deploy checks.
CREATE TABLE golden_cases (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label      golden_label NOT NULL,
  payload    jsonb NOT NULL,
  expected   vote_verdict NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE eval_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source          eval_source NOT NULL,
  model_id        uuid REFERENCES model_registry(id),
  precision_score numeric(5,4),
  recall_score    numeric(5,4),
  per_label       jsonb,
  passed          boolean NOT NULL,
  ran_at          timestamptz NOT NULL DEFAULT now()
);

-- ---------- 6. FINDINGS, REPORTS, CONFIRMATIONS ----------------------
-- One finding = one incident (course + date + category [+ slot]).
-- Many reports and confirmations attach to it.
CREATE TABLE findings (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id      uuid NOT NULL REFERENCES courses(id),
  category       report_category NOT NULL,
  incident_date  date NOT NULL,
  slot_id        uuid REFERENCES timetable_slots(id),
  status         finding_status NOT NULL DEFAULT 'collecting',
  public_summary text,              -- anonymised, model-drafted and rule-checked, shown on dashboard
  created_at     timestamptz NOT NULL DEFAULT now(),
  clearance_tier smallint NOT NULL DEFAULT 0 CHECK (clearance_tier BETWEEN 0 AND 2),
                                 -- 0 store only, 1 aggregate stats public, 2 private delivery to authority
  held_until     timestamptz,    -- uncertain findings wait here; new evidence re-triggers evaluation
  cleared_at     timestamptz
);
CREATE UNIQUE INDEX findings_one_per_incident
  ON findings (course_id, incident_date, category,
               COALESCE(slot_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX findings_status_idx ON findings (status);

-- reporter_id is NEVER exposed via API/dashboard; restrict with row-level security.
CREATE TABLE reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_code text NOT NULL UNIQUE,            -- shown to the student
  reporter_id   uuid NOT NULL REFERENCES student_accounts(id),
  finding_id    uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  description   text NOT NULL CHECK (length(description) <= 2000),
  notice_given  boolean,                         -- did the lecturer announce the absence?
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (finding_id, reporter_id)
);
CREATE INDEX reports_finding_idx ON reports (finding_id);

CREATE TABLE finding_confirmations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES student_accounts(id),
  comment    text CHECK (length(comment) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (finding_id, student_id)
);

-- Evidence (e.g. timetable photos). Strip metadata; delete after retention window.
CREATE TABLE report_evidence (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id         uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  kind              evidence_kind NOT NULL,
  storage_key       text NOT NULL,
  sha256            text NOT NULL,
  metadata_stripped boolean NOT NULL DEFAULT false,
  delete_after      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- A student cannot both report and confirm the same finding (independence).
CREATE FUNCTION forbid_double_support() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'finding_confirmations' THEN
    IF EXISTS (SELECT 1 FROM reports r
               WHERE r.finding_id = NEW.finding_id AND r.reporter_id = NEW.student_id) THEN
      RAISE EXCEPTION 'reporter cannot also confirm the same finding';
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM finding_confirmations c
               WHERE c.finding_id = NEW.finding_id AND c.student_id = NEW.reporter_id) THEN
      RAISE EXCEPTION 'confirmer cannot also report the same finding';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER confirmations_independence BEFORE INSERT ON finding_confirmations
  FOR EACH ROW EXECUTE FUNCTION forbid_double_support();
CREATE TRIGGER reports_independence BEFORE INSERT ON reports
  FOR EACH ROW EXECUTE FUNCTION forbid_double_support();

-- Distinct supporters per finding and their summed trust.
-- App rule (thresholds are settings): move to 'pending_review' when
-- supporters >= min_supporters AND total_trust >= min_total_trust.
CREATE VIEW finding_support AS
WITH supporters AS (
  SELECT finding_id, reporter_id AS student_id FROM reports
  UNION
  SELECT finding_id, student_id FROM finding_confirmations
)
SELECT f.id AS finding_id,
       COUNT(s.student_id)                 AS supporters,
       COALESCE(SUM(t.trust_score), 0)     AS total_trust
FROM findings f
LEFT JOIN supporters s    ON s.finding_id = f.id
LEFT JOIN student_trust t ON t.student_id = s.student_id
GROUP BY f.id;

-- ---------- 6b. AUTOMATED ADJUDICATION -------------------------------
-- A panel of independent models votes on a report, finding or appeal.
-- Report text is UNTRUSTED input: pass it as data, require structured output,
-- and never let a model write status columns. Only the deterministic gate does.
CREATE TABLE panel_votes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type text NOT NULL CHECK (subject_type IN ('report', 'finding', 'appeal')),
  subject_id   uuid NOT NULL,
  round        smallint NOT NULL DEFAULT 1,
  role         panel_role NOT NULL,
  model_id     uuid NOT NULL REFERENCES model_registry(id),
  verdict      vote_verdict NOT NULL,
  confidence   numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),   -- CALIBRATED, not self-reported
  reasons      jsonb,                                              -- cited spans, rule hits
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subject_type, subject_id, round, role, model_id)
);
CREATE INDEX panel_votes_subject_idx ON panel_votes (subject_type, subject_id, round);

-- Signals that discount a supporter's weight (bursts of new accounts, similar text...).
CREATE TABLE anomaly_signals (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES student_accounts(id) ON DELETE CASCADE,
  kind       text NOT NULL,
  severity   numeric(4,3) NOT NULL CHECK (severity BETWEEN 0 AND 1),
  detail     jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Every score is stored with its full breakdown so it can be recomputed and audited.
CREATE TABLE finding_scores (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id      uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  formula_version text NOT NULL,
  score           numeric(8,3) NOT NULL,
  supporters      integer NOT NULL,
  breakdown       jsonb NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX finding_scores_latest ON finding_scores (finding_id, computed_at DESC);

CREATE VIEW finding_latest_score AS
SELECT DISTINCT ON (finding_id) finding_id, score, supporters, formula_version, computed_at
FROM finding_scores
ORDER BY finding_id, computed_at DESC;

-- Append-only, hash-chained decision log: entry_hash = H(prev_hash || canonical row).
-- Compute hashes in the app. Lets anyone verify no decision was altered afterwards.
CREATE TABLE decision_log (
  id         bigserial PRIMARY KEY,
  finding_id uuid REFERENCES findings(id) ON DELETE SET NULL,
  stage      text NOT NULL,          -- 'gate', 'score', 'panel', 'appeal', 'breaker', 'delivery' ...
  actor      text NOT NULL,          -- component name, e.g. 'gate_v1', 'safety_model'
  decision   text NOT NULL,
  details    jsonb,
  prev_hash  bytea,
  entry_hash bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Automated appeals: a fresh, larger panel re-adjudicates with the new evidence.
CREATE TABLE appeals (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id   uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  appellant    appellant_kind NOT NULL,
  lecturer_id  uuid REFERENCES lecturers(id),
  authority_id uuid REFERENCES authorities(id),
  report_id    uuid REFERENCES reports(id),
  body         text NOT NULL CHECK (length(body) <= 2000),
  status       appeal_status NOT NULL DEFAULT 'open',
  round        smallint NOT NULL DEFAULT 1 CHECK (round BETWEEN 1 AND 2),
  created_at   timestamptz NOT NULL DEFAULT now(),
  decided_at   timestamptz,
  CHECK ((appellant = 'lecturer'  AND lecturer_id  IS NOT NULL) OR
         (appellant = 'authority' AND authority_id IS NOT NULL) OR
         (appellant = 'student'   AND report_id    IS NOT NULL)),
  UNIQUE (finding_id, appellant, round)
);

-- ---------- 7. LECTURER SIDE -----------------------------------------
-- Advance notices give lecturers a reason to use the platform and
-- help auto-flag reports about classes that were announced as cancelled.
CREATE TABLE class_notices (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  lecturer_id uuid NOT NULL REFERENCES lecturers(id),
  kind        notice_kind NOT NULL,
  for_date    date NOT NULL,
  new_start   timestamptz,
  note        text,
  posted_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX class_notices_lookup ON class_notices (course_id, for_date);

CREATE TABLE lecturer_replies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id  uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  lecturer_id uuid NOT NULL REFERENCES lecturers(id),
  reason      reply_reason NOT NULL,
  body        text NOT NULL CHECK (length(body) <= 2000),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Was an announcement posted BEFORE the incident date? (lowers report weight / auto-flags)
CREATE VIEW finding_notice_check AS
SELECT f.id AS finding_id,
       EXISTS (SELECT 1 FROM class_notices n
               WHERE n.course_id = f.course_id
                 AND n.for_date  = f.incident_date
                 AND n.posted_at < (f.incident_date)::timestamptz) AS announced_in_advance
FROM findings f;

-- ---------- 8. DELIVERY & ESCALATION ---------------------------------
CREATE TABLE deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id      uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
  authority_id    uuid NOT NULL REFERENCES authorities(id),
  step_order      smallint NOT NULL CHECK (step_order >= 1),
  status          delivery_status NOT NULL DEFAULT 'queued',
  token_hash      bytea NOT NULL UNIQUE,         -- hash of the secure no-login link token
  queued_at       timestamptz NOT NULL DEFAULT now(),
  sent_at         timestamptz,
  viewed_at       timestamptz,                   -- set when the secure link is opened
  acknowledged_at timestamptz,
  responded_at    timestamptz,
  due_at          timestamptz,                   -- sent_at + routing_steps.wait_days
  UNIQUE (finding_id, step_order)
);
CREATE INDEX deliveries_due_idx ON deliveries (due_at) WHERE status IN ('sent', 'viewed');
CREATE INDEX deliveries_finding_idx ON deliveries (finding_id);

CREATE TABLE authority_responses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  outcome     response_outcome NOT NULL,
  body        text NOT NULL CHECK (length(body) <= 4000),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- A daily worker reads this, marks rows 'escalated', and queues the next step.
CREATE VIEW deliveries_to_escalate AS
SELECT d.*
FROM deliveries d
WHERE d.status IN ('sent', 'viewed')            -- never acknowledged
  AND d.due_at <= now()
  AND NOT EXISTS (SELECT 1 FROM deliveries n
                  WHERE n.finding_id = d.finding_id AND n.step_order > d.step_order);

-- ---------- 9. PUBLIC / ACCOUNTABILITY VIEWS -------------------------
-- Aggregates only, never lecturer names. Groups smaller than
-- dashboard_min_group are hidden (protects anonymity in small classes).
CREATE VIEW public_dashboard AS
SELECT d.id   AS department_id,
       d.name AS department,
       f.category,
       date_trunc('month', f.incident_date)::date AS month,
       COUNT(*) AS findings
FROM findings f
JOIN courses c     ON c.id = f.course_id
JOIN departments d ON d.id = c.department_id
WHERE f.status = 'published'
GROUP BY d.id, d.name, f.category, date_trunc('month', f.incident_date)
HAVING COUNT(*) >= COALESCE((SELECT value FROM platform_settings WHERE key = 'dashboard_min_group'), 3);

-- Responsiveness of authorities (hours from sent to acknowledged).
CREATE VIEW authority_response_stats AS
SELECT a.id AS authority_id, a.role, a.department_id, a.faculty_id,
       COUNT(*)                                                     AS deliveries,
       COUNT(*) FILTER (WHERE dl.acknowledged_at IS NOT NULL)       AS acknowledged,
       ROUND(AVG(EXTRACT(EPOCH FROM (dl.acknowledged_at - dl.sent_at)) / 3600)::numeric, 1)
                                                                    AS avg_hours_to_acknowledge
FROM deliveries dl
JOIN authorities a ON a.id = dl.authority_id
WHERE dl.sent_at IS NOT NULL
GROUP BY a.id, a.role, a.department_id, a.faculty_id;

-- ---------- 10. PRIVACY NOTES (implement in the app / RLS) -----------
-- * reports.reporter_id, finding_confirmations.student_id: never returned by
--   any public or authority-facing query; models and operators see trust scores, not identity.
-- * lecturers / lecturer names: visible only to the relevant HOD/Dean (tier-2 delivery), never public.
-- * Strip identifiers before any text is sent to an external model provider.
-- * Delete report_evidence files after delete_after; strip EXIF before storing.
