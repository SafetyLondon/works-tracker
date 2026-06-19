-- 40_actions.sql — MUTATING. Wrap in BEGIN/ROLLBACK.
-- rpc_progress_action transition matrix, scope eligibility, verifier ≠ assignee,
-- role gating, illegal transition rejection.

DO $$
DECLARE
  v_site uuid; v_action uuid; v_v bigint;
  v_sup uuid := '00000000-0000-0000-0000-00000000d001';
  v_op  uuid := '00000000-0000-0000-0000-00000000d002';
  v_dm  uuid := '00000000-0000-0000-0000-00000000d003';
  v_ro  uuid := '00000000-0000-0000-0000-00000000d004';
  v_gm  uuid := '00000000-0000-0000-0000-00000000d005';
BEGIN
  INSERT INTO public.sites(code,name) VALUES ('AC_SITE','Actions site') ON CONFLICT DO NOTHING;
  SELECT id INTO v_site FROM public.sites WHERE code='AC_SITE';

  PERFORM tests.make_user(v_sup,'sup@ac'); PERFORM tests.grant_role(v_sup,'tms_supervisor',v_site);
  PERFORM tests.make_user(v_op,'op@ac');   PERFORM tests.grant_role(v_op,'tms_operative',v_site);
  PERFORM tests.make_user(v_dm,'dm@ac');   PERFORM tests.grant_role(v_dm,'centre_dm_reviewer',v_site);
  PERFORM tests.make_user(v_ro,'ro@ac');   PERFORM tests.grant_role(v_ro,'read_only_viewer',v_site);
  PERFORM tests.make_user(v_gm,'gm@ac');   PERFORM tests.grant_role(v_gm,'centre_gm',v_site);

  INSERT INTO public.actions(site_id,title,scope_classification,priority,status,created_by)
    VALUES (v_site,'T','routine_cleaning','normal','open',v_sup)
    RETURNING id, version_no INTO v_action, v_v;

  -- Read-only viewer cannot mutate.
  PERFORM tests.set_user(v_ro);
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_progress_action(%L,%L::bigint,'in_progress'::public.action_status)$f$, v_action, v_v),
    'forbidden');

  -- Centre DM cannot mutate.
  PERFORM tests.set_user(v_dm);
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_progress_action(%L,%L::bigint,'in_progress'::public.action_status)$f$, v_action, v_v),
    'forbidden');

  -- TMS supervisor assigns to operative.
  PERFORM tests.set_user(v_sup);
  v_v := public.rpc_progress_action(v_action, v_v, 'assigned'::public.action_status, NULL, v_op);

  -- Operative moves to in_progress and to awaiting_verification.
  PERFORM tests.set_user(v_op);
  v_v := public.rpc_progress_action(v_action, v_v, 'in_progress'::public.action_status);
  v_v := public.rpc_progress_action(v_action, v_v, 'awaiting_verification'::public.action_status);

  -- Operative is the assignee → cannot close (verifier ≠ assignee rule).
  PERFORM tests.assert_raises(
    format($f$SELECT public.rpc_progress_action(%L,%L::bigint,'closed'::public.action_status)$f$, v_action, v_v),
    'forbidden_transition');

  -- Centre GM can verify (close).
  PERFORM tests.set_user(v_gm);
  v_v := public.rpc_progress_action(v_action, v_v, 'closed'::public.action_status, 'ok');
  PERFORM tests.assert(
    (SELECT status FROM public.actions WHERE id=v_action) = 'closed',
    'action closed by verifier');

  -- Illegal jump open->closed must be rejected by the validation trigger.
  INSERT INTO public.actions(site_id,title,scope_classification,priority,status,created_by)
    VALUES (v_site,'T2','routine_cleaning','normal','open',v_sup) RETURNING id INTO v_action;
  PERFORM tests.assert_raises(
    format($f$UPDATE public.actions SET status='closed' WHERE id=%L$f$, v_action),
    'illegal action status transition');

  PERFORM tests.reset_role();
  RAISE NOTICE '40_actions: ALL PASSED';
END $$;
