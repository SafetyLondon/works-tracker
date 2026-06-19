
-- =====================================================================
-- A4 pre-flight: refuse to drop legacy columns if scores exist
-- =====================================================================

do $$
declare n_rls int; n_fis int;
begin
  select count(*) into n_rls from public.review_line_scores;
  select count(*) into n_fis from public.focus_item_scores;
  if n_rls > 0 or n_fis > 0 then
    raise exception
      'rating-model migration aborted: % review_line_scores and % focus_item_scores rows exist; deliberate legacy conversion required',
      n_rls, n_fis;
  end if;
end $$;

-- =====================================================================
-- Drop existing dependent objects
-- =====================================================================

drop function if exists public.rpc_save_review_draft(uuid, bigint, jsonb);
drop function if exists public.rpc_submit_review(uuid, bigint);
drop trigger if exists trg_rls_immutable on public.review_line_scores;
drop trigger if exists trg_fis_immutable on public.focus_item_scores;

-- =====================================================================
-- A4: 1–5 + N/A rating model
-- =====================================================================

alter table public.review_line_scores
  drop constraint if exists review_line_scores_rating_band_check,
  drop constraint if exists review_line_scores_score_check,
  drop column if exists score,
  drop column if exists rating_band,
  drop column if exists is_failure;

alter table public.review_line_scores
  add column rating smallint,
  add column is_na boolean not null default false,
  add column na_reason text,
  add constraint rls_rating_range_chk check (rating is null or (rating between 1 and 5)),
  add constraint rls_rating_or_na_chk check (
    (is_na = true and rating is null and coalesce(na_reason,'') <> '')
    or (is_na = false and rating is not null)
  ),
  add constraint rls_comment_on_low_rating_chk check (
    rating is null or rating > 2 or coalesce(comment,'') <> ''
  );

alter table public.review_line_scores
  add column rating_band_display text generated always as (
    case when is_na then 'na'
         when rating is null then null
         when rating <= 2 then 'red'
         when rating = 3 then 'amber'
         else 'green' end
  ) stored,
  add column is_failure boolean generated always as (
    rating is not null and rating <= 2
  ) stored;

alter table public.focus_item_scores
  drop constraint if exists focus_item_scores_rating_band_check,
  drop column if exists rating_band,
  drop column if exists is_failure;

alter table public.focus_item_scores
  add column rating smallint,
  add column is_na boolean not null default false,
  add column na_reason text,
  add constraint fis_rating_range_chk check (rating is null or (rating between 1 and 5)),
  add constraint fis_rating_or_na_chk check (
    (is_na = true and rating is null and coalesce(na_reason,'') <> '')
    or (is_na = false and rating is not null)
  ),
  add constraint fis_comment_on_low_rating_chk check (
    rating is null or rating > 2 or coalesce(comment,'') <> ''
  );

alter table public.focus_item_scores
  add column rating_band_display text generated always as (
    case when is_na then 'na'
         when rating is null then null
         when rating <= 2 then 'red'
         when rating = 3 then 'amber'
         else 'green' end
  ) stored,
  add column is_failure boolean generated always as (
    rating is not null and rating <= 2
  ) stored;

-- =====================================================================
-- A5: composite visit integrity on score tables
-- =====================================================================

alter table public.review_line_scores add column cleaning_visit_id uuid;
update public.review_line_scores rls
   set cleaning_visit_id = r.cleaning_visit_id
  from public.reviews r where r.id = rls.review_id;
alter table public.review_line_scores alter column cleaning_visit_id set not null;

alter table public.focus_item_scores add column cleaning_visit_id uuid;
update public.focus_item_scores fis
   set cleaning_visit_id = r.cleaning_visit_id
  from public.reviews r where r.id = fis.review_id;
alter table public.focus_item_scores alter column cleaning_visit_id set not null;

-- Parent composite uniques needed as FK targets
alter table public.reviews
  add constraint reviews_id_visit_uk unique (id, cleaning_visit_id);
alter table public.visit_rating_lines
  add constraint vrl_id_visit_uk unique (id, cleaning_visit_id);
alter table public.visit_focus_items
  add constraint vfi_id_visit_uk unique (id, cleaning_visit_id);

-- Composite FKs (drop original single-column FKs where they duplicate)
alter table public.review_line_scores
  drop constraint review_line_scores_review_id_fkey,
  drop constraint review_line_scores_visit_rating_line_id_fkey;
alter table public.review_line_scores
  add constraint rls_review_visit_fk
    foreign key (review_id, cleaning_visit_id)
    references public.reviews(id, cleaning_visit_id) on delete restrict,
  add constraint rls_rating_line_visit_fk
    foreign key (visit_rating_line_id, cleaning_visit_id)
    references public.visit_rating_lines(id, cleaning_visit_id) on delete restrict;

alter table public.focus_item_scores
  drop constraint focus_item_scores_review_id_fkey,
  drop constraint focus_item_scores_visit_focus_item_id_fkey;
alter table public.focus_item_scores
  add constraint fis_review_visit_fk
    foreign key (review_id, cleaning_visit_id)
    references public.reviews(id, cleaning_visit_id) on delete restrict,
  add constraint fis_focus_item_visit_fk
    foreign key (visit_focus_item_id, cleaning_visit_id)
    references public.visit_focus_items(id, cleaning_visit_id) on delete restrict;

-- Composite FK for actions(cleaning_visit_id, site_id)
alter table public.actions
  drop constraint actions_cleaning_visit_id_fkey;
alter table public.actions
  add constraint actions_visit_site_fk
    foreign key (cleaning_visit_id, site_id)
    references public.cleaning_visits(id, site_id) on delete restrict;

-- Restore immutability triggers
create trigger trg_rls_immutable
  before insert or update or delete on public.review_line_scores
  for each row execute function public.tms_protect_review_children();
create trigger trg_fis_immutable
  before insert or update or delete on public.focus_item_scores
  for each row execute function public.tms_protect_review_children();

-- =====================================================================
-- Rewrite score-write RPCs against the new shape
-- =====================================================================

create or replace function public.rpc_save_review_draft(
  p_review_id uuid, p_expected_version bigint, p_payload jsonb
) returns bigint
  language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_status public.review_status; v_version bigint; v_reviewer uuid;
  v_new_version bigint;
  r jsonb;
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
end $$;

create or replace function public.rpc_submit_review(
  p_review_id uuid, p_expected_version bigint
) returns uuid
  language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_visit uuid; v_site uuid; v_version bigint; v_status public.review_status;
  v_visit_status public.cleaning_visit_status; v_reviewer uuid;
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

  -- Write snapshots into score rows (historic immutability of meaning)
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

  -- Auto-actions for failures (rating <= 2)
  for rls in
    select * from public.review_line_scores
     where review_id = p_review_id and is_failure
  loop
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
  for fis in
    select * from public.focus_item_scores
     where review_id = p_review_id and is_failure
  loop
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
end $$;

revoke all on function public.rpc_save_review_draft(uuid,bigint,jsonb) from public;
revoke all on function public.rpc_submit_review(uuid,bigint) from public;
grant execute on function public.rpc_save_review_draft(uuid,bigint,jsonb) to authenticated;
grant execute on function public.rpc_submit_review(uuid,bigint) to authenticated;
