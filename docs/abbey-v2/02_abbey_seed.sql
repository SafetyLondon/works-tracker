-- =====================================================================
-- Abbey v2 cleaning model — SEED (idempotent, forward-only, additive)
-- =====================================================================
-- STAGED, NOT YET APPLIED. Moves into supabase/migrations/ on sign-off.
-- Runs AFTER 01_schema.sql. Idempotent: re-running changes nothing.
-- Uses code-based lookups; never hard-codes a live UUID.
--
-- CONFIRMED:   service days, areas, baseline structure, Friday 2-week / Sunday
--              4-week rotation shape, mirrors/vanity baseline (owner edit).
-- PLACEHOLDER: cubicle numbering/grouping, exact toilet names, accessible asset
--              names, exact open-shower count (assumed 8). Marked @UNCONFIRMED.
--              These are safe to refine later via "Other / not listed".
-- =====================================================================

-- ---------- task_families (global) ----------
insert into public.task_families(code, label, sort_order) values
  ('BASELINE_FLOOR',        'Baseline floor work',        10),
  ('CUBICLE_SHOWER_DETAIL', 'Cubicle / shower detail',    20),
  ('LIMESCALE_DESCALE',     'Limescale / descaling',      30),
  ('DRAINS_GRATES',         'Drains / grates',            40),
  ('FIXTURES_TOUCHPOINTS',  'Fixtures / touchpoints',     50),
  ('LOCKER_BENCH',          'Locker / bench detail',      60),
  ('VANITY_SPLASH',         'Vanity / splash zones',      70),
  ('CORRIDOR',              'Corridor / transition',      80),
  ('HIGH_IMPACT_REPEAT',    'High-impact repeat',         90),
  ('TOILETS',               'Toilets',                   100),
  ('GROUP_CHANGING',        'Group changing rooms',      110)
on conflict (code) do update set label = excluded.label, sort_order = excluded.sort_order;

-- ---------- areas ----------
insert into public.areas(site_id, code, name, display_order, is_out_of_scope)
select s.id, v.code, v.name, v.ord, v.oos
from public.sites s, (values
  -- Tuesday / spa
  ('SPA_RECEPTION',     'Spa reception / entrance',            10, false),
  ('SPA_FOYER',         'Spa foyer / relaxation area',         20, false),
  ('SPA_POOL_SURROUND', 'Spa pool-side floor / drains',        30, false),
  ('SPA_SHOWER',        'Spa shower area',                     40, false),
  ('SPA_SAUNA',         'Sauna (interior)',                    50, true),
  ('SPA_STEAM',         'Steam room (interior)',               60, true),
  ('SPA_POOL_BODY',     'Spa pool / jacuzzi water body',       70, true),
  -- Friday / dry-side + foyer
  ('FOYER_AFTER_GATES', 'Centre foyer after barrier gates',   110, false),
  ('DRY_MALE',          'Dry-side male changing room',        120, false),
  ('DRY_FEMALE',        'Dry-side female changing room',      130, false),
  ('MAIN_RECEPTION_PRE_GATES','Main reception before gates',  140, true),
  -- Sunday / wet changing village
  ('WET_CUBICLES',      'Wet changing village cubicles',      210, false),
  ('WET_OPEN_SHOWERS',  'Open showers',                       220, false),
  ('WET_MALE_TOILET',   'Wet-side male toilet',               230, false),
  ('WET_FEMALE_TOILET', 'Wet-side female toilet',             240, false),
  ('WET_ACCESS_TOILET', 'Wet-side accessible toilet',         250, false),
  ('WET_CORRIDOR',      'Wet changing village corridor',      260, false),
  ('GROUP_ROOM_1',      'Group changing room 1',              270, false),
  ('GROUP_ROOM_2',      'Group changing room 2',              280, false),
  ('WET_ACCESSIBLE',    'Wet-side accessible changing/shower',290, false),
  -- Global out-of-scope
  ('POOLSIDE_SURROUND', 'Poolside surround',                  900, true),
  ('GYM_UPSTAIRS',      'Upstairs / gym areas',               910, true)
) as v(code, name, ord, oos)
where s.code = 'ABBEY_LC'
on conflict (site_id, code) do update
  set name = excluded.name, display_order = excluded.display_order,
      is_out_of_scope = excluded.is_out_of_scope;

-- ---------- sub_areas ----------
-- Open showers 1-8 (validated). @UNCONFIRMED exact count.
insert into public.sub_areas(area_id, code, name, display_order)
select a.id, 'OPEN_SHOWER_' || n, 'Open shower ' || n, n
from public.areas a
join public.sites s on s.id = a.site_id and s.code = 'ABBEY_LC'
cross join generate_series(1, 8) as n
where a.code = 'WET_OPEN_SHOWERS'
on conflict (area_id, code) do update set name = excluded.name;

