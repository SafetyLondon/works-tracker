
-- ---------- recommended rotation week ----------
create or replace function tms_internal.recommended_rotation_week(_programme uuid, _visit_date date)
returns int
language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_anchor date;
  v_cycle int;
begin
  select anchor_date, cycle_length_weeks into v_anchor, v_cycle
    from public.rotation_programmes where id = _programme;
  if v_anchor is null then return null; end if;
  return ((floor((_visit_date - v_anchor)::numeric / 7)::int) % v_cycle) + 1;
end;
$$;
revoke all on function tms_internal.recommended_rotation_week(uuid, date) from public;
grant execute on function tms_internal.recommended_rotation_week(uuid, date) to authenticated;

-- =====================================================================
-- RPC: create cleaning visit from template
-- =====================================================================
create or replace function public.rpc_create_cleaning_visit_from_template(
  p_site_id uuid,
  p_visit_template_id uuid,
  p_visit_date date,
  p_rotation_programme_id uuid default null,
  p_rotation_week_override int default null,
  p_rotation_week_override_reason text default null,
  p_weekday_override_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit_id uuid;
  v_expected_weekday int;
  v_actual_weekday int;
  v_can_manage boolean;
  v_can_override boolean;
  v_rec_week int;
  v_use_week int;
  v_step record;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;

  v_can_manage := tms_internal.has_site_role(v_uid, p_site_id,
    array['site_supervisor','centre_dm_reviewer','ops_manager','gm','tms_admin']);
  if not v_can_manage then raise exception 'forbidden'; end if;

  v_can_override := tms_internal.has_site_role(v_uid, p_site_id,
    array['site_supervisor','ops_manager','gm','tms_admin']);

  -- Validate template belongs to site
  if not exists (select 1 from public.visit_templates
                 where id = p_visit_template_id and site_id = p_site_id and archived_at is null) then
    raise exception 'invalid template for site';
  end if;

  select expected_weekday into v_expected_weekday
    from public.visit_templates where id = p_visit_template_id;
  v_actual_weekday := extract(dow from p_visit_date)::int;

  if v_expected_weekday is not null and v_actual_weekday <> v_expected_weekday then
    if not v_can_override then
      raise exception 'visit date weekday % does not match template expected weekday %',
        v_actual_weekday, v_expected_weekday;
    end if;
    if coalesce(p_weekday_override_reason, '') = '' then
      raise exception 'weekday override requires a reason';
    end if;
  end if;

  if p_rotation_week_override is not null and not v_can_override then
    raise exception 'rotation week override requires supervisor/admin';
  end if;

  -- Recommended week
  if p_rotation_programme_id is not null then
    v_rec_week := tms_internal.recommended_rotation_week(p_rotation_programme_id, p_visit_date);
  end if;
  v_use_week := coalesce(p_rotation_week_override, v_rec_week);

  insert into public.cleaning_visits(
    site_id, visit_template_id, rotation_programme_id, visit_date,
    recommended_rotation_week, rotation_week_override, rotation_week_override_reason,
    weekday_override_reason, status, supervisor_id, created_by
  ) values (
    p_site_id, p_visit_template_id, p_rotation_programme_id, p_visit_date,
    v_rec_week, p_rotation_week_override, p_rotation_week_override_reason,
    p_weekday_override_reason, 'planned', v_uid, v_uid
  ) returning id into v_visit_id;

  -- Snapshot scope items
  insert into public.visit_scope_snapshots
    (cleaning_visit_id, item_type, label_snapshot, description_snapshot, display_order, source_template_scope_item_id)
  select v_visit_id, tsi.item_type, tsi.label, tsi.description, tsi.display_order, tsi.id
    from public.template_scope_items tsi
    where tsi.visit_template_id = p_visit_template_id and tsi.archived_at is null
    order by tsi.item_type, tsi.display_order;

  -- Snapshot rating lines
  insert into public.visit_rating_lines
    (cleaning_visit_id, visit_template_id, template_rating_line_id, label_snapshot, description_snapshot, display_order)
  select v_visit_id, p_visit_template_id, trl.id, trl.label, trl.description, trl.display_order
    from public.template_rating_lines trl
    where trl.visit_template_id = p_visit_template_id and trl.archived_at is null
    order by trl.display_order;

  -- Snapshot recommendations for the resolved rotation week
  if p_rotation_programme_id is not null and v_use_week is not null then
    insert into public.visit_focus_recommendations
      (cleaning_visit_id, focus_item_id, focus_label_snapshot, focus_description_snapshot, display_order)
    select v_visit_id, fi.id, fi.label, fi.description, rsfi.display_order
      from public.rotation_steps rs
      join public.rotation_step_focus_items rsfi on rsfi.rotation_step_id = rs.id
      join public.focus_items fi on fi.id = rsfi.focus_item_id
      where rs.rotation_programme_id = p_rotation_programme_id
        and rs.week_number = v_use_week
        and fi.archived_at is null
      order by rsfi.display_order;
  end if;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (p_site_id, v_uid, 'cleaning_visit', v_visit_id, 'created',
            jsonb_build_object('visit_date', p_visit_date,
                               'rotation_week', v_use_week,
                               'weekday_override_reason', p_weekday_override_reason));
  return v_visit_id;
end;
$$;
revoke all on function public.rpc_create_cleaning_visit_from_template(uuid,uuid,date,uuid,int,text,text) from public;
grant execute on function public.rpc_create_cleaning_visit_from_template(uuid,uuid,date,uuid,int,text,text) to authenticated;

-- =====================================================================
-- RPC: save visit draft (aggregate, optimistic locking)
-- =====================================================================
create or replace function public.rpc_save_visit_draft(
  p_visit_id uuid,
  p_expected_version bigint,
  p_payload jsonb
) returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid;
  v_status public.cleaning_visit_status;
  v_version bigint;
  v_can boolean;
  v_new_version bigint;
  r jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select site_id, status, version_no into v_site, v_status, v_version
    from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;

  v_can := tms_internal.has_site_role(v_uid, v_site,
    array['site_supervisor','ops_manager','gm','tms_admin']);
  if not v_can then raise exception 'forbidden'; end if;

  if v_status not in ('draft','planned','in_progress') then
    raise exception 'visit not editable in status %', v_status;
  end if;
  if v_version <> p_expected_version then
    raise exception 'stale_version' using errcode='40001';
  end if;

  -- Move planned -> in_progress on first save
  if v_status = 'planned' then
    update public.cleaning_visits
       set status = 'in_progress', notes = coalesce(p_payload->>'notes', notes),
           weather = coalesce(p_payload->>'weather', weather),
           headcount = coalesce((p_payload->>'headcount')::int, headcount)
       where id = p_visit_id;
  else
    update public.cleaning_visits
       set notes = coalesce(p_payload->>'notes', notes),
           weather = coalesce(p_payload->>'weather', weather),
           headcount = coalesce((p_payload->>'headcount')::int, headcount)
       where id = p_visit_id;
  end if;

  -- Recommendations resolution (partial updates)
  if p_payload ? 'recommendations' then
    for r in select * from jsonb_array_elements(p_payload->'recommendations')
    loop
      update public.visit_focus_recommendations
         set recommendation_status = coalesce(r->>'recommendation_status', recommendation_status),
             resolution_reason     = r->>'resolution_reason'
       where id = (r->>'id')::uuid
         and cleaning_visit_id = p_visit_id;
    end loop;
  end if;

  -- Focus items: replace by id when present, else insert ad-hoc
  if p_payload ? 'focus_items' then
    for r in select * from jsonb_array_elements(p_payload->'focus_items')
    loop
      if (r ? 'id') and (r->>'id') is not null then
        update public.visit_focus_items
           set focus_name_snapshot = coalesce(r->>'focus_name_snapshot', focus_name_snapshot),
               description_snapshot = coalesce(r->>'description_snapshot', description_snapshot),
               exact_location = r->>'exact_location',
               status = coalesce((r->>'status')::public.focus_item_status, status),
               completion_note = r->>'completion_note',
               completed_at = case when (r->>'status') in ('completed','partially_completed')
                                   then coalesce((r->>'completed_at')::timestamptz, now()) else null end
         where id = (r->>'id')::uuid and cleaning_visit_id = p_visit_id;
      else
        insert into public.visit_focus_items(
          cleaning_visit_id, focus_item_id, source_recommendation_id,
          focus_name_snapshot, description_snapshot, exact_location,
          status, completion_note, completed_at)
        values (
          p_visit_id,
          nullif(r->>'focus_item_id','')::uuid,
          nullif(r->>'source_recommendation_id','')::uuid,
          r->>'focus_name_snapshot',
          r->>'description_snapshot',
          r->>'exact_location',
          coalesce((r->>'status')::public.focus_item_status, 'selected'),
          r->>'completion_note',
          case when (r->>'status') in ('completed','partially_completed')
               then coalesce((r->>'completed_at')::timestamptz, now()) else null end
        );
      end if;
    end loop;
  end if;

  -- Constraints replace-all if present
  if p_payload ? 'constraints' then
    delete from public.visit_constraints where cleaning_visit_id = p_visit_id;
    insert into public.visit_constraints(cleaning_visit_id, constraint_type, description, affected_area)
    select p_visit_id, c->>'constraint_type', c->>'description', c->>'affected_area'
      from jsonb_array_elements(p_payload->'constraints') c;
  end if;

  -- Team members replace-all if present
  if p_payload ? 'team_members' then
    delete from public.visit_team_members where cleaning_visit_id = p_visit_id;
    insert into public.visit_team_members(cleaning_visit_id, user_id, full_name, role_on_visit)
    select p_visit_id, nullif(t->>'user_id','')::uuid, t->>'full_name', t->>'role_on_visit'
      from jsonb_array_elements(p_payload->'team_members') t;
  end if;

  update public.cleaning_visits
     set version_no = version_no + 1
   where id = p_visit_id
   returning version_no into v_new_version;

  return v_new_version;
end;
$$;
revoke all on function public.rpc_save_visit_draft(uuid, bigint, jsonb) from public;
grant execute on function public.rpc_save_visit_draft(uuid, bigint, jsonb) to authenticated;

-- =====================================================================
-- RPC: submit supervisor handover
-- =====================================================================
create or replace function public.rpc_submit_supervisor_handover(
  p_visit_id uuid,
  p_expected_version bigint
) returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid;
  v_status public.cleaning_visit_status;
  v_version bigint;
  v_pending int;
  v_missing_reason int;
  v_new_version bigint;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select site_id, status, version_no into v_site, v_status, v_version
    from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['site_supervisor','ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;
  if v_status not in ('draft','planned','in_progress') then
    raise exception 'visit cannot be submitted from status %', v_status;
  end if;
  if v_version <> p_expected_version then
    raise exception 'stale_version' using errcode='40001';
  end if;

  select count(*) into v_pending
    from public.visit_focus_recommendations
   where cleaning_visit_id = p_visit_id and recommendation_status = 'pending';
  if v_pending > 0 then
    raise exception 'all recommendations must be resolved (% pending)', v_pending;
  end if;
  select count(*) into v_missing_reason
    from public.visit_focus_recommendations
   where cleaning_visit_id = p_visit_id
     and recommendation_status in ('skipped','inaccessible')
     and coalesce(resolution_reason, '') = '';
  if v_missing_reason > 0 then
    raise exception 'skipped/inaccessible recommendations require a reason (% missing)', v_missing_reason;
  end if;

  -- Force in_progress -> submitted_for_review (status trigger validates)
  if v_status <> 'in_progress' then
    update public.cleaning_visits set status='in_progress' where id = p_visit_id;
  end if;
  update public.cleaning_visits
     set status = 'submitted_for_review',
         submitted_at = now(),
         submitted_by = v_uid,
         version_no = version_no + 1
   where id = p_visit_id
   returning version_no into v_new_version;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action)
    values (v_site, v_uid, 'cleaning_visit', p_visit_id, 'submitted_for_review');
  return v_new_version;
end;
$$;
revoke all on function public.rpc_submit_supervisor_handover(uuid, bigint) from public;
grant execute on function public.rpc_submit_supervisor_handover(uuid, bigint) to authenticated;

-- =====================================================================
-- RPC: reopen visit
-- =====================================================================
create or replace function public.rpc_reopen_visit(p_visit_id uuid, p_reason text)
returns bigint
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid;
  v_status public.cleaning_visit_status;
  v_new_version bigint;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(p_reason, '') = '' then raise exception 'reason required'; end if;

  select site_id, status into v_site, v_status
    from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;
  if v_status not in ('submitted_for_review','reviewed','closed') then
    raise exception 'cannot reopen from status %', v_status;
  end if;

  update public.cleaning_visits
     set status = 'in_progress',
         submitted_at = null, submitted_by = null,
         reviewed_at = null, closed_at = null,
         version_no = version_no + 1
   where id = p_visit_id
   returning version_no into v_new_version;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'cleaning_visit', p_visit_id, 'reopened',
            jsonb_build_object('reason', p_reason));
  return v_new_version;
