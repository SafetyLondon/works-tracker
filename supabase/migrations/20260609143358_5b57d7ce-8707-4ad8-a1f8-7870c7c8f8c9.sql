
-- =====================================================================
-- A6: action permission matrix + scope-based assignee eligibility
-- =====================================================================

create or replace function tms_internal.action_assignee_eligible(
  _user uuid, _site uuid, _scope public.scope_classification
) returns boolean
  language sql stable security definer set search_path = pg_catalog, public
as $$
  select case
    when _scope in ('routine_cleaning','rotating_focus','equipment_chemical') then
      tms_internal.has_site_role(_user, _site, array['tms_admin','tms_supervisor','tms_operative'])
    when _scope in ('maintenance_site_fabric','access','out_of_scope','additional_resource','urgent_hs') then
      tms_internal.has_site_role(_user, _site, array['tms_admin','tms_supervisor','centre_operations_manager','centre_gm'])
    else false
  end;
$$;
revoke all on function tms_internal.action_assignee_eligible(uuid,uuid,public.scope_classification) from public, anon;
grant execute on function tms_internal.action_assignee_eligible(uuid,uuid,public.scope_classification) to authenticated;

create or replace function public.tms_validate_action_assignee()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.assignee_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.assignee_id is not distinct from old.assignee_id
     and new.scope_classification is not distinct from old.scope_classification then
    return new;
  end if;
  if not tms_internal.action_assignee_eligible(new.assignee_id, new.site_id, new.scope_classification) then
    raise exception 'assignee is not eligible for action scope % at this site', new.scope_classification
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists trg_actions_assignee_eligible on public.actions;
create trigger trg_actions_assignee_eligible
  before insert or update of assignee_id, scope_classification on public.actions
  for each row execute function public.tms_validate_action_assignee();

create or replace function public.rpc_progress_action(
  p_action_id uuid, p_expected_version bigint, p_new_status public.action_status,
  p_note text default null, p_assignee_id uuid default null
) returns bigint
  language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid; v_version bigint; v_status public.action_status;
  v_assignee uuid; v_scope public.scope_classification;
  v_is_assignee boolean; v_is_admin boolean; v_is_supervisor boolean; v_is_verifier boolean;
  v_new bigint; v_allowed boolean := false;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select site_id, version_no, status, assignee_id, scope_classification
    into v_site, v_version, v_status, v_assignee, v_scope
    from public.actions where id = p_action_id for update;
  if v_site is null then raise exception 'action not found'; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;

  v_is_admin      := tms_internal.is_tms_admin(v_uid);
  v_is_supervisor := tms_internal.has_site_role(v_uid, v_site, array['tms_supervisor']);
  v_is_verifier   := tms_internal.has_site_role(v_uid, v_site,
                       array['tms_admin','tms_supervisor','centre_operations_manager','centre_gm']);
  v_is_assignee   := v_assignee is not distinct from v_uid;

  v_allowed := case
    when p_assignee_id is not null and p_assignee_id is distinct from v_assignee then
      (v_is_admin or v_is_supervisor)
    when p_new_status = 'cancelled' then (v_is_admin or v_is_supervisor)
    when v_status = 'open' and p_new_status = 'assigned' then (v_is_admin or v_is_supervisor)
    when v_status = 'open' and p_new_status = 'in_progress' then
      (v_is_admin or v_is_supervisor or v_is_assignee
       or tms_internal.action_assignee_eligible(v_uid, v_site, v_scope))
    when v_status = 'assigned' and p_new_status in ('in_progress','blocked') then
      (v_is_admin or v_is_supervisor or v_is_assignee)
    when v_status = 'in_progress' and p_new_status in ('blocked','awaiting_verification') then
      (v_is_admin or v_is_supervisor or v_is_assignee)
    when v_status = 'blocked' and p_new_status = 'in_progress' then
      (v_is_admin or v_is_supervisor or v_is_assignee)
    when v_status = 'awaiting_verification' and p_new_status = 'closed' then
      (v_is_verifier and not v_is_assignee)
    when v_status = 'awaiting_verification' and p_new_status = 'in_progress' then
      v_is_verifier
    else false
  end;
  if not v_allowed then
    raise exception 'forbidden_transition' using detail=format('%s -> %s by %s', v_status, p_new_status, v_uid);
  end if;

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
            jsonb_build_object('note', p_note, 'assignee_id', p_assignee_id));
  return v_new;
