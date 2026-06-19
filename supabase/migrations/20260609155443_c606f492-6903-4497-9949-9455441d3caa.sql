
-- Slice A: focus-item scoring + urgent source binding

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS urgent_source_constraint_id uuid
    REFERENCES public.visit_constraints(id) ON DELETE RESTRICT;

-- Replace supersede-immutability trigger so the new column is also pinned during supersede.
CREATE OR REPLACE FUNCTION public.tms_protect_submitted_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    if old.status in ('submitted','superseded') then
      raise exception 'submitted reviews are immutable (id=%)', old.id;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.status in ('submitted','superseded') then
    if old.status = 'submitted' and new.status = 'superseded' then
      if new.id <> old.id
         or new.cleaning_visit_id <> old.cleaning_visit_id
         or new.review_type <> old.review_type
         or new.reviewer_id is distinct from old.reviewer_id
         or new.submitted_at is distinct from old.submitted_at
         or new.general_comment is distinct from old.general_comment
         or new.urgent_hs_flag is distinct from old.urgent_hs_flag
         or new.urgent_hs_detail is distinct from old.urgent_hs_detail
         or new.urgent_source_constraint_id is distinct from old.urgent_source_constraint_id
         or new.supersedes_review_id is distinct from old.supersedes_review_id
         or new.version_no <> old.version_no then
        raise exception 'only status/superseded_at/superseded_by_review_id may change in supersede transition';
      end if;
      return new;
    end if;
    raise exception 'submitted reviews are immutable (id=%, % -> %)', old.id, old.status, new.status;
  end if;
  return new;
end;
$function$;

-- Patched rpc_save_review_draft: accepts urgent_source_constraint_id, and validates it
-- belongs to the same visit if provided. Preserves all other behaviour.
CREATE OR REPLACE FUNCTION public.rpc_save_review_draft(p_review_id uuid, p_expected_version bigint, p_payload jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_status public.review_status; v_version bigint; v_reviewer uuid;
  v_new_version bigint;
  r jsonb;
  v_urgent_constraint uuid;
  v_constraint_visit uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select cleaning_visit_id, status, version_no, reviewer_id
    into v_visit, v_status, v_version, v_reviewer
    from public.reviews where id = p_review_id for update;
  if v_visit is null then raise exception 'review not found'; end if;
  if v_status <> 'draft' then raise exception 'review not editable in status %', v_status; end if;
  if v_version <> p_expected_version then raise exception 'stale_version' using errcode='40001'; end if;
  if v_reviewer is distinct from v_uid and not tms_internal.is_tms_admin(v_uid) then
    raise exception 'not_review_owner';
  end if;

  select site_id into v_site from public.cleaning_visits where id = v_visit;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['centre_dm_reviewer','centre_operations_manager','centre_gm','tms_admin']) then
    raise exception 'forbidden';
  end if;

  update public.reviews
     set general_comment = coalesce(p_payload->>'general_comment', general_comment),
         urgent_hs_flag = coalesce((p_payload->>'urgent_hs_flag')::boolean, urgent_hs_flag),
         urgent_hs_detail = p_payload->>'urgent_hs_detail'
   where id = p_review_id;

  -- urgent constraint source: validated to belong to this visit; null clears.
  if p_payload ? 'urgent_source_constraint_id' then
    v_urgent_constraint := nullif(p_payload->>'urgent_source_constraint_id','')::uuid;
    if v_urgent_constraint is not null then
      select cleaning_visit_id into v_constraint_visit
        from public.visit_constraints where id = v_urgent_constraint;
      if v_constraint_visit is null or v_constraint_visit <> v_visit then
        raise exception 'urgent_source_constraint_id must belong to the same visit';
      end if;
    end if;
    update public.reviews set urgent_source_constraint_id = v_urgent_constraint
     where id = p_review_id;
  end if;

  if p_payload ? 'line_scores' then
    for r in select * from jsonb_array_elements(p_payload->'line_scores') loop
      insert into public.review_line_scores(
        review_id, cleaning_visit_id, visit_rating_line_id,
        rating, is_na, na_reason, comment,
        scope_classification, issue_type_code, urgent_hs_flag)
      select
        p_review_id, v_visit, (r->>'visit_rating_line_id')::uuid,
        nullif(r->>'rating','')::smallint,
        coalesce((r->>'is_na')::boolean, false),
        nullif(r->>'na_reason',''),
        nullif(r->>'comment',''),
        nullif(r->>'scope_classification','')::public.scope_classification,
        nullif(r->>'issue_type_code',''),
        coalesce((r->>'urgent_hs_flag')::boolean, false)
      on conflict (review_id, visit_rating_line_id) do update
        set rating = excluded.rating,
            is_na = excluded.is_na,
            na_reason = excluded.na_reason,
            comment = excluded.comment,
            scope_classification = excluded.scope_classification,
            issue_type_code = excluded.issue_type_code,
            urgent_hs_flag = excluded.urgent_hs_flag;
    end loop;
  end if;

  if p_payload ? 'focus_scores' then
    for r in select * from jsonb_array_elements(p_payload->'focus_scores') loop
      -- Reject focus_score rows whose visit_focus_item does not belong to this visit.
      if not exists (
        select 1 from public.visit_focus_items
         where id = (r->>'visit_focus_item_id')::uuid
           and cleaning_visit_id = v_visit
      ) then
        raise exception 'focus_score visit_focus_item_id % does not belong to this visit', r->>'visit_focus_item_id';
      end if;

      insert into public.focus_item_scores(
        review_id, cleaning_visit_id, visit_focus_item_id,
        rating, is_na, na_reason, comment,
        scope_classification, issue_type_code, urgent_hs_flag)
      select
        p_review_id, v_visit, (r->>'visit_focus_item_id')::uuid,
        nullif(r->>'rating','')::smallint,
        coalesce((r->>'is_na')::boolean, false),
        nullif(r->>'na_reason',''),
        nullif(r->>'comment',''),
        nullif(r->>'scope_classification','')::public.scope_classification,
        nullif(r->>'issue_type_code',''),
        coalesce((r->>'urgent_hs_flag')::boolean, false)
      on conflict (review_id, visit_focus_item_id) do update
        set rating = excluded.rating,
            is_na = excluded.is_na,
            na_reason = excluded.na_reason,
            comment = excluded.comment,
            scope_classification = excluded.scope_classification,
            issue_type_code = excluded.issue_type_code,
            urgent_hs_flag = excluded.urgent_hs_flag;
    end loop;
  end if;

  update public.reviews set version_no = version_no + 1 where id = p_review_id
    returning version_no into v_new_version;
  return v_new_version;