-- Wet cubicles 1-6 (@UNCONFIRMED numbering/grouping — placeholder).
insert into public.sub_areas(area_id, code, name, display_order)
select a.id, 'CUBICLE_' || n, 'Cubicle ' || n || ' (unconfirmed)', n
from public.areas a
join public.sites s on s.id = a.site_id and s.code = 'ABBEY_LC'
cross join generate_series(1, 6) as n
where a.code = 'WET_CUBICLES'
on conflict (area_id, code) do nothing;

-- ---------- task_templates ----------
-- task_kind is an advisory default; whether a task is baseline or rotation for a
-- given visit is decided by where it is wired (schedule_baseline_tasks vs
-- rotation_segment_tasks), NOT by this column.
insert into public.task_templates(site_id, code, name, task_family_code, task_kind,
  requires_supervisor_verification, acceptance_criteria, display_order)
select s.id, v.code, v.name, v.fam, v.kind::public.cleaning_task_kind, v.verify, v.accept, v.ord
from public.sites s, (values
  ('TT_FLOOR_BUFFER',     'Floor buffer',                    'BASELINE_FLOOR',        'baseline', false, null, 10),
  ('TT_JET_WASH',         'Jet wash floor',                  'BASELINE_FLOOR',        'baseline', false, null, 20),
  ('TT_MOP_WIPE',         'Mop / wipe floor',                'BASELINE_FLOOR',        'baseline', false, null, 30),
  ('TT_DRY_SAFE',         'Dry floor / leave safe',          'BASELINE_FLOOR',        'baseline', true,  'Floor left dry and safe; no slip risk; signage handled.', 40),
  ('TT_FLOOR_EDGES',      'Clean floor edges / corners',     'BASELINE_FLOOR',        'baseline', false, null, 50),
  ('TT_FIXTURE_WIPE',     'Fixture / signage wipe-down',     'FIXTURES_TOUCHPOINTS',  'baseline', false, null, 60),
  ('TT_UNDER_FIXTURES',   'Detail under fixtures/chairs/extinguishers','FIXTURES_TOUCHPOINTS','baseline', false, null, 70),
  ('TT_MIRRORS_VANITY',   'Mirrors / vanity area clean',     'VANITY_SPLASH',         'baseline', false, null, 80),
  ('TT_DRAIN_GRATE',      'Clean drain grate',               'DRAINS_GRATES',         'baseline', false, null, 90),
  ('TT_TOILET_CLEAN',     'Toilet area clean',               'TOILETS',               'baseline', false, null, 100),
  ('TT_OPEN_SHOWER',      'Open shower clean',               'CUBICLE_SHOWER_DETAIL', 'baseline', false, null, 110),
  ('TT_CUBICLE_PRESENT',  'Cubicle area presentation',       'CUBICLE_SHOWER_DETAIL', 'baseline', false, null, 120),
  ('TT_GROUP_ROOM',       'Group changing room clean',       'GROUP_CHANGING',        'baseline', false, null, 130),
  -- rotation / intensive
  ('TT_DESCALE_SHOWER',   'Descale shower area',             'LIMESCALE_DESCALE',     'rotation', true,  'Limescale removed from walls/fittings/floor to spec.', 200),
  ('TT_LIMESCALE_FOCUS',  'Limescale focus',                 'LIMESCALE_DESCALE',     'rotation', true,  null, 210),
  ('TT_DESCALE_DRAINS',   'Descale drains / grates',         'DRAINS_GRATES',         'rotation', true,  null, 220),
  ('TT_CUBICLE_DEEP',     'Shower / cubicle deep clean',     'CUBICLE_SHOWER_DETAIL', 'rotation', false, null, 230),
  ('TT_CUBICLE_BASE',     'Cubicle base detail',             'CUBICLE_SHOWER_DETAIL', 'rotation', false, null, 240),
  ('TT_VANITY_DEEP',      'Vanity / splash-zone deep detail','VANITY_SPLASH',         'rotation', false, null, 250),
  ('TT_LOCKER_BASE',      'Locker base detail',              'LOCKER_BENCH',          'rotation', false, null, 260),
  ('TT_BENCH_DETAIL',     'Bench detail clean',              'LOCKER_BENCH',          'rotation', false, null, 270),
  ('TT_ENTRANCE_EDGE',    'Entrance / floor edge detail',    'HIGH_IMPACT_REPEAT',    'rotation', false, null, 280),
  ('TT_HIGH_IMPACT',      'High-impact repeat clean',        'HIGH_IMPACT_REPEAT',    'rotation', false, null, 290)
) as v(code, name, fam, kind, verify, accept, ord)
where s.code = 'ABBEY_LC'
on conflict (site_id, code) do update
  set name = excluded.name, task_family_code = excluded.task_family_code,
      task_kind = excluded.task_kind,
      requires_supervisor_verification = excluded.requires_supervisor_verification,
      acceptance_criteria = excluded.acceptance_criteria;