end $$;
revoke all on function public.rpc_progress_action(uuid,bigint,public.action_status,text,uuid) from public, anon;
grant execute on function public.rpc_progress_action(uuid,bigint,public.action_status,text,uuid) to authenticated;

-- =====================================================================
-- A7: supersede pair + reopen reconciliation
-- =====================================================================

drop function if exists public.rpc_supersede_review(uuid, text);

create or replace function public.rpc_reopen_visit(p_visit_id uuid, p_reason text)
returns bigint language plpgsql security definer set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid(); v_site uuid; v_status public.cleaning_visit_status;
        v_new_version bigint; v_draft_count int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(p_reason,'') = '' then raise exception 'reason required'; end if;
  select site_id, status into v_site, v_status from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_operations_manager','centre_gm','tms_admin']) then
    raise exception 'forbidden';
  end if;
  if v_status not in ('submitted_for_review','reviewed','closed') then
    raise exception 'cannot reopen from status %', v_status;
  end if;

  select count(*) into v_draft_count from public.reviews
   where cleaning_visit_id = p_visit_id and status = 'draft';
  if v_draft_count > 0 then
    raise exception 'cannot_reopen_with_active_draft'
      using hint = 'Use rpc_admin_reopen_visit_with_cancel to cancel the draft as part of the reopen';
  end if;

  update public.cleaning_visits
     set status = 'in_progress', submitted_at = null, submitted_by = null,
         reviewed_at = null, closed_at = null, version_no = version_no + 1
   where id = p_visit_id returning version_no into v_new_version;
  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'cleaning_visit', p_visit_id, 'reopened', jsonb_build_object('reason', p_reason));
  return v_new_version;
end $$;

create or replace function public.rpc_admin_reopen_visit_with_cancel(
  p_visit_id uuid, p_reason text, p_cancel_draft_review_id uuid
) returns bigint language plpgsql security definer set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid(); v_site uuid; v_status public.cleaning_visit_status;
        v_draft_visit uuid; v_draft_status public.review_status; v_new_version bigint;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;
  if coalesce(p_reason,'') = '' then raise exception 'reason required'; end if;

  select site_id, status into v_site, v_status from public.cleaning_visits where id = p_visit_id for update;
  if v_site is null then raise exception 'visit not found'; end if;
  if v_status not in ('submitted_for_review','reviewed','closed') then
    raise exception 'cannot reopen from status %', v_status;
  end if;

  select cleaning_visit_id, status into v_draft_visit, v_draft_status
    from public.reviews where id = p_cancel_draft_review_id for update;
  if v_draft_visit is null then raise exception 'draft review not found'; end if;
  if v_draft_visit <> p_visit_id then raise exception 'draft review does not belong to this visit'; end if;
  if v_draft_status <> 'draft' then raise exception 'only draft reviews can be cancelled via this RPC'; end if;

  delete from public.review_line_scores where review_id = p_cancel_draft_review_id;
  delete from public.focus_item_scores where review_id = p_cancel_draft_review_id;
  delete from public.reviews where id = p_cancel_draft_review_id;

  if exists (select 1 from public.reviews where cleaning_visit_id = p_visit_id and status='draft') then
    raise exception 'other draft reviews still exist for this visit';
  end if;

  update public.cleaning_visits
     set status = 'in_progress', submitted_at = null, submitted_by = null,
         reviewed_at = null, closed_at = null, version_no = version_no + 1
   where id = p_visit_id returning version_no into v_new_version;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'cleaning_visit', p_visit_id, 'reopened_with_draft_cancel',
            jsonb_build_object('reason', p_reason, 'cancelled_draft_review_id', p_cancel_draft_review_id));
  return v_new_version;