end $function$;

-- Patched rpc_submit_review: focus completeness + constraint-sourced urgent action.
CREATE OR REPLACE FUNCTION public.rpc_submit_review(p_review_id uuid, p_expected_version bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_version bigint; v_status public.review_status;
  v_visit_status public.cleaning_visit_status; v_reviewer uuid;
  v_urgent_flag boolean; v_urgent_constraint uuid;
  v_missing int; v_missing_focus int;
  v_constraint_label text;
  rls record; fis record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select cleaning_visit_id, status, version_no, reviewer_id, urgent_hs_flag, urgent_source_constraint_id
    into v_visit, v_status, v_version, v_reviewer, v_urgent_flag, v_urgent_constraint
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

  -- Rating-line completeness.
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

  -- Focus-item completeness (mirrors rating-line check; only over actual visit_focus_items).
  select count(*) into v_missing_focus
    from public.visit_focus_items vfi
    left join public.focus_item_scores fis
      on fis.review_id = p_review_id and fis.visit_focus_item_id = vfi.id
   where vfi.cleaning_visit_id = v_visit
     and (fis.id is null
          or (fis.is_na = false and fis.rating is null)
          or (fis.is_na = true  and coalesce(fis.na_reason,'') = ''));
  if v_missing_focus > 0 then
    raise exception 'review_incomplete_focus'
      using detail = format('% focus items need a 1-5 score or N/A with reason', v_missing_focus);
  end if;

  -- Urgent flag must reference at least one source (line, focus, or constraint).
  if coalesce(v_urgent_flag, false) then
    if v_urgent_constraint is null
       and not exists (select 1 from public.review_line_scores
                        where review_id = p_review_id and urgent_hs_flag and is_failure)
       and not exists (select 1 from public.focus_item_scores
                        where review_id = p_review_id and urgent_hs_flag and is_failure) then
      raise exception 'urgent_hs_requires_source'
        using detail = 'urgent H&S flag needs a rating-line, focus-item or visit-constraint source';
    end if;
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

  -- Constraint-sourced urgent action.
  if coalesce(v_urgent_flag, false) and v_urgent_constraint is not null then
    select coalesce(ct.label, vc.constraint_type) into v_constraint_label
      from public.visit_constraints vc
      left join public.constraint_types ct on ct.code = vc.constraint_type
     where vc.id = v_urgent_constraint;
    insert into public.actions(
      site_id, cleaning_visit_id, title, description, scope_classification,
      priority, status, source_constraint_id, urgent_hs_flag, created_by)
    select v_site, v_visit,
           'Urgent H&S: ' || coalesce(v_constraint_label, 'constraint'),
           coalesce(vc.description, ''),
           'urgent_hs'::public.scope_classification,
           'urgent'::public.action_priority,
           'open', vc.id, true, v_uid
      from public.visit_constraints vc
     where vc.id = v_urgent_constraint
    on conflict do nothing;
  end if;

  update public.cleaning_visits
     set status = case when status = 'submitted_for_review' then 'reviewed' else status end,
         reviewed_at = case when status = 'submitted_for_review' then now() else reviewed_at end,
         version_no = version_no + 1
   where id = v_visit;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action)
    values (v_site, v_uid, 'review', p_review_id, 'submitted');
  return p_review_id;
end $function$;