-- ---------- service_schedules (bridged to legacy visit_templates) ----------
insert into public.service_schedules(site_id, code, name, expected_weekday,
  planned_duration_hours, legacy_visit_template_id, display_summary)
select s.id, v.code, v.name, v.wd, v.hours,
       (select vt.id from public.visit_templates vt where vt.site_id = s.id and vt.code = v.legacy),
       v.summary
from public.sites s, (values
  ('SS_TUE', 'Abbey Tuesday Spa Clean',                 2, 6.0, 'TUE_SPA',     'Spa deep clean'),
  ('SS_FRI', 'Abbey Friday Dry-Side & Foyer Clean',     5, 5.0, 'FRI_DRYSIDE', 'Foyer after gates + dry-side male/female'),
  ('SS_SUN', 'Abbey Sunday Wet Changing Village Clean', 0, 6.0, 'SUN_WETSIDE', 'Wet changing village')
) as v(code, name, wd, hours, legacy, summary)
where s.code = 'ABBEY_LC'
on conflict (site_id, code) do update
  set name = excluded.name, expected_weekday = excluded.expected_weekday,
      planned_duration_hours = excluded.planned_duration_hours,
      legacy_visit_template_id = excluded.legacy_visit_template_id,
      display_summary = excluded.display_summary;

-- ---------- helper: wire a baseline task by codes ----------
-- (inline; repeated INSERT...SELECT keyed on stable codes, idempotent)

-- TUESDAY baseline
insert into public.schedule_baseline_tasks(service_schedule_id, task_template_id, area_id, display_order)
select ss.id, tt.id, ar.id, x.ord
from public.sites s
join public.service_schedules ss on ss.site_id = s.id and ss.code = 'SS_TUE'
join (values
  ('TT_FLOOR_BUFFER','SPA_FOYER',10),('TT_JET_WASH','SPA_POOL_SURROUND',20),
  ('TT_DRAIN_GRATE','SPA_POOL_SURROUND',30),('TT_DESCALE_SHOWER','SPA_SHOWER',40),
  ('TT_MOP_WIPE','SPA_RECEPTION',50),('TT_FLOOR_EDGES','SPA_RECEPTION',60),
  ('TT_FIXTURE_WIPE','SPA_FOYER',70),('TT_DRY_SAFE','SPA_FOYER',80)
) as x(tt_code, area_code, ord) on true
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
join public.areas ar on ar.site_id = s.id and ar.code = x.area_code
where s.code = 'ABBEY_LC'
on conflict (service_schedule_id, task_template_id, area_id, sub_area_id) do nothing;

-- FRIDAY baseline (incl. mirrors/vanity for BOTH male and female — owner edit)
insert into public.schedule_baseline_tasks(service_schedule_id, task_template_id, area_id, display_order)
select ss.id, tt.id, ar.id, x.ord
from public.sites s
join public.service_schedules ss on ss.site_id = s.id and ss.code = 'SS_FRI'
join (values
  -- Foyer after gates
  ('TT_MOP_WIPE','FOYER_AFTER_GATES',10),('TT_UNDER_FIXTURES','FOYER_AFTER_GATES',20),
  ('TT_FIXTURE_WIPE','FOYER_AFTER_GATES',30),
  -- Dry-side male
  ('TT_FLOOR_BUFFER','DRY_MALE',40),('TT_JET_WASH','DRY_MALE',50),
  ('TT_DRY_SAFE','DRY_MALE',60),('TT_MIRRORS_VANITY','DRY_MALE',70),
  -- Dry-side female
  ('TT_FLOOR_BUFFER','DRY_FEMALE',80),('TT_JET_WASH','DRY_FEMALE',90),
  ('TT_DRY_SAFE','DRY_FEMALE',100),('TT_MIRRORS_VANITY','DRY_FEMALE',110)
) as x(tt_code, area_code, ord) on true
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
join public.areas ar on ar.site_id = s.id and ar.code = x.area_code
where s.code = 'ABBEY_LC'
on conflict (service_schedule_id, task_template_id, area_id, sub_area_id) do nothing;