end $$;

create or replace function public.rpc_create_superseding_review(
  p_original_review_id uuid, p_reason text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid();
        v_visit uuid; v_site uuid; v_status public.review_status; v_type public.review_type;
        v_new_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(p_reason,'') = '' then raise exception 'reason required'; end if;
  select cleaning_visit_id, status, review_type into v_visit, v_status, v_type
    from public.reviews where id = p_original_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'submitted' then raise exception 'only submitted reviews can be superseded'; end if;

  select site_id into v_site from public.cleaning_visits where id = v_visit;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_operations_manager','centre_gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  insert into public.reviews(
    cleaning_visit_id, review_type, status, reviewer_id, supersedes_review_id,
    general_comment, urgent_hs_flag, urgent_hs_detail)
  select v_visit, v_type, 'draft', v_uid, p_original_review_id,
         general_comment, urgent_hs_flag, urgent_hs_detail
    from public.reviews where id = p_original_review_id
  returning id into v_new_id;

  insert into public.review_line_scores(
    review_id, cleaning_visit_id, visit_rating_line_id, rating, is_na, na_reason, comment,
    scope_classification, issue_type_code, urgent_hs_flag, line_label_snapshot)
  select v_new_id, cleaning_visit_id, visit_rating_line_id, rating, is_na, na_reason, comment,
         scope_classification, issue_type_code, urgent_hs_flag, line_label_snapshot
    from public.review_line_scores where review_id = p_original_review_id;

  insert into public.focus_item_scores(
    review_id, cleaning_visit_id, visit_focus_item_id, rating, is_na, na_reason, comment,
    scope_classification, issue_type_code, urgent_hs_flag,
    focus_label_snapshot, focus_location_snapshot, focus_acceptance_snapshot)
  select v_new_id, cleaning_visit_id, visit_focus_item_id, rating, is_na, na_reason, comment,
         scope_classification, issue_type_code, urgent_hs_flag,
         focus_label_snapshot, focus_location_snapshot, focus_acceptance_snapshot
    from public.focus_item_scores where review_id = p_original_review_id;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'review', p_original_review_id, 'supersede_draft_created',
            jsonb_build_object('reason', p_reason, 'new_review_id', v_new_id));
  return v_new_id;
end $$;

create or replace function public.rpc_submit_superseding_review(
  p_new_review_id uuid, p_expected_version bigint
) returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid();
        v_visit uuid; v_site uuid; v_version bigint; v_status public.review_status;
        v_orig uuid; v_orig_status public.review_status;
        v_visit_status public.cleaning_visit_status; v_reviewer uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select cleaning_visit_id, status, version_no, supersedes_review_id, reviewer_id
    into v_visit, v_status, v_version, v_orig, v_reviewer
    from public.reviews where id = p_new_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'draft' then raise exception 'review already %', v_status; end if;
  if v_orig is null then raise exception 'not a superseding review'; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;
  if v_reviewer is distinct from v_uid and not tms_internal.is_tms_admin(v_uid) then
    raise exception 'not_review_owner';
  end if;

  select status into v_orig_status from public.reviews where id = v_orig for update;
  if v_orig_status <> 'submitted' then raise exception 'original review no longer submitted'; end if;

  select site_id, status into v_site, v_visit_status from public.cleaning_visits where id = v_visit for update;
  if v_visit_status not in ('submitted_for_review','reviewed') then
    raise exception 'visit_state_changed' using detail=format('visit status=%s', v_visit_status);
  end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_operations_manager','centre_gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  update public.reviews set status='submitted', submitted_at=now() where id = p_new_review_id;
  update public.reviews set status='superseded', superseded_at=now(), superseded_by_review_id=p_new_review_id
   where id = v_orig;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'review', v_orig, 'superseded',
            jsonb_build_object('new_review_id', p_new_review_id));
  return p_new_review_id;
