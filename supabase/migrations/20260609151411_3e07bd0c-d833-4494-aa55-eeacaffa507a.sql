
-- ============================================================================
-- M4 completion repair migration
-- Forward-only fixes; does not modify any previously applied migration files.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Fix legacy role codes in supervisor handover RPCs (TMS-only ownership).
--    Previous body referenced site_supervisor/ops_manager/gm which were
--    removed by the canonical-role migration.
-- ---------------------------------------------------------------------------
create or replace function public.rpc_save_visit_draft(
  p_visit_id uuid, p_expected_version bigint, p_payload jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_site uuid;
  v_status public.cleaning_visit_status;
  v_version bigint;
  v_new_version bigint;
  r jsonb;
  v_focus_ids uuid[];
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select site_id, status, version_no into v_site, v_status, v_version
    from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;

  -- TMS-only ownership for the supervisor handover.
  if not tms_internal.has_site_role(v_uid, v_site,
       array['tms_supervisor','tms_operative','tms_admin']) then
    raise exception 'forbidden';
  end if;

  if v_status not in ('draft','planned','in_progress') then
    raise exception 'visit not editable in status %', v_status;
  end if;
  if v_version <> p_expected_version then
    raise exception 'stale_version' using errcode='40001';
  end if;

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

  -- Recommendations: partial update + reconcile linked focus items when
  -- the recommendation is moved away from 'selected'.
  if p_payload ? 'recommendations' then
    for r in select * from jsonb_array_elements(p_payload->'recommendations')
    loop
      update public.visit_focus_recommendations
         set recommendation_status = coalesce(r->>'recommendation_status', recommendation_status),
             resolution_reason     = r->>'resolution_reason'
       where id = (r->>'id')::uuid
         and cleaning_visit_id = p_visit_id;

      if (r->>'recommendation_status') in ('skipped','inaccessible','not_applicable') then
        delete from public.visit_focus_items
         where cleaning_visit_id = p_visit_id
           and source_recommendation_id = (r->>'id')::uuid;
      end if;
    end loop;
  end if;

  -- Focus items: full id-set replacement semantics.
  -- Caller submits the complete intended set; we delete anything missing,
  -- then upsert each entry. Ad-hoc rows (no id) are inserted.
  if p_payload ? 'focus_items' then
    select coalesce(array_agg((e->>'id')::uuid) filter (where (e->>'id') is not null and (e->>'id') <> ''), '{}')
      into v_focus_ids
      from jsonb_array_elements(p_payload->'focus_items') e;

    delete from public.visit_focus_items
     where cleaning_visit_id = p_visit_id
       and (v_focus_ids = '{}'::uuid[] or id <> all(v_focus_ids));

    for r in select * from jsonb_array_elements(p_payload->'focus_items')
    loop
      if (r ? 'id') and coalesce(r->>'id','') <> '' then
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

  if p_payload ? 'constraints' then
    delete from public.visit_constraints where cleaning_visit_id = p_visit_id;
    insert into public.visit_constraints(cleaning_visit_id, constraint_type, description, affected_area)
    select p_visit_id, c->>'constraint_type', c->>'description', c->>'affected_area'
      from jsonb_array_elements(p_payload->'constraints') c;
  end if;

  if p_payload ? 'team_members' then
    delete from public.visit_team_members where cleaning_visit_id = p_visit_id;
    insert into public.visit_team_members(cleaning_visit_id, user_id, full_name, role_on_visit)
    select p_visit_id, nullif(t->>'user_id','')::uuid, t->>'full_name', t->>'role_on_visit'
      from jsonb_array_elements(p_payload->'team_members') t;
  end if;

  update public.cleaning_visits set version_no = version_no + 1
   where id = p_visit_id returning version_no into v_new_version;
  return v_new_version;
end $function$;

create or replace function public.rpc_submit_supervisor_handover(
  p_visit_id uuid, p_expected_version bigint)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
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
       array['tms_supervisor','tms_operative','tms_admin']) then
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
end $function$;

