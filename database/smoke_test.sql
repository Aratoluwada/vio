DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'pgcrypto extension is missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citext') THEN
    RAISE EXCEPTION 'citext extension is missing';
  END IF;

  IF to_regclass('public.student_trust') IS NULL
     OR to_regclass('public.finding_support') IS NULL
     OR to_regclass('public.public_dashboard') IS NULL
     OR to_regclass('public.deliveries_to_escalate') IS NULL THEN
    RAISE EXCEPTION 'one or more required views are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname = 'confirmations_independence'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname = 'reports_independence'
  ) THEN
    RAISE EXCEPTION 'supporter-independence triggers are missing';
  END IF;

  IF (SELECT COUNT(*) FROM universities) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM universities
       WHERE name = 'Federal University of Agriculture, Abeokuta'
         AND short_name = 'FUNAAB'
         AND email_domain IS NULL
     ) THEN
    RAISE EXCEPTION 'expected verified FUNAAB seed row is missing or incorrect';
  END IF;

  IF (SELECT COUNT(*) FROM trust_weights) <> 3
     OR (SELECT COUNT(*) FROM platform_settings) <> 11
     OR (SELECT COUNT(*) FROM circuit_breakers) <> 3 THEN
    RAISE EXCEPTION 'expected seed configuration counts do not match';
  END IF;

  IF EXISTS (SELECT 1 FROM courses)
     OR EXISTS (SELECT 1 FROM lecturers)
     OR EXISTS (SELECT 1 FROM authorities) THEN
    RAISE EXCEPTION 'unverified catalogue or delivery-contact data was seeded';
  END IF;

  RAISE NOTICE 'M0 smoke checks passed';
END;
$$;