end;
$$;
revoke all on function public.rpc_reopen_visit(uuid, text) from public;
grant execute on function public.rpc_reopen_visit(uuid, text) to authenticated;

-- =====================================================================
-- Review RPCs (start draft, save draft, submit, supersede)
-- =====================================================================
create or replace function public.rpc_start_review_draft(
  p_visit_id uuid,
  p_review_type public.review_type default 'dm_lightweight'
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid; v_status public.cleaning_visit_status;
  v_review_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select site_id, status into v_site, v_status
    from public.cleaning_visits where id = p_visit_id;
  if v_site is null then raise exception 'visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_dm_reviewer','ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;
  if v_status not in ('submitted_for_review','reviewed') then
    raise exception 'visit not ready for review (status %)', v_status;
  end if;

  -- Reuse an existing draft if present
  select id into v_review_id from public.reviews
    where cleaning_visit_id = p_visit_id and status = 'draft' and reviewer_id = v_uid
    limit 1;
  if v_review_id is null then
    insert into public.reviews(cleaning_visit_id, review_type, status, reviewer_id)
      values (p_visit_id, p_review_type, 'draft', v_uid)
      returning id into v_review_id;
  end if;
  return v_review_id;
end;
$$;
revoke all on function public.rpc_start_review_draft(uuid, public.review_type) from public;
grant execute on function public.rpc_start_review_draft(uuid, public.review_type) to authenticated;

create or replace function public.rpc_save_review_draft(
  p_review_id uuid, p_expected_version bigint, p_payload jsonb
) returns bigint
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_status public.review_status; v_version bigint;
  v_new_version bigint;
  r jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select cleaning_visit_id, status, version_no into v_visit, v_status, v_version
    from public.reviews where id = p_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'draft' then raise exception 'review not editable in status %', v_status; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;

  select site_id into v_site from public.cleaning_visits where id = v_visit;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_dm_reviewer','ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  update public.reviews
     set general_comment = coalesce(p_payload->>'general_comment', general_comment),
         urgent_hs_flag = coalesce((p_payload->>'urgent_hs_flag')::boolean, urgent_hs_flag),
         urgent_hs_detail = p_payload->>'urgent_hs_detail'
   where id = p_review_id;

  if p_payload ? 'line_scores' then
    for r in select * from jsonb_array_elements(p_payload->'line_scores') loop
      insert into public.review_line_scores(
        review_id, visit_rating_line_id, score, rating_band, comment,
        is_failure, scope_classification, issue_type_code, urgent_hs_flag)
      values (
        p_review_id, (r->>'visit_rating_line_id')::uuid,
        nullif(r->>'score','')::int, r->>'rating_band', r->>'comment',
        coalesce((r->>'is_failure')::boolean, false),
        nullif(r->>'scope_classification','')::public.scope_classification,
        nullif(r->>'issue_type_code',''),
        coalesce((r->>'urgent_hs_flag')::boolean, false))
      on conflict (review_id, visit_rating_line_id) do update
        set score = excluded.score,
            rating_band = excluded.rating_band,
            comment = excluded.comment,
            is_failure = excluded.is_failure,
            scope_classification = excluded.scope_classification,
            issue_type_code = excluded.issue_type_code,
            urgent_hs_flag = excluded.urgent_hs_flag;
    end loop;
  end if;

  if p_payload ? 'focus_scores' then
    for r in select * from jsonb_array_elements(p_payload->'focus_scores') loop
      insert into public.focus_item_scores(
        review_id, visit_focus_item_id, rating_band, comment,
        is_failure, scope_classification, issue_type_code, urgent_hs_flag)
      values (
        p_review_id, (r->>'visit_focus_item_id')::uuid,
        r->>'rating_band', r->>'comment',
        coalesce((r->>'is_failure')::boolean, false),
        nullif(r->>'scope_classification','')::public.scope_classification,
        nullif(r->>'issue_type_code',''),
        coalesce((r->>'urgent_hs_flag')::boolean, false))
      on conflict (review_id, visit_focus_item_id) do update
        set rating_band = excluded.rating_band,
            comment = excluded.comment,
            is_failure = excluded.is_failure,
            scope_classification = excluded.scope_classification,
            issue_type_code = excluded.issue_type_code,
            urgent_hs_flag = excluded.urgent_hs_flag;
    end loop;
  end if;

  update public.reviews set version_no = version_no + 1 where id = p_review_id
    returning version_no into v_new_version;
  return v_new_version;
end;
$$;
revoke all on function public.rpc_save_review_draft(uuid, bigint, jsonb) from public;
grant execute on function public.rpc_save_review_draft(uuid, bigint, jsonb) to authenticated;

create or replace function public.rpc_submit_review(p_review_id uuid, p_expected_version bigint)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_version bigint; v_status public.review_status;
  rls record;
  fis record;
  v_action_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select cleaning_visit_id, status, version_no into v_visit, v_status, v_version
    from public.reviews where id = p_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'draft' then raise exception 'review already %', v_status; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;

  select site_id into v_site from public.cleaning_visits where id = v_visit;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_dm_reviewer','ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  update public.reviews set status='submitted', submitted_at=now(), reviewer_id=v_uid where id = p_review_id;

  -- Auto-actions for failures
  for rls in select * from public.review_line_scores where review_id = p_review_id and is_failure loop
    insert into public.actions(
      site_id, cleaning_visit_id, title, description, scope_classification,
      priority, status, source_review_line_score_id, urgent_hs_flag, created_by)
    values (
      v_site, v_visit,
      'Review failure: rating line', coalesce(rls.comment, ''),
      coalesce(rls.scope_classification, 'routine_cleaning'),
      case when rls.urgent_hs_flag then 'urgent' else 'normal' end::public.action_priority,
      'open', rls.id, rls.urgent_hs_flag, v_uid)
    on conflict do nothing
    returning id into v_action_id;
  end loop;
  for fis in select * from public.focus_item_scores where review_id = p_review_id and is_failure loop
    insert into public.actions(
      site_id, cleaning_visit_id, title, description, scope_classification,
      priority, status, source_focus_item_score_id, urgent_hs_flag, created_by)
    values (
      v_site, v_visit,
      'Focus issue', coalesce(fis.comment, ''),
      coalesce(fis.scope_classification, 'rotating_focus'),
      case when fis.urgent_hs_flag then 'urgent' else 'normal' end::public.action_priority,
      'open', fis.id, fis.urgent_hs_flag, v_uid)
    on conflict do nothing
    returning id into v_action_id;
  end loop;

  update public.cleaning_visits
     set status = case when status = 'submitted_for_review' then 'reviewed' else status end,
         reviewed_at = case when status = 'submitted_for_review' then now() else reviewed_at end,
         version_no = version_no + 1
   where id = v_visit;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action)
    values (v_site, v_uid, 'review', p_review_id, 'submitted');
  return p_review_id;
