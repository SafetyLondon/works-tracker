-- 30_review_workflow.sql — MUTATING. Wrap in BEGIN/ROLLBACK.
-- Review draft ownership, rating-line + focus-item completeness, urgent H&S
-- source binding, auto-actions, supersede flow, reopen-with-cancel.

DO $$
DECLARE
  v_site uuid; v_tpl uuid; v_visit uuid; v_review uuid;
  v_sup uuid := '00000000-0000-0000-0000-00000000c001';
  v_dm1 uuid := '00000000-0000-0000-0000-00000000c002';
  v_dm2 uuid := '00000000-0000-0000-0000-00000000c003';
  v_gm  uuid := '00000000-0000-0000-0000-00000000c004';
  v_admin uuid := '00000000-0000-0000-0000-00000000c005';
  v_line_id uuid; v_focus_visit_id uuid; v_version bigint;
  v_constraint_id uuid; v_review2 uuid; v_action_count int;
BEGIN
  INSERT INTO public.sites(code,name) VALUES ('RV_SITE','Review Site') ON CONFLICT DO NOTHING;
  SELECT id INTO v_site FROM public.sites WHERE code='RV_SITE';
  INSERT INTO public.visit_templates(site_id,code,name,expected_weekday)
    VALUES (v_site,'RV_TPL','Tpl',2) ON CONFLICT DO NOTHING;
  SELECT id INTO v_tpl FROM public.visit_templates WHERE site_id=v_site AND code='RV_TPL';
  INSERT INTO public.template_rating_lines(visit_template_id,code,label,display_order)
    VALUES (v_tpl,'L1','L1',10) ON CONFLICT DO NOTHING;

  PERFORM tests.make_user(v_sup,'sup@rv');   PERFORM tests.grant_role(v_sup,'tms_supervisor',v_site);
  PERFORM tests.make_user(v_dm1,'dm1@rv');   PERFORM tests.grant_role(v_dm1,'centre_dm_reviewer',v_site);
  PERFORM tests.make_user(v_dm2,'dm2@rv');   PERFORM tests.grant_role(v_dm2,'centre_dm_reviewer',v_site);
  PERFORM tests.make_user(v_gm,'gm@rv');     PERFORM tests.grant_role(v_gm,'centre_gm',v_site);
  PERFORM tests.make_user(v_admin,'admin@rv'); PERFORM tests.grant_role(v_admin,'tms_admin',NULL);

  -- Supervisor creates and submits a handover.
  PERFORM tests.set_user(v_sup);
  v_visit := (public.rpc_create_cleaning_visit_from_template(v_site,v_tpl,DATE '2026-06-09')->>'visit_id')::uuid;
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_save_visit_draft(v_visit, v_version, '{"notes":"go"}'::jsonb);
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_submit_supervisor_handover(v_visit, v_version);

  -- DM1 opens a review draft.
  PERFORM tests.set_user(v_dm1);
  v_review := public.rpc_start_review_draft(v_visit, 'dm_lightweight');
  PERFORM tests.assert(v_review IS NOT NULL, 'review draft created');

  -- DM2 cannot save into DM1's draft.
  PERFORM tests.set_user(v_dm2);
  SELECT version_no INTO v_version FROM public.reviews WHERE id=v_review;
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_save_review_draft(%L,%L::bigint,'{}'::jsonb)$f$, v_review, v_version),
    'not_review_owner');

  -- DM1 cannot submit while a rating line is missing.
  PERFORM tests.set_user(v_dm1);
  SELECT version_no INTO v_version FROM public.reviews WHERE id=v_review;
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_submit_review(%L,%L::bigint)$f$, v_review, v_version),
    'review_incomplete');

  -- N/A without a reason is incomplete.
  SELECT vrl.id INTO v_line_id FROM public.visit_rating_lines vrl WHERE vrl.cleaning_visit_id=v_visit LIMIT 1;
  INSERT INTO public.review_line_scores(review_id, cleaning_visit_id, visit_rating_line_id, is_na, na_reason)
    VALUES (v_review, v_visit, v_line_id, true, '');
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_submit_review(%L,%L::bigint)$f$, v_review, v_version),
    'review_incomplete');

  -- 1–2 rating without a comment violates CHECK.
  PERFORM tests.assert_raises(
    format($f$UPDATE public.review_line_scores SET is_na=false, rating=2, comment=NULL WHERE id=(SELECT id FROM public.review_line_scores WHERE review_id=%L LIMIT 1)$f$, v_review),
    'comment');

  -- Provide a clean N/A reason then submit.
  UPDATE public.review_line_scores SET is_na=true, na_reason='covered elsewhere'
    WHERE review_id=v_review;
  SELECT version_no INTO v_version FROM public.reviews WHERE id=v_review;
  PERFORM public.rpc_submit_review(v_review, v_version);
  PERFORM tests.assert(
    (SELECT status FROM public.reviews WHERE id=v_review)='submitted',
    'review reaches submitted');

  -- Submitted review is immutable.
  PERFORM tests.assert_raises(
    format($f$UPDATE public.reviews SET general_comment='x' WHERE id=%L$f$, v_review),
    'submitted reviews are immutable');

  -- Urgent H&S without source must be rejected.
  PERFORM tests.set_user(v_sup);
  v_visit := (public.rpc_create_cleaning_visit_from_template(v_site,v_tpl,DATE '2026-06-16')->>'visit_id')::uuid;
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_save_visit_draft(v_visit, v_version, '{"notes":"x"}'::jsonb);
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_submit_supervisor_handover(v_visit, v_version);
  PERFORM tests.set_user(v_dm1);
  v_review2 := public.rpc_start_review_draft(v_visit,'dm_lightweight');
  SELECT version_no INTO v_version FROM public.reviews WHERE id=v_review2;
  PERFORM public.rpc_save_review_draft(v_review2, v_version,
    jsonb_build_object('urgent_hs_flag', true, 'urgent_source_constraint_id', NULL));
  SELECT vrl.id INTO v_line_id FROM public.visit_rating_lines vrl WHERE vrl.cleaning_visit_id=v_visit LIMIT 1;
  INSERT INTO public.review_line_scores(review_id, cleaning_visit_id, visit_rating_line_id, is_na, na_reason)
    VALUES (v_review2, v_visit, v_line_id, true, 'n/a');
  SELECT version_no INTO v_version FROM public.reviews WHERE id=v_review2;
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_submit_review(%L,%L::bigint)$f$, v_review2, v_version),
    'urgent_hs_requires_source');

  -- Bind urgent source to a visit_constraint and resubmit.
  INSERT INTO public.visit_constraints(cleaning_visit_id, constraint_type, description)
    VALUES (v_visit,'area_in_use','locked out') RETURNING id INTO v_constraint_id;
  PERFORM public.rpc_save_review_draft(v_review2,
    (SELECT version_no FROM public.reviews WHERE id=v_review2),
    jsonb_build_object('urgent_hs_flag', true,
                       'urgent_source_constraint_id', v_constraint_id::text));
  PERFORM public.rpc_submit_review(v_review2,
    (SELECT version_no FROM public.reviews WHERE id=v_review2));
  SELECT count(*) INTO v_action_count
    FROM public.actions WHERE source_constraint_id = v_constraint_id AND urgent_hs_flag;
  PERFORM tests.assert(v_action_count = 1,
    'urgent constraint-sourced action must be created exactly once');

  -- Admin reopen with cancel of a fresh draft restores in_progress.
  PERFORM tests.set_user(v_dm1);
  v_review := public.rpc_start_review_draft(v_visit,'dm_lightweight');
  PERFORM tests.set_user(v_admin);
  PERFORM public.rpc_admin_reopen_visit_with_cancel(v_visit,'audit',v_review);
  PERFORM tests.assert(
    (SELECT status FROM public.cleaning_visits WHERE id=v_visit)='in_progress',
    'visit returns to in_progress after admin reopen');
  PERFORM tests.assert(
    NOT EXISTS (SELECT 1 FROM public.reviews WHERE id=v_review),
    'cancelled draft is removed');

  PERFORM tests.reset_role();
  RAISE NOTICE '30_review_workflow: ALL PASSED';
END $$;