-- SUNDAY baseline
insert into public.schedule_baseline_tasks(service_schedule_id, task_template_id, area_id, display_order)
select ss.id, tt.id, ar.id, x.ord
from public.sites s
join public.service_schedules ss on ss.site_id = s.id and ss.code = 'SS_SUN'
join (values
  ('TT_FLOOR_BUFFER','WET_CUBICLES',10),('TT_JET_WASH','WET_CUBICLES',20),
  ('TT_DRY_SAFE','WET_CUBICLES',30),('TT_OPEN_SHOWER','WET_OPEN_SHOWERS',40),
  ('TT_TOILET_CLEAN','WET_MALE_TOILET',50),('TT_TOILET_CLEAN','WET_FEMALE_TOILET',60),
  ('TT_TOILET_CLEAN','WET_ACCESS_TOILET',70),('TT_MOP_WIPE','WET_CORRIDOR',80),
  ('TT_DRAIN_GRATE','WET_CORRIDOR',90),('TT_CUBICLE_PRESENT','WET_CUBICLES',100),
  ('TT_GROUP_ROOM','GROUP_ROOM_1',110),('TT_GROUP_ROOM','GROUP_ROOM_2',120)
) as x(tt_code, area_code, ord) on true
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
join public.areas ar on ar.site_id = s.id and ar.code = x.area_code
where s.code = 'ABBEY_LC'
on conflict (service_schedule_id, task_template_id, area_id, sub_area_id) do nothing;

-- ---------- rotation anchors + segments ----------
-- Friday: 2-week male/female alternation. anchor_start_date NULL (admin sets).
insert into public.rotation_anchors(site_id, service_schedule_id, code, name, cycle_length)
select s.id, ss.id, 'RA_FRI_DRY', 'Abbey Friday Dry-Side Intensive Detail Rotation', 2
from public.sites s
join public.service_schedules ss on ss.site_id = s.id and ss.code = 'SS_FRI'
where s.code = 'ABBEY_LC'
on conflict (site_id, code) do update set name = excluded.name, cycle_length = excluded.cycle_length;

-- Sunday: 4-week wet-village rotation. anchor_start_date NULL.
insert into public.rotation_anchors(site_id, service_schedule_id, code, name, cycle_length)
select s.id, ss.id, 'RA_SUN_WET', 'Abbey Sunday Wet Changing Village Rotation', 4
from public.sites s
join public.service_schedules ss on ss.site_id = s.id and ss.code = 'SS_SUN'
where s.code = 'ABBEY_LC'
on conflict (site_id, code) do update set name = excluded.name, cycle_length = excluded.cycle_length;

insert into public.rotation_segments(rotation_anchor_id, position, title)
select ra.id, x.pos, x.title
from public.sites s
join public.rotation_anchors ra on ra.site_id = s.id and ra.code = 'RA_FRI_DRY'
join (values (1,'Dry-side male intensive detail'), (2,'Dry-side female intensive detail')) as x(pos,title) on true
where s.code = 'ABBEY_LC'
on conflict (rotation_anchor_id, position) do update set title = excluded.title;

insert into public.rotation_segments(rotation_anchor_id, position, title)
select ra.id, x.pos, x.title
from public.sites s
join public.rotation_anchors ra on ra.site_id = s.id and ra.code = 'RA_SUN_WET'
join (values
  (1,'Cubicles 1-2 + vanity/splash + entrance edges'),
  (2,'Cubicles 4-6 + cubicle bases + locker bases'),
  (3,'Accessible cubicles / accessible changing & shower'),
  (4,'High-impact repeat / worst limescale / problem areas')
) as x(pos,title) on true
where s.code = 'ABBEY_LC'
on conflict (rotation_anchor_id, position) do update set title = excluded.title;

-- ---------- rotation_segment_tasks ----------
-- Friday position 1 (male intensive) — area DRY_MALE
insert into public.rotation_segment_tasks(rotation_segment_id, task_template_id, area_id, display_order)
select seg.id, tt.id, ar.id, x.ord
from public.sites s
join public.rotation_anchors ra on ra.site_id = s.id and ra.code = 'RA_FRI_DRY'
join public.rotation_segments seg on seg.rotation_anchor_id = ra.id and seg.position = 1
join public.areas ar on ar.site_id = s.id and ar.code = 'DRY_MALE'
join (values
  ('TT_DESCALE_SHOWER',10),('TT_DESCALE_DRAINS',20),('TT_CUBICLE_DEEP',30),
  ('TT_VANITY_DEEP',40),('TT_LOCKER_BASE',50),('TT_BENCH_DETAIL',60),
  ('TT_ENTRANCE_EDGE',70),('TT_HIGH_IMPACT',80)
) as x(tt_code, ord) on true
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
where s.code = 'ABBEY_LC'
on conflict (rotation_segment_id, task_template_id, area_id, sub_area_id) do nothing;