end;
$$;
revoke all on function public.rpc_submit_review(uuid, bigint) from public;
grant execute on function public.rpc_submit_review(uuid, bigint) to authenticated;

create or replace function public.rpc_supersede_review(
  p_original_review_id uuid, p_reason text
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_status public.review_status; v_type public.review_type;
  v_new_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(p_reason, '') = '' then raise exception 'reason required'; end if;

  select cleaning_visit_id, status, review_type into v_visit, v_status, v_type
    from public.reviews where id = p_original_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'submitted' then raise exception 'only submitted reviews can be superseded'; end if;

  select site_id into v_site from public.cleaning_visits where id = v_visit;
  if not tms_internal.has_site_role(v_uid, v_site, array['ops_manager','gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  insert into public.reviews(cleaning_visit_id, review_type, status, reviewer_id, supersedes_review_id)
    values (v_visit, v_type, 'draft', v_uid, p_original_review_id)
    returning id into v_new_id;

  update public.reviews
     set status = 'superseded', superseded_at = now(), superseded_by_review_id = v_new_id
   where id = p_original_review_id;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'review', p_original_review_id, 'superseded',
            jsonb_build_object('reason', p_reason, 'new_review_id', v_new_id));
  return v_new_id;
end;
$$;
revoke all on function public.rpc_supersede_review(uuid, text) from public;
grant execute on function public.rpc_supersede_review(uuid, text) to authenticated;

-- =====================================================================
-- Action RPCs
-- =====================================================================
create or replace function public.rpc_progress_action(
  p_action_id uuid, p_expected_version bigint,
  p_new_status public.action_status,
  p_note text default null,
  p_assignee_id uuid default null
) returns bigint
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid(); v_site uuid; v_version bigint; v_new bigint;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select site_id, version_no into v_site, v_version
    from public.actions where id = p_action_id for update;
  if v_site is null then raise exception 'action not found'; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;
  if not tms_internal.has_any_site_access(v_uid, v_site) then raise exception 'forbidden'; end if;

  update public.actions
     set status = p_new_status,
         verification_note = coalesce(p_note, verification_note),
         assignee_id = coalesce(p_assignee_id, assignee_id),
         closed_at = case when p_new_status = 'closed' then now() else closed_at end,
         cancelled_at = case when p_new_status = 'cancelled' then now() else cancelled_at end,
         version_no = version_no + 1
   where id = p_action_id
   returning version_no into v_new;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'action', p_action_id, p_new_status::text,
            jsonb_build_object('note', p_note));
  return v_new;
end;
$$;
revoke all on function public.rpc_progress_action(uuid,bigint,public.action_status,text,uuid) from public;
grant execute on function public.rpc_progress_action(uuid,bigint,public.action_status,text,uuid) to authenticated;

-- =====================================================================
-- Evidence finalisation
-- =====================================================================
create or replace function public.rpc_finalise_evidence_upload(
  p_site_id uuid, p_storage_path text, p_mime text, p_byte_size bigint,
  p_entity_kind text, p_entity_id uuid, p_caption text default null
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_evidence_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.has_any_site_access(v_uid, p_site_id) then raise exception 'forbidden'; end if;
  if p_storage_path not like (p_site_id::text || '/%') then
    raise exception 'storage_path must begin with site id';
  end if;
  if p_mime not in ('image/jpeg','image/png','image/webp','image/heic','application/pdf') then
    raise exception 'unsupported mime: %', p_mime;
  end if;
  if p_byte_size > 10 * 1024 * 1024 then
    raise exception 'file too large';
  end if;

  insert into public.evidence_items(site_id, bucket, storage_path, mime_type, byte_size, uploaded_by)
    values (p_site_id, 'evidence', p_storage_path, p_mime, p_byte_size, v_uid)
    on conflict (bucket, storage_path) do update set mime_type = excluded.mime_type
    returning id into v_evidence_id;

  if p_entity_kind = 'visit_focus_item' then
    insert into public.visit_focus_item_evidence(visit_focus_item_id, evidence_item_id, caption)
      values (p_entity_id, v_evidence_id, p_caption) on conflict do nothing;
  elsif p_entity_kind = 'review_line_score' then
    insert into public.review_line_score_evidence(review_line_score_id, evidence_item_id, caption)
      values (p_entity_id, v_evidence_id, p_caption) on conflict do nothing;
  elsif p_entity_kind = 'focus_item_score' then
    insert into public.focus_item_score_evidence(focus_item_score_id, evidence_item_id, caption)
      values (p_entity_id, v_evidence_id, p_caption) on conflict do nothing;
  else
    raise exception 'unknown entity_kind: %', p_entity_kind;
  end if;
  return v_evidence_id;
end;
$$;
revoke all on function public.rpc_finalise_evidence_upload(uuid,text,text,bigint,text,uuid,text) from public;
grant execute on function public.rpc_finalise_evidence_upload(uuid,text,text,bigint,text,uuid,text) to authenticated;

-- =====================================================================
-- Admin: list unfinalised evidence (admin-only)
-- =====================================================================
create or replace function public.rpc_list_unfinalised_evidence(
  p_site_id uuid, p_older_than interval default interval '24 hours'
) returns table (storage_path text, byte_size bigint, created_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;
  return query
    select o.name, (o.metadata->>'size')::bigint, o.created_at
      from storage.objects o
      left join public.evidence_items ei
        on ei.bucket = o.bucket_id and ei.storage_path = o.name
     where o.bucket_id = 'evidence'
       and o.name like (p_site_id::text || '/%')
       and ei.id is null
       and o.created_at < (now() - p_older_than);
end;
$$;
revoke all on function public.rpc_list_unfinalised_evidence(uuid, interval) from public;
grant execute on function public.rpc_list_unfinalised_evidence(uuid, interval) to authenticated;

-- =====================================================================
-- Admin user/role RPCs
-- =====================================================================
create or replace function public.rpc_assign_site_role(
  p_user_id uuid, p_role_code text, p_site_id uuid
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;
  insert into public.user_site_roles(user_id, role_code, site_id, granted_by)
    values (p_user_id, p_role_code, p_site_id, v_uid)
    on conflict do nothing returning id into v_id;
  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (p_site_id, v_uid, 'user_site_role', coalesce(v_id, gen_random_uuid()), 'granted',
            jsonb_build_object('user_id', p_user_id, 'role_code', p_role_code));
  return v_id;
end;
$$;
revoke all on function public.rpc_assign_site_role(uuid, text, uuid) from public;
grant execute on function public.rpc_assign_site_role(uuid, text, uuid) to authenticated;

create or replace function public.rpc_revoke_site_role(p_assignment_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid(); v_site uuid; v_user uuid; v_role text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;
  select site_id, user_id, role_code into v_site, v_user, v_role
    from public.user_site_roles where id = p_assignment_id;
  delete from public.user_site_roles where id = p_assignment_id;
  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'user_site_role', p_assignment_id, 'revoked',
            jsonb_build_object('user_id', v_user, 'role_code', v_role));
end;
$$;
revoke all on function public.rpc_revoke_site_role(uuid) from public;
grant execute on function public.rpc_revoke_site_role(uuid) to authenticated;

-- =====================================================================
-- Dashboard view (security_invoker)
-- =====================================================================
create or replace view public.v_dashboard_counters with (security_invoker = true) as
select
  s.id as site_id,
  s.name as site_name,
  (select count(*) from public.cleaning_visits cv
    where cv.site_id = s.id and cv.status in ('draft','planned','in_progress')) as visits_open,
  (select count(*) from public.cleaning_visits cv
    where cv.site_id = s.id and cv.status = 'submitted_for_review') as visits_awaiting_review,
  (select count(*) from public.actions a
    where a.site_id = s.id and a.status not in ('closed','cancelled')) as actions_open,
  (select count(*) from public.actions a
    where a.site_id = s.id and a.status not in ('closed','cancelled') and a.urgent_hs_flag) as actions_urgent_hs
from public.sites s
where s.archived_at is null;
grant select on public.v_dashboard_counters to authenticated;
