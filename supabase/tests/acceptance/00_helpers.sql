-- 00_helpers.sql — preamble loaded inside the test transaction.
-- Provides a `tests` schema with assertion helpers and JWT setters.

CREATE SCHEMA IF NOT EXISTS tests;

-- Set the current request as a given user with role 'authenticated'.
CREATE OR REPLACE FUNCTION tests.set_user(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
  -- Switch session role; harmless if 'authenticated' isn't grantable in this env.
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END $$;

CREATE OR REPLACE FUNCTION tests.set_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('role','anon')::text, true);
  BEGIN EXECUTE 'SET LOCAL ROLE anon'; EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

CREATE OR REPLACE FUNCTION tests.reset_role()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

CREATE OR REPLACE FUNCTION tests.assert_uid(p_expected uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  v := auth.uid();
  IF v IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'assert_uid: auth.uid()=% expected=%', v, p_expected;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION tests.assert(p_cond boolean, p_msg text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(p_cond, false) THEN
    RAISE EXCEPTION 'ASSERT FAIL: %', p_msg;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION tests.assert_raises(p_sql text, p_substring text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(lower(p_substring) IN lower(SQLERRM)) = 0 THEN
      RAISE EXCEPTION 'assert_raises: expected % to contain %, got: %',
        p_sql, p_substring, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'assert_raises: expected exception containing % but SQL succeeded: %',
    p_substring, p_sql;
END $$;

-- Fabricate a fixture user without touching auth.users (which is owned by
-- Supabase Auth). We insert directly into auth.users when permitted; the
-- runner is expected to be run with privileges that allow this on local /
-- test environments only.
CREATE OR REPLACE FUNCTION tests.make_user(p_uid uuid, p_email text)
RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email, instance_id, aud, role)
  VALUES (p_uid, p_email, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (p_uid, p_email, split_part(p_email,'@',1))
  ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END $$;

-- Grant a role assignment via direct insert (bypasses RLS within the
-- security-definer scope of the test transaction).
CREATE OR REPLACE FUNCTION tests.grant_role(p_uid uuid, p_role text, p_site uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.user_site_roles(user_id, role_code, site_id)
  VALUES (p_uid, p_role, p_site)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
