-- 20_visit_workflow.sql — MUTATING. Wrap in BEGIN/ROLLBACK.
-- Visit creation, weekday override, duplicate handling, transition matrix,
-- supervisor handover, recommendation/focus reconciliation, optimistic lock,
-- and immutability after submit.

DO $$
DECLARE
  v_site uuid; v_tpl uuid;
  v_sup uuid := '00000000-0000-0000-0000-00000000b001';
  v_dm  uuid := '00000000-0000-0000-0000-00000000b002';
  v_admin uuid := '00000000-0000-0000-0000-00000000b003';
  v_ro uuid := '00000000-0000-0000-0000-00000000b004';
  v_visit uuid; v_visit2 uuid;
  v_resp jsonb; v_version bigint;
  v_focus_id uuid; v_rec_id uuid;
BEGIN
  INSERT INTO public.sites(code,name) VALUES('VW_SITE','Visit Workflow Site') ON CONFLICT DO NOTHING;
  SELECT id INTO v_site FROM public.sites WHERE code='VW_SITE';
  INSERT INTO public.visit_templates(site_id,code,name,expected_weekday)
    VALUES (v_site,'TUE','Tuesday',2) ON CONFLICT DO NOTHING;
  SELECT id INTO v_tpl FROM public.visit_templates WHERE site_id=v_site AND code='TUE';

  PERFORM tests.make_user(v_sup,'sup@vw');     PERFORM tests.grant_role(v_sup,'tms_supervisor',v_site);
  PERFORM tests.make_user(v_dm,'dm@vw');       PERFORM tests.grant_role(v_dm,'centre_dm_reviewer',v_site);
  PERFORM tests.make_user(v_admin,'admin@vw'); PERFORM tests.grant_role(v_admin,'tms_admin',NULL);
  PERFORM tests.make_user(v_ro,'ro@vw');       PERFORM tests.grant_role(v_ro,'read_only_viewer',v_site);

  -- Create Tuesday visit on correct weekday
  PERFORM tests.set_user(v_sup);
  v_resp := public.rpc_create_cleaning_visit_from_template(v_site,v_tpl,DATE '2026-06-09');
  v_visit := (v_resp->>'visit_id')::uuid;
  PERFORM tests.assert((v_resp->>'created')::boolean, 'first creation must return created=true');

  -- Duplicate same-date returns created=false
  v_resp := public.rpc_create_cleaning_visit_from_template(v_site,v_tpl,DATE '2026-06-09');
  PERFORM tests.assert(NOT (v_resp->>'created')::boolean, 'duplicate returns created=false');
  PERFORM tests.assert((v_resp->>'visit_id')::uuid = v_visit, 'duplicate returns existing id');

  -- Wrong weekday without override is rejected for supervisor (supervisor CAN override but must supply reason)
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_create_cleaning_visit_from_template(%L,%L,DATE '2026-06-10')$f$,
           v_site, v_tpl),
    'weekday override requires a reason');

  -- Read-only user cannot create
  PERFORM tests.set_user(v_ro);
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_create_cleaning_visit_from_template(%L,%L,DATE '2026-06-16')$f$, v_site, v_tpl),
    'forbidden');

  -- Centre DM cannot save the handover (TMS-only ownership)
  PERFORM tests.set_user(v_dm);
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_save_visit_draft(%L,%L::bigint,'{}'::jsonb)$f$, v_visit, v_version),
    'forbidden');

  -- Supervisor saves and submits the handover
  PERFORM tests.set_user(v_sup);
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM (SELECT public.rpc_save_visit_draft(v_visit, v_version, '{"notes":"hi"}'::jsonb));
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;

  -- Stale optimistic-lock version is rejected
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_save_visit_draft(%L,%L::bigint,'{}'::jsonb)$f$, v_visit, v_version - 5),
    'stale_version');

  -- Recommendation/focus reconciliation: insert recommendation, accept it (focus item created),
  -- then skip it and assert linked focus item is removed.
  INSERT INTO public.visit_focus_recommendations(cleaning_visit_id, focus_label_snapshot, recommendation_status, display_order)
    VALUES (v_visit,'Test focus','pending',1) RETURNING id INTO v_rec_id;
  INSERT INTO public.visit_focus_items(cleaning_visit_id, source_recommendation_id, focus_name_snapshot, exact_location, status)
    VALUES (v_visit, v_rec_id, 'Test focus','Cubicle 1','selected') RETURNING id INTO v_focus_id;
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_save_visit_draft(v_visit, v_version,
    jsonb_build_object('recommendations',
      jsonb_build_array(jsonb_build_object('id', v_rec_id::text,
                                           'recommendation_status','skipped',
                                           'resolution_reason','no time'))));
  PERFORM tests.assert(
    NOT EXISTS (SELECT 1 FROM public.visit_focus_items WHERE id=v_focus_id),
    'skipping a recommendation must remove its linked selected focus item');

  -- Submit handover
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM public.rpc_submit_supervisor_handover(v_visit, v_version);
  PERFORM tests.assert(
    (SELECT status FROM public.cleaning_visits WHERE id=v_visit)='submitted_for_review',
    'submitted handover moves visit to submitted_for_review');

  -- Immutability: a supervisor cannot edit after submit_for_review
  SELECT version_no INTO v_version FROM public.cleaning_visits WHERE id=v_visit;
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_save_visit_draft(%L,%L::bigint,'{}'::jsonb)$f$, v_visit, v_version),
    'visit not editable');

  -- Illegal transition: planned -> reviewed must fail at trigger level
  INSERT INTO public.cleaning_visits(site_id, visit_template_id, visit_date, status, supervisor_id, created_by)
    VALUES (v_site, v_tpl, DATE '2026-06-23','planned', v_sup, v_sup) RETURNING id INTO v_visit2;
  PERFORM tests.assert_raises(
    format($f$UPDATE public.cleaning_visits SET status='reviewed' WHERE id=%L$f$, v_visit2),
    'illegal cleaning_visit status transition');

  PERFORM tests.reset_role();
  RAISE NOTICE '20_visit_workflow: ALL PASSED';
END $$;
