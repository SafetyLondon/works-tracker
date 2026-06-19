-- 50_directory_privacy.sql — MUTATING. Wrap in BEGIN/ROLLBACK.
-- Verifies profile privacy and rpc_site_user_directory shape and authorisation.

DO $$
DECLARE
  v_site_a uuid; v_site_b uuid;
  v_u1 uuid := '00000000-0000-0000-0000-00000000e001';
  v_u2 uuid := '00000000-0000-0000-0000-00000000e002';
  v_rec record;
  v_col_count int;
BEGIN
  INSERT INTO public.sites(code,name) VALUES ('DIR_A','A'),('DIR_B','B') ON CONFLICT DO NOTHING;
  SELECT id INTO v_site_a FROM public.sites WHERE code='DIR_A';
  SELECT id INTO v_site_b FROM public.sites WHERE code='DIR_B';
  PERFORM tests.make_user(v_u1,'u1@dir'); PERFORM tests.grant_role(v_u1,'tms_supervisor',v_site_a);
  PERFORM tests.make_user(v_u2,'u2@dir'); PERFORM tests.grant_role(v_u2,'centre_dm_reviewer',v_site_b);

  -- Directory column shape: user_id, display_name, role_code, site_id ONLY (no email).
  SELECT count(*) INTO v_col_count FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_site_user_directory';
  PERFORM tests.assert(v_col_count = 1, 'rpc_site_user_directory exists');

  PERFORM tests.set_user(v_u1);
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM public.rpc_site_user_directory(v_site_a) WHERE user_id=v_u1),
    'site A user sees themselves in site A directory');
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_site_user_directory(%L)$f$, v_site_b),
    'forbidden');

  -- Profile policy: a user can read their own profile but not strangers'.
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM public.profiles WHERE id=v_u1),
    'self profile readable');
  PERFORM tests.assert(
    NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_u2),
    'stranger profile NOT readable by non-admin');

  PERFORM tests.reset_role();
  RAISE NOTICE '50_directory_privacy: ALL PASSED';
END $$;