-- ---------------------------------------------------------------------------
-- 2. Tighten rpc_submit_review with fixed rating-line completeness.
--    Every visit_rating_lines row must have a corresponding review_line_scores
--    row that is either a 1-5 rating or is_na with a non-empty reason.
-- ---------------------------------------------------------------------------
create or replace function public.rpc_submit_review(
  p_review_id uuid, p_expected_version bigint)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_version bigint; v_status public.review_status;
  v_visit_status public.cleaning_visit_status; v_reviewer uuid;
  v_missing int;
  rls record; fis record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select cleaning_visit_id, status, version_no, reviewer_id
    into v_visit, v_status, v_version, v_reviewer
    from public.reviews where id = p_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'draft' then raise exception 'review already %', v_status; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;
  if v_reviewer is distinct from v_uid and not tms_internal.is_tms_admin(v_uid) then
    raise exception 'not_review_owner';
  end if;

  select site_id, status into v_site, v_visit_status
    from public.cleaning_visits where id = v_visit for update;
  if v_visit_status not in ('submitted_for_review','reviewed') then
    raise exception 'visit_state_changed' using detail=format('visit status=%s', v_visit_status);
  end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_dm_reviewer','centre_operations_manager','centre_gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  -- Completeness: every visit rating line must have a usable score row.
  select count(*) into v_missing
    from public.visit_rating_lines vrl
    left join public.review_line_scores rls
      on rls.review_id = p_review_id and rls.visit_rating_line_id = vrl.id
   where vrl.cleaning_visit_id = v_visit
     and (rls.id is null
          or (rls.is_na = false and rls.rating is null)
          or (rls.is_na = true  and coalesce(rls.na_reason,'') = ''));
  if v_missing > 0 then
    raise exception 'review_incomplete'
      using detail = format('% rating lines need a 1-5 score or N/A with reason', v_missing);
  end if;

  -- Snapshots
  update public.review_line_scores rls
     set line_label_snapshot = vrl.label_snapshot
    from public.visit_rating_lines vrl
   where vrl.id = rls.visit_rating_line_id
     and rls.review_id = p_review_id
     and rls.line_label_snapshot is null;
  update public.focus_item_scores fis
     set focus_label_snapshot = vfi.focus_name_snapshot,
         focus_location_snapshot = vfi.exact_location,
         focus_acceptance_snapshot = fi.acceptance_standard
    from public.visit_focus_items vfi
    left join public.focus_items fi on fi.id = vfi.focus_item_id
   where vfi.id = fis.visit_focus_item_id
     and fis.review_id = p_review_id
     and fis.focus_label_snapshot is null;

  update public.reviews
     set status='submitted', submitted_at=now()
   where id = p_review_id;

  -- Auto-actions for failures
  for rls in select * from public.review_line_scores
              where review_id = p_review_id and is_failure loop
    insert into public.actions(
      site_id, cleaning_visit_id, title, description, scope_classification,
      priority, status, source_review_line_score_id, urgent_hs_flag, created_by)
    values (
      v_site, v_visit,
      'Review failure: rating line', coalesce(rls.comment, ''),
      coalesce(rls.scope_classification, 'routine_cleaning'),
      case when rls.urgent_hs_flag then 'urgent' else 'normal' end::public.action_priority,
      'open', rls.id, rls.urgent_hs_flag, v_uid)
    on conflict do nothing;
  end loop;
  for fis in select * from public.focus_item_scores
              where review_id = p_review_id and is_failure loop
    insert into public.actions(
      site_id, cleaning_visit_id, title, description, scope_classification,
      priority, status, source_focus_item_score_id, urgent_hs_flag, created_by)
    values (
      v_site, v_visit,
      'Focus issue', coalesce(fis.comment, ''),
      coalesce(fis.scope_classification, 'rotating_focus'),
      case when fis.urgent_hs_flag then 'urgent' else 'normal' end::public.action_priority,
      'open', fis.id, fis.urgent_hs_flag, v_uid)
    on conflict do nothing;
  end loop;

  update public.cleaning_visits
     set status = case when status = 'submitted_for_review' then 'reviewed' else status end,
         reviewed_at = case when status = 'submitted_for_review' then now() else reviewed_at end,
         version_no = version_no + 1
   where id = v_visit;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action)
    values (v_site, v_uid, 'review', p_review_id, 'submitted');
  return p_review_id;
end $function$;

-- ---------------------------------------------------------------------------
-- 3. Prevent multiple concurrent draft reviews per visit (one owner at a time).
-- ---------------------------------------------------------------------------
create unique index if not exists ux_reviews_one_active_draft_per_visit
  on public.reviews(cleaning_visit_id)
  where status = 'draft';

-- ---------------------------------------------------------------------------
-- 4. Last-admin guard on role revocation.
-- ---------------------------------------------------------------------------
create or replace function public.rpc_revoke_site_role(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare v_uid uuid := auth.uid(); v_site uuid; v_user uuid; v_role text;
        v_remaining int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;

  select site_id, user_id, role_code into v_site, v_user, v_role
    from public.user_site_roles where id = p_assignment_id;
  if v_role is null then raise exception 'assignment not found'; end if;

  if v_role = 'tms_admin' and v_site is null then
    select count(*) into v_remaining
      from public.user_site_roles
     where role_code = 'tms_admin' and site_id is null and id <> p_assignment_id;
    if v_remaining = 0 then
      raise exception 'last_tms_admin_protected'
        using hint = 'Assign tms_admin to another user before revoking this one';
    end if;
  end if;

  delete from public.user_site_roles where id = p_assignment_id;
  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'user_site_role', p_assignment_id, 'revoked',
            jsonb_build_object('user_id', v_user, 'role_code', v_role));
end $function$;
