-- Public institutional facts and neutral configuration placeholders. Run after schema.sql.
-- Public source for the institution name: https://funaab.edu.ng/ (accessed 2026-11-07).
-- Do not add guessed catalogue, student-domain, timetable, or contact data.
-- Synthetic reports and delivery scenarios belong in isolated test fixtures, not this seed.

-- Tunables (decide real defaults later)
INSERT INTO trust_weights (factor, weight) VALUES
  ('school_email',   0.40),
  ('phone_otp',      0.10),
  ('timetable_match',0.30);

INSERT INTO platform_settings (key, value, note) VALUES
  ('min_supporters_tier1',  3,   'PLACEHOLDER: distinct students for public aggregate stats'),
  ('min_total_trust_tier1', 2.0, 'PLACEHOLDER'),
  ('min_supporters_tier2',  5,   'PLACEHOLDER: stricter bar for private delivery naming a lecturer'),
  ('min_total_trust_tier2', 4.0, 'PLACEHOLDER'),
  ('per_supporter_cap',     1.0, 'PLACEHOLDER: max score any one student can add'),
  ('panel_size',            3,   'PLACEHOLDER: independent model votes per decision'),
  ('appeal_panel_size',     5,   'PLACEHOLDER: larger panel for appeals'),
  ('panel_min_confidence',  0.80,'PLACEHOLDER: calibrated confidence below this counts as abstain'),
  ('hold_ttl_days',         14,  'PLACEHOLDER: how long an uncertain finding is held collecting evidence'),
  ('dashboard_min_group',   3,   'Hide dashboard groups smaller than this (anonymity)'),
  ('reports_per_week',      5,   'PLACEHOLDER: per-student weekly report limit');

INSERT INTO circuit_breakers (name) VALUES ('publish'), ('private_delivery'), ('model_panel');

-- Verified public institution identity. Student email domain confirmed by the
-- project owner, a current FUNAAB student, as 'student.funaab.edu.ng'
-- (distinct from the general staff/public domain 'funaab.edu.ng').
-- Observed address pattern: {surname}{given-name-initials}.{2-digit admission
-- year}@student.funaab.edu.ng (e.g. 'surnametl.26@student.funaab.edu.ng' for a
-- student admitted in 2026). This pattern is evidence only for domain
-- verification; it encodes no department, and the admission-year digits alone
-- cannot reliably derive a current level (deferrals/retakes/slow semesters
-- break that assumption without a verified academic calendar). Department and
-- level therefore remain self-declared and timetable-weighted, not derived
-- from the email.
INSERT INTO universities (name, short_name, email_domain)
VALUES ('Federal University of Agriculture, Abeokuta', 'FUNAAB', 'student.funaab.edu.ng');

-- 2026/2027 academic calendar, supplied by the project owner as
-- docs/data/school_calendar26-27.jpg. The source document's own title reads
-- "PROPOSED 2026/2027 SESSION ACADEMIC CALENDAR" (FUNAAB), so status is
-- 'proposed': these dates may still shift before a final calendar is issued.
-- Update this row (and bump status to 'confirmed') once a final version appears.
INSERT INTO academic_sessions (
  university_id, session, status,
  fresh_registration_starts, returning_registration_starts,
  late_registration_starts, late_registration_ends, matriculation_date,
  first_semester_lectures_start, first_semester_lectures_end,
  first_semester_exams_start, first_semester_exams_end,
  second_semester_lectures_start, second_semester_lectures_end,
  second_semester_exams_start, second_semester_exams_end,
  session_ends, source
)
SELECT id, '2026/2027', 'proposed',
  DATE '2026-09-07', DATE '2026-09-14',
  DATE '2026-10-24', DATE '2026-11-15', DATE '2026-11-18',
  DATE '2026-09-21', DATE '2026-12-18',
  DATE '2027-01-04', DATE '2027-01-22',
  DATE '2027-02-15', DATE '2027-05-14',
  DATE '2027-05-24', DATE '2027-06-11',
  DATE '2027-07-29',
  'docs/data/school_calendar26-27.jpg, supplied by the project owner. Source title: "Proposed 2026/2027 Session Academic Calendar" (FUNAAB); provisional until a confirmed calendar supersedes it.'
FROM universities WHERE short_name = 'FUNAAB';

