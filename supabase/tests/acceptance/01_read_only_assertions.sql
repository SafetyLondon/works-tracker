-- 01_read_only_assertions.sql
-- Pure SELECT assertions. Safe against any environment including live.
-- No writes. No role switches. Fails fast on the first deviation.

DO $$
DECLARE
  v_site uuid;
  v_tue uuid; v_fri uuid; v_sun uuid;
  v_fri_prog uuid; v_sun_prog uuid;
  v_fri_anchor date; v_sun_anchor date;
  v_count int;
BEGIN
  ---------------------------------------------------------------- canonical roles
  PERFORM tests.assert(
    (SELECT count(*) FROM public.role_definitions
       WHERE code IN ('tms_admin','tms_supervisor','tms_operative',
                      'centre_dm_reviewer','centre_operations_manager',
                      'centre_gm','read_only_viewer')) = 7,
    'all seven canonical role codes must exist');

  PERFORM tests.assert(
    (SELECT count(*) FROM public.role_definitions
       WHERE code IN ('site_supervisor','site_operative','ops_manager','gm')) = 0,
    'legacy role codes must not exist');

  PERFORM tests.assert(
    (SELECT is_global FROM public.role_definitions WHERE code='tms_admin'),
    'tms_admin must be a global role');

  ---------------------------------------------------------------- Abbey site & templates
  SELECT id INTO v_site FROM public.sites WHERE code='ABBEY_LC';
  PERFORM tests.assert(v_site IS NOT NULL, 'ABBEY_LC site must exist');

  SELECT id INTO v_tue FROM public.visit_templates WHERE site_id=v_site AND code='TUE_SPA';
  SELECT id INTO v_fri FROM public.visit_templates WHERE site_id=v_site AND code='FRI_DRYSIDE';
  SELECT id INTO v_sun FROM public.visit_templates WHERE site_id=v_site AND code='SUN_WETSIDE';
  PERFORM tests.assert(v_tue IS NOT NULL AND v_fri IS NOT NULL AND v_sun IS NOT NULL,
    'all three Abbey templates must exist');
  PERFORM tests.assert(
    (SELECT expected_weekday FROM public.visit_templates WHERE id=v_tue)=2 AND
    (SELECT expected_weekday FROM public.visit_templates WHERE id=v_fri)=5 AND
    (SELECT expected_weekday FROM public.visit_templates WHERE id=v_sun)=0,
    'Abbey templates must use weekdays 2/5/0');

  ---------------------------------------------------------------- rating-line counts
  PERFORM tests.assert(
    (SELECT count(*) FROM public.template_rating_lines WHERE visit_template_id=v_tue) = 7,
    'Tuesday rating lines must be 7');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.template_rating_lines WHERE visit_template_id=v_fri) = 11,
    'Friday rating lines must be 11');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.template_rating_lines WHERE visit_template_id=v_sun) = 9,
    'Sunday rating lines must be 9');

  ---------------------------------------------------------------- scope items are separate from rating lines
  PERFORM tests.assert(
    (SELECT count(DISTINCT item_type) FROM public.template_scope_items
      WHERE visit_template_id IN (v_tue,v_fri,v_sun)) = 4,
    'all four scope item_types must be represented across Abbey templates');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.template_scope_items WHERE visit_template_id=v_tue) > 0
    AND (SELECT count(*) FROM public.template_scope_items WHERE visit_template_id=v_fri) > 0
    AND (SELECT count(*) FROM public.template_scope_items WHERE visit_template_id=v_sun) > 0,
    'every Abbey template must have schedule scope items');

  ---------------------------------------------------------------- rotation programmes
  SELECT id, anchor_date INTO v_fri_prog, v_fri_anchor
    FROM public.rotation_programmes WHERE site_id=v_site AND code='FRI_ROT_4WK';
  SELECT id, anchor_date INTO v_sun_prog, v_sun_anchor
    FROM public.rotation_programmes WHERE site_id=v_site AND code='SUN_ROT_4WK';
  PERFORM tests.assert(v_fri_prog IS NOT NULL AND v_sun_prog IS NOT NULL,
    'Friday and Sunday rotation programmes must exist');
  PERFORM tests.assert(v_fri_anchor IS NULL AND v_sun_anchor IS NULL,
    'rotation anchors must remain NULL until deliberately configured');
  PERFORM tests.assert(
    NOT EXISTS (SELECT 1 FROM public.rotation_programmes
                 WHERE site_id=v_site AND visit_template_id=v_tue),
    'Tuesday must have no fixed rotation programme');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.rotation_steps WHERE rotation_programme_id=v_fri_prog)=4
    AND (SELECT count(*) FROM public.rotation_steps WHERE rotation_programme_id=v_sun_prog)=4,
    'Friday and Sunday rotations must each have four steps');

  -- Every step must have at least one focus link.
  PERFORM tests.assert(
    NOT EXISTS (
      SELECT 1 FROM public.rotation_steps rs
      WHERE rs.rotation_programme_id IN (v_fri_prog, v_sun_prog)
        AND NOT EXISTS (SELECT 1 FROM public.rotation_step_focus_items
                         WHERE rotation_step_id = rs.id)),
    'every rotation step must have at least one focus link');

  ---------------------------------------------------------------- focus items present
  PERFORM tests.assert(
    (SELECT count(*) FROM public.focus_items WHERE site_id=v_site) >= 20,
    'Abbey focus library must contain at least 20 items');
  -- Every focus_item must have a category and either be ad-hoc-template
  -- (NULL visit_template_id) or attached to a visit template; in the live
  -- seed every row is attached to a template.
  PERFORM tests.assert(
    NOT EXISTS (SELECT 1 FROM public.focus_items
                 WHERE site_id=v_site AND visit_template_id IS NULL),
    'all Abbey focus items are bound to a visit template');

  ---------------------------------------------------------------- duplicate stable codes
  PERFORM tests.assert(
    NOT EXISTS (
      SELECT visit_template_id, code FROM public.template_rating_lines
       WHERE visit_template_id IN (v_tue,v_fri,v_sun)
       GROUP BY 1,2 HAVING count(*) > 1),
    'no duplicate rating-line codes within a template');
  PERFORM tests.assert(
    NOT EXISTS (
      SELECT visit_template_id, code FROM public.template_scope_items
       WHERE visit_template_id IN (v_tue,v_fri,v_sun)
       GROUP BY 1,2 HAVING count(*) > 1),
    'no duplicate scope codes within a template');
  PERFORM tests.assert(
    NOT EXISTS (
      SELECT code FROM public.focus_items WHERE site_id=v_site
       GROUP BY 1 HAVING count(*) > 1),
    'no duplicate focus_item codes per site');

  ---------------------------------------------------------------- catalogues
  PERFORM tests.assert(
    (SELECT count(*) FROM public.issue_types WHERE is_active) >= 12,
    'issue_types catalogue must be populated');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.constraint_types WHERE is_active) >= 8,
    'constraint_types catalogue must be populated');
  PERFORM tests.assert(
    (SELECT count(*) FROM public.visit_team_role_options WHERE is_active) >= 4,
    'visit_team_role_options catalogue must be populated');

  ---------------------------------------------------------------- review immutability triggers
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM pg_trigger
             WHERE tgname = 'tms_protect_submitted_review_trg'
                OR tgrelid = 'public.reviews'::regclass
                AND tgname ILIKE '%protect_submitted_review%'),
    'submitted-review protection trigger must exist on public.reviews');

  ---------------------------------------------------------------- urgent H&S source constraint
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname = 'actions_urgent_hs_source_chk'),
    'actions.urgent_hs source CHECK constraint must exist');

  ---------------------------------------------------------------- urgent source column on reviews (Slice A)
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='reviews'
               AND column_name='urgent_source_constraint_id'),
    'reviews.urgent_source_constraint_id column (Slice A) must exist');

  ---------------------------------------------------------------- focus_item_scores parity
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='focus_item_scores'
               AND column_name='cleaning_visit_id'),
    'focus_item_scores.cleaning_visit_id must exist (same-visit FK target)');

  ---------------------------------------------------------------- evidence bucket policies present
  PERFORM tests.assert(
    (SELECT count(*) FROM pg_policy
      WHERE polrelid='storage.objects'::regclass
        AND polname IN ('evidence_select','evidence_insert',
                        'evidence_update','evidence_delete')) = 4,
    'all four evidence storage policies must exist');

  ---------------------------------------------------------------- RPC presence (signatures verified by usage tests)
  PERFORM tests.assert(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public'
        AND p.proname IN (
          'rpc_create_cleaning_visit_from_template',
          'rpc_save_visit_draft','rpc_submit_supervisor_handover',
          'rpc_start_review_draft','rpc_save_review_draft','rpc_submit_review',
          'rpc_create_superseding_review','rpc_admin_reopen_visit_with_cancel',
          'rpc_progress_action','rpc_site_user_directory',
          'rpc_finalise_evidence_upload','rpc_set_rotation_anchor',
          'rpc_assign_site_role','rpc_revoke_site_role')) = 14,
    'every workflow RPC must exist');

  ---------------------------------------------------------------- profiles policy is restricted
  PERFORM tests.assert(
    EXISTS (SELECT 1 FROM pg_policy
             WHERE polrelid='public.profiles'::regclass
               AND polname ILIKE '%self_or_admin%'),
    'profiles must have a self-or-admin select policy (no broad reads)');

  RAISE NOTICE '01_read_only_assertions: ALL PASSED';
END $$;
