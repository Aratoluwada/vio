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

-- Verified public institution identity. The student email domain is intentionally
-- NULL until an official source confirms the domain used for student accounts.
INSERT INTO universities (name, short_name, email_domain)
VALUES ('Federal University of Agriculture, Abeokuta', 'FUNAAB', NULL);

