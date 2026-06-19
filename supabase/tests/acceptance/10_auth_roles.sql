-- 10_auth_roles.sql — MUTATING. Run only in a transaction that will be ROLLBACK'd.
-- Verifies role assignment, global tms_admin (site_id NULL), centre site-scoping,
-- cross-site isolation, and that a no-role user cannot reach operational tables.

DO $$
DECLARE
  v_site_a uuid; v_site_b uuid;
  v_admin uuid := '00000000-0000-0000-0000-00000000a001';
  v_no_role uuid := '00000000-0000-0000-0000-00000000a002';
  v_centre_a uuid := '00000000-0000-0000-0000-00000000a003';
  v_centre_b uuid := '00000000-0000-0000-0000-00000000a004';
  v_tpl uuid;
BEGIN
  -- Fixture sites
  INSERT INTO public.sites(code,name) VALUES
    ('TEST_SITE_A','Test Site A'),('TEST_SITE_B','Test Site B')
    ON CONFLICT (code) DO NOTHING;
  SELECT id INTO v_site_a FROM public.sites WHERE code='TEST_SITE_A';
  SELECT id INTO v_site_b FROM public.sites WHERE code='TEST_SITE_B';
  INSERT INTO public.visit_templates(site_id,code,name,expected_weekday)
    VALUES (v_site_a,'TPL_A1','TPL A1',2) ON CONFLICT DO NOTHING
    RETURNING id INTO v_tpl;

  PERFORM tests.make_user(v_admin, 'admin@test');
  PERFORM tests.make_user(v_no_role,'norole@test');
  PERFORM tests.make_user(v_centre_a,'centre_a@test');
  PERFORM tests.make_user(v_centre_b,'centre_b@test');

  -- Global tms_admin assignment requires site_id NULL
  PERFORM tests.grant_role(v_admin,'tms_admin',NULL);
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM public.user_site_roles
             WHERE user_id=v_admin AND role_code='tms_admin' AND site_id IS NULL),
    'global tms_admin must have site_id NULL');

  -- Global role with a site_id must be rejected by the validation trigger
  PERFORM tests.assert_raises(
    format($f$INSERT INTO public.user_site_roles(user_id,role_code,site_id)
                VALUES (%L,'tms_admin',%L)$f$, v_admin, v_site_a),
    'must not have a site_id');

  -- Site-scoped role missing site_id is rejected
  PERFORM tests.assert_raises(
    format($f$INSERT INTO public.user_site_roles(user_id,role_code,site_id)
                VALUES (%L,'centre_dm_reviewer',NULL)$f$, v_centre_a),
    'requires a site_id');

  PERFORM tests.grant_role(v_centre_a,'centre_dm_reviewer',v_site_a);
  PERFORM tests.grant_role(v_centre_b,'centre_dm_reviewer',v_site_b);

  -- Cross-site isolation: centre_a should NOT see site B via the directory RPC
  PERFORM tests.set_user(v_centre_a);
  PERFORM tests.assert_uid(v_centre_a);
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_site_user_directory(%L)$f$, v_site_b),
    'forbidden');

  -- No-role user must not be able to start a review or submit a handover
  PERFORM tests.set_user(v_no_role);
  PERFORM tests.assert_uid(v_no_role);
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_create_cleaning_visit_from_template(%L,%L,DATE %L)$f$,
           v_site_a, v_tpl, '2026-06-09'),
    'forbidden');

  PERFORM tests.reset_role();
  RAISE NOTICE '10_auth_roles: ALL PASSED';
END $$;
