-- =====================================================================
-- Abbey v2 — smoke test (run AFTER the v2 schema + seed migrations).
-- =====================================================================
-- Wrapped in BEGIN ... ROLLBACK: it writes nothing permanent. Run in the
-- Supabase SQL editor. It exercises the real RPCs as an existing global
-- tms_admin and asserts the database-decides-what-is-due behaviour.
--
-- Requires: at least one global tms_admin in user_site_roles (you have one).
-- If your auth.uid() wiring differs, replace the auto-pick with a literal uid.
-- =====================================================================
begin;

do $smoke$
declare
  v_uid uuid;
  v_site uuid;
  v_ss_tue uuid; v_ss_fri uuid; v_ss_sun uuid;
  v_fri_anchor date := date '2026-06-19';   -- a Friday => Friday pos 1 (male)
  v_sun_anchor date := date '2026-06-21';   -- a Sunday => Sunday pos 1
  v_vtue uuid; v_vfri1 uuid; v_vfri2 uuid; v_vsun1 uuid; v_vsun4 uuid;
  n int; n_male int; n_female int; n_oos int; n_cf int;
  v_fail_task uuid;
begin
  select user_id into v_uid from public.user_site_roles
   where role_code='tms_admin' and site_id is null limit 1;
  if v_uid is null then
    raise exception 'No global tms_admin found — assign one before running the smoke test';
  end if;
  -- act as that admin for RLS / SECURITY DEFINER role checks
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role','authenticated')::text, true);
  perform set_config('role','authenticated', true);

  select id into v_site from public.sites where code='ABBEY_LC';
  select id into v_ss_tue from public.v2_service_schedules where site_id=v_site and code='SS_TUE';
  select id into v_ss_fri from public.v2_service_schedules where site_id=v_site and code='SS_FRI';
  select id into v_ss_sun from public.v2_service_schedules where site_id=v_site and code='SS_SUN';

  -- activate rotations deterministically (rolled back)
  update public.v2_rotation_anchors set anchor_start_date=v_fri_anchor
    where site_id=v_site and code='RA_FRI_DRY';
  update public.v2_rotation_anchors set anchor_start_date=v_sun_anchor
    where site_id=v_site and code='RA_SUN_WET';

  -- ---- Tuesday: baseline only, no rotation ----
  v_vtue := public.rpc_v2_create_visit(v_site, v_ss_tue, date '2026-06-23'); -- a Tuesday
  select count(*) into n from public.v2_generated_visit_tasks
    where visit_instance_id=v_vtue and task_source='baseline';
  assert n >= 8, format('Tuesday baseline expected >=8, got %s', n);
  select count(*) into n from public.v2_generated_visit_tasks
    where visit_instance_id=v_vtue and task_source='rotation';
  assert n = 0, format('Tuesday should have no rotation tasks, got %s', n);

  -- ---- Friday week of anchor => pos 1 (MALE intensive due, FEMALE not) ----
  v_vfri1 := public.rpc_v2_create_visit(v_site, v_ss_fri, v_fri_anchor);
  select count(*) into n from public.v2_generated_visit_tasks
    where visit_instance_id=v_vfri1 and task_source='baseline';
  assert n >= 11, format('Friday baseline expected >=11, got %s', n);
  select count(*) into n_male from public.v2_generated_visit_tasks g
    join public.v2_areas a on a.id=g.area_id
    where g.visit_instance_id=v_vfri1 and g.task_source='rotation' and a.code='DRY_MALE';
  select count(*) into n_female from public.v2_generated_visit_tasks g
    join public.v2_areas a on a.id=g.area_id
    where g.visit_instance_id=v_vfri1 and g.task_source='rotation' and a.code='DRY_FEMALE';
  assert n_male > 0,  'Friday pos1: male intensive should be due';
  assert n_female = 0, format('Friday pos1: female intensive must NOT be due (not-due != failure), got %s', n_female);

  -- ---- Friday anchor+7 => pos 2 (FEMALE intensive due, MALE not) ----
  v_vfri2 := public.rpc_v2_create_visit(v_site, v_ss_fri, v_fri_anchor + 7);
  select count(*) into n_male from public.v2_generated_visit_tasks g
    join public.v2_areas a on a.id=g.area_id
    where g.visit_instance_id=v_vfri2 and g.task_source='rotation' and a.code='DRY_MALE';
  select count(*) into n_female from public.v2_generated_visit_tasks g
    join public.v2_areas a on a.id=g.area_id
    where g.visit_instance_id=v_vfri2 and g.task_source='rotation' and a.code='DRY_FEMALE';
  assert n_female > 0, 'Friday pos2: female intensive should be due';
  assert n_male = 0,  format('Friday pos2: male intensive must NOT be due, got %s', n_male);

  -- ---- Sunday pos 1 and pos 4 ----
  v_vsun1 := public.rpc_v2_create_visit(v_site, v_ss_sun, v_sun_anchor);
  select count(*) into n from public.v2_generated_visit_tasks
    where visit_instance_id=v_vsun1 and task_source='rotation';
  assert n > 0, 'Sunday pos1 should generate rotation tasks';
  v_vsun4 := public.rpc_v2_create_visit(v_site, v_ss_sun, v_sun_anchor + 21); -- week 4
  select count(*) into n from public.v2_generated_visit_tasks g
    join public.v2_rotation_segments seg on seg.id=g.rotation_segment_id
    where g.visit_instance_id=v_vsun4 and seg.position=4;
  assert n > 0, 'Sunday week-4 should map to segment position 4';

  -- ---- out-of-scope areas never generate tasks ----
  select count(*) into n_oos from public.v2_generated_visit_tasks g
    join public.v2_areas a on a.id=g.area_id
    where a.is_out_of_scope;
  assert n_oos = 0, format('Out-of-scope areas must generate no tasks, got %s', n_oos);

  -- ---- carry-forward: fail a Friday-1 task, regenerate Friday-2, expect a carry ----
  select id into v_fail_task from public.v2_generated_visit_tasks
    where visit_instance_id=v_vfri1 and task_source='baseline' limit 1;
  perform public.rpc_v2_record_result(v_fail_task, 'not_completed', null, false, null, 'left undone', false);
  perform public.rpc_v2_generate_visit_tasks(v_vfri2);
  select count(*) into n_cf from public.v2_generated_visit_tasks
    where visit_instance_id=v_vfri2 and task_source='carry_forward' and carried_from_task_id=v_fail_task;
  assert n_cf = 1, format('expected 1 carry-forward of the failed task, got %s', n_cf);

  -- ---- supervisor verification path ----
  perform public.rpc_v2_supervisor_verify(v_fail_task, true, 'checked');
  select count(*) into n from public.v2_visit_task_results
    where generated_visit_task_id=v_fail_task and supervisor_verified;
  assert n = 1, 'supervisor verification should be recorded';

  raise notice 'ABBEY V2 SMOKE TEST PASSED (Tue/Fri/Sun generation, rotation positions, not-due!=failure, out-of-scope excluded, carry-forward, supervisor verify)';
end $smoke$;

rollback;