-- Friday position 2 (female intensive) — area DRY_FEMALE
insert into public.rotation_segment_tasks(rotation_segment_id, task_template_id, area_id, display_order)
select seg.id, tt.id, ar.id, x.ord
from public.sites s
join public.rotation_anchors ra on ra.site_id = s.id and ra.code = 'RA_FRI_DRY'
join public.rotation_segments seg on seg.rotation_anchor_id = ra.id and seg.position = 2
join public.areas ar on ar.site_id = s.id and ar.code = 'DRY_FEMALE'
join (values
  ('TT_DESCALE_SHOWER',10),('TT_DESCALE_DRAINS',20),('TT_CUBICLE_DEEP',30),
  ('TT_VANITY_DEEP',40),('TT_LOCKER_BASE',50),('TT_BENCH_DETAIL',60),
  ('TT_ENTRANCE_EDGE',70),('TT_HIGH_IMPACT',80)
) as x(tt_code, ord) on true
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
where s.code = 'ABBEY_LC'
on conflict (rotation_segment_id, task_template_id, area_id, sub_area_id) do nothing;

-- Sunday positions 1-4 — area WET_CUBICLES / WET_ACCESSIBLE (sub-areas @UNCONFIRMED)
insert into public.rotation_segment_tasks(rotation_segment_id, task_template_id, area_id, display_order)
select seg.id, tt.id, ar.id, x.ord
from public.sites s
join public.rotation_anchors ra on ra.site_id = s.id and ra.code = 'RA_SUN_WET'
join public.rotation_segments seg on seg.rotation_anchor_id = ra.id and seg.position = x.pos
join public.areas ar on ar.site_id = s.id and ar.code = x.area_code
join public.task_templates tt on tt.site_id = s.id and tt.code = x.tt_code
join (values
  (1,'WET_CUBICLES','TT_CUBICLE_DEEP',10), (1,'WET_CUBICLES','TT_VANITY_DEEP',20),
  (1,'WET_CUBICLES','TT_ENTRANCE_EDGE',30),
  (2,'WET_CUBICLES','TT_CUBICLE_BASE',10), (2,'WET_CUBICLES','TT_LOCKER_BASE',20),
  (3,'WET_ACCESSIBLE','TT_CUBICLE_DEEP',10),(3,'WET_ACCESSIBLE','TT_LIMESCALE_FOCUS',20),
  (4,'WET_CUBICLES','TT_HIGH_IMPACT',10), (4,'WET_CUBICLES','TT_DESCALE_DRAINS',20)
) as x(pos, area_code, tt_code, ord) on true
where s.code = 'ABBEY_LC'
on conflict (rotation_segment_id, task_template_id, area_id, sub_area_id) do nothing;

-- ---------- embedded assertions ----------
do $assert$
declare v_site uuid; n int;
begin
  select id into v_site from public.sites where code = 'ABBEY_LC';
  if v_site is null then raise exception 'Abbey site missing — run legacy Abbey seed first'; end if;

  select count(*) into n from public.service_schedules where site_id = v_site;
  if n <> 3 then raise exception 'expected 3 service_schedules, got %', n; end if;

  select count(*) into n from public.rotation_anchors where site_id = v_site;
  if n <> 2 then raise exception 'expected 2 rotation_anchors, got %', n; end if;

  select count(*) into n from public.rotation_segments seg
    join public.rotation_anchors ra on ra.id = seg.rotation_anchor_id
   where ra.site_id = v_site and ra.code = 'RA_SUN_WET';
  if n <> 4 then raise exception 'expected 4 Sunday segments, got %', n; end if;

  -- mirrors/vanity present as baseline for BOTH dry-side rooms
  select count(*) into n
    from public.schedule_baseline_tasks sbt
    join public.service_schedules ss on ss.id = sbt.service_schedule_id and ss.code = 'SS_FRI'
    join public.task_templates tt on tt.id = sbt.task_template_id and tt.code = 'TT_MIRRORS_VANITY'
    join public.areas ar on ar.id = sbt.area_id
   where ss.site_id = v_site and ar.code in ('DRY_MALE','DRY_FEMALE');
  if n <> 2 then raise exception 'expected mirrors/vanity baseline for male+female, got %', n; end if;

  raise notice 'Abbey v2 seed assertions passed (schedules=3, anchors=2, sun_segments=4, mirrors/vanity=2)';
end $assert$;