end $$;

-- =====================================================================
-- A9: dup visit + profile policy + directory RPC + structured create
-- =====================================================================

create unique index if not exists ux_visit_site_template_date
  on public.cleaning_visits(site_id, visit_template_id, visit_date)
  where status <> 'cancelled';

drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or tms_internal.is_tms_admin(auth.uid()));

create or replace function public.rpc_site_user_directory(p_site_id uuid)
returns table(user_id uuid, display_name text, role_code text, site_id uuid)
  language plpgsql security definer set search_path = pg_catalog, public stable
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.has_any_site_access(v_uid, p_site_id) then raise exception 'forbidden'; end if;
  return query
    select usr.user_id, p.display_name, usr.role_code, usr.site_id
      from public.user_site_roles usr
      left join public.profiles p on p.id = usr.user_id
     where usr.site_id = p_site_id
        or (usr.site_id is null and exists
             (select 1 from public.user_site_roles s2
               where s2.user_id = usr.user_id and s2.site_id = p_site_id));
end $$;
revoke all on function public.rpc_site_user_directory(uuid) from public, anon;
grant execute on function public.rpc_site_user_directory(uuid) to authenticated;

drop function if exists public.rpc_create_cleaning_visit_from_template(uuid, uuid, date, uuid, int, text, text);
create or replace function public.rpc_create_cleaning_visit_from_template(
  p_site_id uuid, p_visit_template_id uuid, p_visit_date date,
  p_rotation_programme_id uuid default null,
  p_rotation_week_override int default null,
  p_rotation_week_override_reason text default null,
  p_weekday_override_reason text default null
) returns jsonb
  language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit_id uuid;
  v_expected_weekday int; v_actual_weekday int;
  v_can_manage boolean; v_can_override boolean;
  v_rec_week int; v_use_week int;
  v_existing_id uuid; v_existing_status public.cleaning_visit_status;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  v_can_manage := tms_internal.has_site_role(v_uid, p_site_id,
    array['tms_supervisor','centre_dm_reviewer','centre_operations_manager','centre_gm','tms_admin']);
  if not v_can_manage then raise exception 'forbidden'; end if;
  v_can_override := tms_internal.has_site_role(v_uid, p_site_id,
    array['tms_supervisor','centre_operations_manager','centre_gm','tms_admin']);

  select id, status into v_existing_id, v_existing_status
    from public.cleaning_visits
   where site_id = p_site_id and visit_template_id = p_visit_template_id
     and visit_date = p_visit_date and status <> 'cancelled' limit 1;
  if v_existing_id is not null then
    return jsonb_build_object('visit_id', v_existing_id, 'created', false,
                              'existing_status', v_existing_status::text);
  end if;

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
    if coalesce(p_weekday_override_reason,'') = '' then
      raise exception 'weekday override requires a reason';
    end if;
  end if;
  if p_rotation_week_override is not null and not v_can_override then
    raise exception 'rotation week override requires supervisor/admin';
  end if;

  if p_rotation_programme_id is not null then
    v_rec_week := tms_internal.recommended_rotation_week(p_rotation_programme_id, p_visit_date);
  end if;
  v_use_week := coalesce(p_rotation_week_override, v_rec_week);

  begin
    insert into public.cleaning_visits(
      site_id, visit_template_id, rotation_programme_id, visit_date,
      recommended_rotation_week, rotation_week_override, rotation_week_override_reason,
      weekday_override_reason, status, supervisor_id, created_by)
    values (
      p_site_id, p_visit_template_id, p_rotation_programme_id, p_visit_date,
      v_rec_week, p_rotation_week_override, p_rotation_week_override_reason,
      p_weekday_override_reason, 'planned', v_uid, v_uid)
    returning id into v_visit_id;
  exception when unique_violation then
    select id, status into v_existing_id, v_existing_status
      from public.cleaning_visits
     where site_id = p_site_id and visit_template_id = p_visit_template_id
       and visit_date = p_visit_date and status <> 'cancelled' limit 1;
    return jsonb_build_object('visit_id', v_existing_id, 'created', false,
                              'existing_status', coalesce(v_existing_status::text, 'unknown'));
  end;

  insert into public.visit_scope_snapshots
    (cleaning_visit_id, item_type, label_snapshot, description_snapshot, display_order, source_template_scope_item_id)
  select v_visit_id, tsi.item_type, tsi.label, tsi.description, tsi.display_order, tsi.id
    from public.template_scope_items tsi
   where tsi.visit_template_id = p_visit_template_id and tsi.archived_at is null
   order by tsi.item_type, tsi.display_order;

  insert into public.visit_rating_lines
    (cleaning_visit_id, visit_template_id, template_rating_line_id, label_snapshot, description_snapshot, display_order)
  select v_visit_id, p_visit_template_id, trl.id, trl.label, trl.description, trl.display_order
    from public.template_rating_lines trl
   where trl.visit_template_id = p_visit_template_id and trl.archived_at is null
   order by trl.display_order;

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
  return jsonb_build_object('visit_id', v_visit_id, 'created', true);
