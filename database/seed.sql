-- Fictional demo data for the hackathon prototype. Run after schema.sql.
-- All names, emails and numbers are made up. Tunable values are PLACEHOLDERS.

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

-- Institution
INSERT INTO universities (name, short_name, email_domain)
VALUES ('Demo State University', 'DSU', 'students.dsu.example');

INSERT INTO faculties (university_id, name)
SELECT id, 'Faculty of Science' FROM universities WHERE short_name = 'DSU';

INSERT INTO departments (faculty_id, name)
SELECT id, 'Computer Science' FROM faculties WHERE name = 'Faculty of Science';

INSERT INTO courses (department_id, code, title, level)
SELECT d.id, v.code, v.title, v.level
FROM departments d,
     (VALUES ('CSC 201', 'Intro to Programming II', 200),
             ('CSC 305', 'Operating Systems',        300),
             ('CSC 411', 'Machine Learning',         400)) AS v(code, title, level)
WHERE d.name = 'Computer Science';

-- Authorities (fictional contacts)
INSERT INTO authorities (university_id, role, faculty_id, department_id, full_name, email)
SELECT u.id, 'hod', NULL, d.id, 'Prof. Demo HOD', 'hod.cs@dsu.example'
FROM universities u, departments d WHERE d.name = 'Computer Science';

INSERT INTO authorities (university_id, role, faculty_id, department_id, full_name, email)
SELECT u.id, 'dean', f.id, NULL, 'Prof. Demo Dean', 'dean.science@dsu.example'
FROM universities u, faculties f WHERE f.name = 'Faculty of Science';

INSERT INTO authorities (university_id, role, full_name, email)
SELECT id, 'dvc_academic',   'Prof. Demo DVC Academic', 'dvc.academic@dsu.example' FROM universities;
INSERT INTO authorities (university_id, role, full_name, email)
SELECT id, 'student_affairs','Demo Dean of Student Affairs', 'studentaffairs@dsu.example' FROM universities;
INSERT INTO authorities (university_id, role, full_name, email)
SELECT id, 'vice_chancellor','Prof. Demo Vice-Chancellor', 'vc@dsu.example' FROM universities;

-- Escalation ladders (wait_days are placeholders)
INSERT INTO routing_steps (university_id, category, step_order, authority_role, wait_days)
SELECT u.id, c.category, s.step_order, s.role, s.wait_days
FROM universities u,
     (VALUES ('class_not_held'::report_category), ('practical_not_held'), ('outline_incomplete'),
             ('poor_delivery'), ('unfair_assessment'), ('unresolved_complaint'), ('other_academic')) AS c(category),
     (VALUES (1, 'hod'::authority_role, 14), (2, 'dean', 14), (3, 'dvc_academic', 14)) AS s(step_order, role, wait_days);

INSERT INTO routing_steps (university_id, category, step_order, authority_role, wait_days)
SELECT u.id, 'institutional', s.step_order, s.role, s.wait_days
FROM universities u,
     (VALUES (1, 'student_affairs'::authority_role, 14), (2, 'dvc_academic', 14), (3, 'vice_chancellor', 14))
     AS s(step_order, role, wait_days);

-- A lecturer and a timetable slot for the demo
INSERT INTO lecturers (department_id, full_name, email)
SELECT id, 'Dr. Demo Lecturer', 'lecturer1@dsu.example' FROM departments WHERE name = 'Computer Science';

INSERT INTO course_lecturers (course_id, lecturer_id, academic_session)
SELECT c.id, l.id, '2026/2027' FROM courses c, lecturers l WHERE c.code = 'CSC 305';

INSERT INTO timetable_slots (course_id, academic_session, semester, day_of_week, start_time, end_time, venue)
SELECT id, '2026/2027', 1, 2, '10:00', '12:00', 'LT 2' FROM courses WHERE code = 'CSC 305';