end $$;
revoke all on function public.rpc_create_cleaning_visit_from_template(
  uuid, uuid, date, uuid, int, text, text) from public, anon;
grant execute on function public.rpc_create_cleaning_visit_from_template(
  uuid, uuid, date, uuid, int, text, text) to authenticated;

create or replace function public.rpc_set_rotation_anchor(p_programme_id uuid, p_anchor_date date)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$
declare v_uid uuid := auth.uid(); v_site uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not tms_internal.is_tms_admin(v_uid) then raise exception 'admin only'; end if;
  if p_anchor_date is null then raise exception 'anchor_date required'; end if;
  update public.rotation_programmes set anchor_date = p_anchor_date where id = p_programme_id
    returning site_id into v_site;
  if v_site is null then raise exception 'programme not found'; end if;
  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'rotation_programme', p_programme_id, 'anchor_set',
            jsonb_build_object('anchor_date', p_anchor_date));
end $$;
revoke all on function public.rpc_set_rotation_anchor(uuid, date) from public, anon;
grant execute on function public.rpc_set_rotation_anchor(uuid, date) to authenticated;

-- =====================================================================
-- A10: evidence finalisation hardened + immutability on link tables
-- =====================================================================

create or replace function tms_internal.storage_object_metadata(_path text)
returns table(bucket_id text, name text, mime text, byte_size bigint, obj_exists boolean)
  language sql stable security definer set search_path = pg_catalog, storage, public
as $$
  select o.bucket_id, o.name,
         o.metadata->>'mimetype' as mime,
         (o.metadata->>'size')::bigint as byte_size,
         true as obj_exists
    from storage.objects o
   where o.bucket_id = 'evidence' and o.name = _path
   limit 1;
$$;
revoke all on function tms_internal.storage_object_metadata(text) from public, anon;
grant execute on function tms_internal.storage_object_metadata(text) to authenticated;

drop function if exists public.rpc_finalise_evidence_upload(uuid, text, text, bigint, text, uuid, text);
create or replace function public.rpc_finalise_evidence_upload(
  p_storage_path text,
  p_entity_kind text,
  p_entity_id uuid,
  p_caption text default null
) returns uuid
  language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid; v_visit uuid;
  v_mime text; v_size bigint; v_obj_exists boolean;
  v_evidence_id uuid;
  v_allowed_mime text[] := array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf'];
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  case p_entity_kind
    when 'visit_focus_item' then
      select cv.site_id, cv.id into v_site, v_visit
        from public.visit_focus_items vfi
        join public.cleaning_visits cv on cv.id = vfi.cleaning_visit_id
       where vfi.id = p_entity_id;
    when 'review_line_score' then
      select cv.site_id, cv.id into v_site, v_visit
        from public.review_line_scores rls
        join public.cleaning_visits cv on cv.id = rls.cleaning_visit_id
       where rls.id = p_entity_id;
    when 'focus_item_score' then
      select cv.site_id, cv.id into v_site, v_visit
        from public.focus_item_scores fis
        join public.cleaning_visits cv on cv.id = fis.cleaning_visit_id
       where fis.id = p_entity_id;
    when 'action' then
      select a.site_id, a.cleaning_visit_id into v_site, v_visit
        from public.actions a where a.id = p_entity_id;
    when 'visit_constraint' then
      select cv.site_id, cv.id into v_site, v_visit
        from public.visit_constraints vc
        join public.cleaning_visits cv on cv.id = vc.cleaning_visit_id
       where vc.id = p_entity_id;
    else
      raise exception 'unknown entity_kind: %', p_entity_kind;
  end case;
  if v_site is null then raise exception 'parent entity not found'; end if;

  if not tms_internal.has_any_site_access(v_uid, v_site) then raise exception 'forbidden'; end if;
  if p_storage_path not like (v_site::text || '/%') then
    raise exception 'storage_path must begin with parent site id (%)', v_site;
  end if;

  select sm.mime, sm.byte_size, sm.obj_exists into v_mime, v_size, v_obj_exists
    from tms_internal.storage_object_metadata(p_storage_path) sm;
  if v_obj_exists is null then raise exception 'storage object not found: %', p_storage_path; end if;
  if not (v_mime = any(v_allowed_mime)) then raise exception 'unsupported mime: %', v_mime; end if;
  if v_size > 10 * 1024 * 1024 then raise exception 'file too large (% bytes)', v_size; end if;

  insert into public.evidence_items(site_id, bucket, storage_path, mime_type, byte_size, uploaded_by)
    values (v_site, 'evidence', p_storage_path, v_mime, v_size, v_uid)
    on conflict (bucket, storage_path) do update set mime_type = excluded.mime_type, byte_size = excluded.byte_size
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
  end if;
  return v_evidence_id;
end $$;
revoke all on function public.rpc_finalise_evidence_upload(text,text,uuid,text) from public, anon;
grant execute on function public.rpc_finalise_evidence_upload(text,text,uuid,text) to authenticated;

create or replace function public.tms_protect_review_line_evidence()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
declare v_status public.review_status; v_review uuid;
begin
  v_review := coalesce((case when tg_op='DELETE' then old.review_line_score_id else new.review_line_score_id end), null);
  select r.status into v_status
    from public.review_line_scores rls join public.reviews r on r.id = rls.review_id
   where rls.id = v_review;
  if v_status in ('submitted','superseded') then
    raise exception 'evidence on submitted/superseded reviews is immutable';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

create or replace function public.tms_protect_focus_score_evidence()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
declare v_status public.review_status; v_score uuid;
begin
  v_score := coalesce((case when tg_op='DELETE' then old.focus_item_score_id else new.focus_item_score_id end), null);
  select r.status into v_status
    from public.focus_item_scores fis join public.reviews r on r.id = fis.review_id
   where fis.id = v_score;
  if v_status in ('submitted','superseded') then
    raise exception 'evidence on submitted/superseded reviews is immutable';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists trg_rls_evidence_immutable on public.review_line_score_evidence;
create trigger trg_rls_evidence_immutable
  before insert or update or delete on public.review_line_score_evidence
  for each row execute function public.tms_protect_review_line_evidence();

drop trigger if exists trg_fis_evidence_immutable on public.focus_item_score_evidence;
create trigger trg_fis_evidence_immutable
  before insert or update or delete on public.focus_item_score_evidence
  for each row execute function public.tms_protect_focus_score_evidence();

-- =====================================================================
-- A11: storage policies + path parser
-- =====================================================================

create or replace function tms_internal.evidence_site_from_path(_name text)
returns uuid language plpgsql immutable as $$
declare v_first text; v_uuid uuid;
begin
  if _name is null then return null; end if;
  v_first := split_part(_name, '/', 1);
  begin
    v_uuid := v_first::uuid;
  exception when others then
    return null;
  end;
  return v_uuid;
end $$;
revoke all on function tms_internal.evidence_site_from_path(text) from public, anon;
grant execute on function tms_internal.evidence_site_from_path(text) to authenticated;

drop policy if exists evidence_select on storage.objects;
drop policy if exists evidence_insert on storage.objects;
drop policy if exists evidence_delete on storage.objects;
drop policy if exists evidence_update on storage.objects;

create policy evidence_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and tms_internal.evidence_site_from_path(name) is not null
    and tms_internal.has_any_site_access(auth.uid(), tms_internal.evidence_site_from_path(name))
  );

create policy evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and tms_internal.evidence_site_from_path(name) is not null
    and tms_internal.has_site_role(
      auth.uid(),
      tms_internal.evidence_site_from_path(name),
      array['tms_admin','tms_supervisor','tms_operative','centre_dm_reviewer','centre_operations_manager','centre_gm']
    )
  );

create policy evidence_update on storage.objects
  for update to authenticated
  using (bucket_id = 'evidence' and tms_internal.is_tms_admin(auth.uid()))
  with check (bucket_id = 'evidence' and tms_internal.is_tms_admin(auth.uid()));

create policy evidence_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidence' and tms_internal.is_tms_admin(auth.uid()));

-- =====================================================================
-- Revoke anon on all operational RPCs
-- =====================================================================

revoke all on function public.rpc_save_review_draft(uuid,bigint,jsonb) from anon, public;
grant execute on function public.rpc_save_review_draft(uuid,bigint,jsonb) to authenticated;

revoke all on function public.rpc_submit_review(uuid,bigint) from anon, public;
grant execute on function public.rpc_submit_review(uuid,bigint) to authenticated;

revoke all on function public.rpc_save_visit_draft(uuid,bigint,jsonb) from anon, public;
grant execute on function public.rpc_save_visit_draft(uuid,bigint,jsonb) to authenticated;

revoke all on function public.rpc_submit_supervisor_handover(uuid,bigint) from anon, public;
grant execute on function public.rpc_submit_supervisor_handover(uuid,bigint) to authenticated;

revoke all on function public.rpc_reopen_visit(uuid,text) from anon, public;
grant execute on function public.rpc_reopen_visit(uuid,text) to authenticated;

revoke all on function public.rpc_admin_reopen_visit_with_cancel(uuid,text,uuid) from anon, public;
grant execute on function public.rpc_admin_reopen_visit_with_cancel(uuid,text,uuid) to authenticated;

revoke all on function public.rpc_create_superseding_review(uuid,text) from anon, public;
grant execute on function public.rpc_create_superseding_review(uuid,text) to authenticated;

revoke all on function public.rpc_submit_superseding_review(uuid,bigint) from anon, public;
grant execute on function public.rpc_submit_superseding_review(uuid,bigint) to authenticated;

revoke all on function public.rpc_start_review_draft(uuid, public.review_type) from anon, public;
grant execute on function public.rpc_start_review_draft(uuid, public.review_type) to authenticated;

revoke all on function public.rpc_assign_site_role(uuid,text,uuid) from anon, public;
grant execute on function public.rpc_assign_site_role(uuid,text,uuid) to authenticated;

revoke all on function public.rpc_revoke_site_role(uuid) from anon, public;
grant execute on function public.rpc_revoke_site_role(uuid) to authenticated;

revoke all on function public.rpc_list_unfinalised_evidence(uuid,interval) from anon, public;
grant execute on function public.rpc_list_unfinalised_evidence(uuid,interval) to authenticated;
