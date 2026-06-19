-- Slice C: idempotent reproducible seed of the live, approved Abbey Leisure Centre configuration.
-- Forward-only. Safe to re-run. Code-based lookups; no hard-coded UUIDs; never deletes live rows.
-- Live-vs-plan conflicts are recorded in IMPLEMENTATION_REPORT.md.

------------------------------------------------------------------------------
-- 1. Site
------------------------------------------------------------------------------
INSERT INTO public.sites (code, name)
VALUES ('ABBEY_LC', 'Abbey Leisure Centre')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name;

------------------------------------------------------------------------------
-- 2. Visit templates
------------------------------------------------------------------------------
WITH s AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC')
INSERT INTO public.visit_templates (site_id, code, name, expected_weekday, display_summary)
SELECT s.id, v.code, v.name, v.expected_weekday, v.display_summary
  FROM s, (VALUES
    ('TUE_SPA',     'Tuesday — Spa Deep Clean',    2, 'Spa areas: pool surrounds, sauna/steam, changing, treatment rooms'),
    ('FRI_DRYSIDE', 'Friday — Dryside Deep Clean', 5, 'Dryside: gym, studios, reception, corridors, café, public WCs'),
    ('SUN_WETSIDE', 'Sunday — Wetside Deep Clean', 0, 'Wetside: pool hall, wet changing, showers, splash areas')
  ) AS v(code, name, expected_weekday, display_summary)
ON CONFLICT (site_id, code) DO UPDATE
   SET name = EXCLUDED.name,
       expected_weekday = EXCLUDED.expected_weekday,
       display_summary  = EXCLUDED.display_summary;

------------------------------------------------------------------------------
-- 3. Template scope items
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     tpl  AS (SELECT id, code FROM public.visit_templates WHERE site_id = (SELECT id FROM site))
INSERT INTO public.template_scope_items (visit_template_id, item_type, code, label, display_order)
SELECT tpl.id, x.item_type, x.code, x.label, x.display_order
  FROM tpl JOIN (VALUES
    ('TUE_SPA','primary_area','PRIMARY_AREA_01','Spa pool surround & approach',10),
    ('TUE_SPA','primary_area','PRIMARY_AREA_02','Sauna and steam rooms',20),
    ('TUE_SPA','primary_area','PRIMARY_AREA_03','Spa changing rooms',30),
    ('TUE_SPA','primary_area','PRIMARY_AREA_04','Treatment rooms',40),
    ('TUE_SPA','primary_area','PRIMARY_AREA_05','Spa reception & corridor',50),
    ('TUE_SPA','primary_area','PRIMARY_AREA_06','Spa WCs',60),
    ('TUE_SPA','base_task','BASE_TASK_01','Detail-clean sauna and steam room benches, walls, glass',10),
    ('TUE_SPA','base_task','BASE_TASK_02','Descale spa showers and screens',20),
    ('TUE_SPA','base_task','BASE_TASK_03','Detail-clean spa lockers and benches',30),
    ('TUE_SPA','base_task','BASE_TASK_04','Mop and disinfect spa wet floors',40),
    ('TUE_SPA','base_task','BASE_TASK_05','Clean treatment rooms ready for therapists',50),
    ('TUE_SPA','base_task','BASE_TASK_06','Clean spa reception desk and customer touch points',60),
    ('TUE_SPA','secondary_maintenance','SECONDARY_MAINTENANCE_01','Report any grout or sealant issues in spa',10),
    ('TUE_SPA','secondary_maintenance','SECONDARY_MAINTENANCE_02','Report any sauna stone / heater concerns',20),
    ('TUE_SPA','limitation','LIMITATION_01','Treatment rooms inaccessible while in use by therapists',10),
    ('TUE_SPA','limitation','LIMITATION_02','Sauna interior requires power-off and cool-down',20),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_01','Gym floor',10),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_02','Studios',20),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_03','Reception & lobby',30),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_04','Public corridors & lift',40),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_05','Café',50),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_06','Dryside changing',60),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_07','Public WCs (dryside)',70),
    ('FRI_DRYSIDE','primary_area','PRIMARY_AREA_08','Bin areas & external approach',80),
    ('FRI_DRYSIDE','base_task','BASE_TASK_01','Detail-clean all gym touch points and equipment frames',10),
    ('FRI_DRYSIDE','base_task','BASE_TASK_02','Vacuum and mop gym matting and floor edges',20),
    ('FRI_DRYSIDE','base_task','BASE_TASK_03','Mop studio floors and clean mirrors',30),
    ('FRI_DRYSIDE','base_task','BASE_TASK_04','Clean reception desk and queue rail',40),
    ('FRI_DRYSIDE','base_task','BASE_TASK_05','Detail-clean lift interior',50),
    ('FRI_DRYSIDE','base_task','BASE_TASK_06','Clean café tables, chairs and condiment stations',60),
    ('FRI_DRYSIDE','base_task','BASE_TASK_07','Detail-clean dryside lockers and benches',70),
    ('FRI_DRYSIDE','base_task','BASE_TASK_08','Detail-clean public WCs (dryside)',80),
    ('FRI_DRYSIDE','base_task','BASE_TASK_09','Empty and clean external bin area',90),
    ('FRI_DRYSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_01','Report damaged gym equipment to maintenance',10),
    ('FRI_DRYSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_02','Report lighting outages along corridor',20),
    ('FRI_DRYSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_03','Report any locker damage',30),
    ('FRI_DRYSIDE','limitation','LIMITATION_01','Studios in use by classes may be inaccessible',10),
    ('FRI_DRYSIDE','limitation','LIMITATION_02','Reception remains live during clean',20),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_01','Pool hall floor & surround',10),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_02','Pool hall walls & glazing',20),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_03','Wetside changing',30),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_04','Wetside showers',40),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_05','Wetside WCs',50),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_06','Splash zone / family changing',60),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_07','Drains, gullies & plant-room approach',70),
    ('SUN_WETSIDE','primary_area','PRIMARY_AREA_08','Bin areas (wetside)',80),
    ('SUN_WETSIDE','base_task','BASE_TASK_01','Mop and disinfect pool surround tile',10),
    ('SUN_WETSIDE','base_task','BASE_TASK_02','Descale showers and screens',20),
    ('SUN_WETSIDE','base_task','BASE_TASK_03','Detail-clean wetside lockers and benches',30),
    ('SUN_WETSIDE','base_task','BASE_TASK_04','Clean wetside WCs',40),
    ('SUN_WETSIDE','base_task','BASE_TASK_05','Lift, clean and reseat accessible drains/gullies',50),
    ('SUN_WETSIDE','base_task','BASE_TASK_06','Clean splash zone and family changing',60),
    ('SUN_WETSIDE','base_task','BASE_TASK_07','Empty and clean wetside bin area',70),
    ('SUN_WETSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_01','Report grout/sealant defects in pool hall',10),
    ('SUN_WETSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_02','Report damaged or missing drain covers',20),
    ('SUN_WETSIDE','secondary_maintenance','SECONDARY_MAINTENANCE_03','Report tile damage',30),
    ('SUN_WETSIDE','limitation','LIMITATION_01','Pool hall remains live during early-morning swim — coordinate access',10),
    ('SUN_WETSIDE','limitation','LIMITATION_02','Plant-room interior is OUT OF SCOPE for cleaning',20)
  ) AS x(tpl_code, item_type, code, label, display_order)
  ON tpl.code = x.tpl_code
ON CONFLICT (visit_template_id, code) DO UPDATE
   SET item_type = EXCLUDED.item_type,
       label = EXCLUDED.label,
       display_order = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 4. Template rating lines (exact approved wording)
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     tpl  AS (SELECT id, code FROM public.visit_templates WHERE site_id = (SELECT id FROM site))
INSERT INTO public.template_rating_lines (visit_template_id, code, label, description, display_order)
SELECT tpl.id, x.code, x.label, x.description, x.display_order
  FROM tpl JOIN (VALUES
    ('TUE_SPA','LINE_01','Sauna & steam room interior cleanliness','Benches, walls, floor, glass, controls',10),
    ('TUE_SPA','LINE_02','Spa changing rooms — lockers, benches, mirrors','Detail-clean lockers/benches/mirrors',20),
    ('TUE_SPA','LINE_03','Spa wet floors & drains','Pool surround tile and drains',30),
    ('TUE_SPA','LINE_04','Spa showers — heads, screens, grout','Limescale, grout, screens',40),
    ('TUE_SPA','LINE_05','Treatment rooms — surfaces & linens area','Cleared and detail-cleaned',50),
    ('TUE_SPA','LINE_06','Spa reception & corridor approach','Floor, surfaces, glass',60),
    ('TUE_SPA','LINE_07','Spa WCs — pans, basins, dispensers','Pans, basins, dispensers, mirrors',70),
    ('FRI_DRYSIDE','LINE_01','Gym equipment surfaces & touch points','Detail-clean grips, screens, frames',10),
    ('FRI_DRYSIDE','LINE_02','Gym floor & matting','Floor edges, under equipment',20),
    ('FRI_DRYSIDE','LINE_03','Studio floors & mirrors','Sprung floor, mirrors, ballet barres',30),
    ('FRI_DRYSIDE','LINE_04','Reception desk & customer-facing surfaces','Desk, screens, queue rail, signage',40),
    ('FRI_DRYSIDE','LINE_05','Public corridor floors','Edges, transitions, lift threshold',50),
    ('FRI_DRYSIDE','LINE_06','Lift interior — surfaces & floor','Buttons, mirror, floor, ceiling vents',60),
    ('FRI_DRYSIDE','LINE_07','Café tables, chairs & condiment stations','Underside of tables, chair legs',70),
    ('FRI_DRYSIDE','LINE_08','Public WCs (dryside) — pans & basins','Pans, basins, dispensers, partitions',80),
    ('FRI_DRYSIDE','LINE_09','Dryside changing — lockers, benches, mirrors','Detail-clean lockers/benches',90),
    ('FRI_DRYSIDE','LINE_10','Glazing & internal doors','Glass, frames, push plates, handles',100),
    ('FRI_DRYSIDE','LINE_11','Bin areas & external approach','Bins emptied, area swept',110),
    ('SUN_WETSIDE','LINE_01','Pool hall floor & surround tile','Slip risk, drains, scum line',10),
    ('SUN_WETSIDE','LINE_02','Pool hall walls & glazing','Lower wall splashes, glass',20),
    ('SUN_WETSIDE','LINE_03','Wetside changing — lockers, benches, mirrors','Detail-clean lockers/benches/mirrors',30),
    ('SUN_WETSIDE','LINE_04','Wetside showers — heads, screens, grout','Limescale, grout discolouration',40),
    ('SUN_WETSIDE','LINE_05','Wetside WCs — pans, basins, dispensers','Pans, basins, dispensers',50),
    ('SUN_WETSIDE','LINE_06','Wet floor drains & gullies','Visible debris, smell',60),
    ('SUN_WETSIDE','LINE_07','Splash zone / family changing','Surfaces and floor',70),
    ('SUN_WETSIDE','LINE_08','Plant-room approach & door','Door, threshold, no spills',80),
    ('SUN_WETSIDE','LINE_09','Bin areas (wetside)','Emptied, area cleaned',90)
  ) AS x(tpl_code, code, label, description, display_order)
  ON tpl.code = x.tpl_code
ON CONFLICT (visit_template_id, code) DO UPDATE
   SET label = EXCLUDED.label,
       description = EXCLUDED.description,
       display_order = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 5. Focus categories
------------------------------------------------------------------------------
WITH s AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC')
INSERT INTO public.focus_categories (site_id, code, label, display_order)
SELECT s.id, c.code, c.label, c.display_order
  FROM s, (VALUES
    ('cubicle_detail',   'Cubicle / locker detail',  10),
    ('shower_detail',    'Shower & screen detail',   20),
    ('gym_detail',       'Gym / studio detail',      30),
    ('glazing_walls',    'Glazing & lower walls',    40),
    ('drains',           'Drains & gullies',         50),
    ('defects_priority', 'Highest-priority defects', 60)
  ) AS c(code, label, display_order)
ON CONFLICT (site_id, code) DO UPDATE
   SET label = EXCLUDED.label, display_order = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 6. Focus items (acceptance_standard left NULL to match live; see report)
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     tpl  AS (SELECT id, code FROM public.visit_templates WHERE site_id = (SELECT id FROM site)),
     cat  AS (SELECT id, code FROM public.focus_categories  WHERE site_id = (SELECT id FROM site))
INSERT INTO public.focus_items (site_id, visit_template_id, category_id, code, label, description, exact_location_required, display_order)
SELECT (SELECT id FROM site), tpl.id, cat.id, x.code, x.label, x.description, true, x.display_order
  FROM (VALUES
    ('FRI_DRYSIDE','cubicle_detail',  'FI_002','Male dryside — cubicle interior detail-clean',  'Interior surfaces, hooks, locks', 10),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_004','Male dryside — bench detail-clean',             'Underside, joints, fixings',      20),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_006','Male dryside — locker doors & vents',           'Vent slots, door edges',          30),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_007','Male dryside — mirror polish & frame',          'Frame and silicone',              40),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_010','Female dryside — cubicle interior detail-clean','Interior surfaces, hooks, locks', 50),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_012','Female dryside — bench detail-clean',           'Underside, joints, fixings',      60),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_013','Female dryside — locker doors & vents',         'Vent slots, door edges',          70),
    ('FRI_DRYSIDE','cubicle_detail',  'FI_015','Female dryside — mirror polish & frame',        'Frame and silicone',              80),
    ('FRI_DRYSIDE','gym_detail',      'FI_018','Gym — equipment frames & cables detail',        'Frame undersides, cable routing', 90),
    ('FRI_DRYSIDE','gym_detail',      'FI_020','Gym — mirror & glazing detail',                 'Frame and edge',                 100),
    ('FRI_DRYSIDE','gym_detail',      'FI_021','Studio — ballet barre & wall mirrors',          'Barre fixings, mirror edges',    110),
    ('FRI_DRYSIDE','gym_detail',      'FI_023','Studio — sprung floor edge detail',             'Edges and transitions',          120),
    ('FRI_DRYSIDE','defects_priority','FI_024','Address top defect from last 2 reviews',        'Highest-priority outstanding defect', 200),
    ('SUN_WETSIDE','cubicle_detail',  'FI_001','Male wetside — cubicle interior detail-clean',  'Interior surfaces, hooks',        10),
    ('SUN_WETSIDE','shower_detail',   'FI_003','Male wetside — shower screen & head',           'Limescale, screen edges',         20),
    ('SUN_WETSIDE','shower_detail',   'FI_005','Male wetside — shower grout detail',            'Vertical and horizontal grout',   30),
    ('SUN_WETSIDE','cubicle_detail',  'FI_008','Female wetside — cubicle interior detail-clean','Interior surfaces, hooks',        40),
    ('SUN_WETSIDE','shower_detail',   'FI_009','Female wetside — shower screen & head',         'Limescale, screen edges',         50),
    ('SUN_WETSIDE','shower_detail',   'FI_011','Female wetside — shower grout detail',          'Vertical and horizontal grout',   60),
    ('SUN_WETSIDE','glazing_walls',   'FI_014','Pool hall — lower wall splash line detail',     'From floor to ~1.5m',             70),
    ('SUN_WETSIDE','glazing_walls',   'FI_016','Pool hall — glazing detail',                    'Interior glazing and seals',      80),
    ('SUN_WETSIDE','glazing_walls',   'FI_017','Pool hall — wall tile scum line removal',       'Around water line',               90),
    ('SUN_WETSIDE','drains',          'FI_019','Drains & gullies — lift, clean and reseat',     'All accessible drains',          100),
    ('SUN_WETSIDE','drains',          'FI_022','Drains — odour trap flush',                     'All accessible traps',           110),
    ('SUN_WETSIDE','defects_priority','FI_025','Address top wetside defect',                    'Highest-priority outstanding wetside defect', 200)
  ) AS x(tpl_code, cat_code, code, label, description, display_order)
  JOIN tpl ON tpl.code = x.tpl_code
  JOIN cat ON cat.code = x.cat_code
ON CONFLICT (site_id, code) DO UPDATE
   SET visit_template_id = EXCLUDED.visit_template_id,
       category_id       = EXCLUDED.category_id,
       label             = EXCLUDED.label,
       description       = EXCLUDED.description,
       exact_location_required = EXCLUDED.exact_location_required,
       display_order     = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 7. Rotation programmes (Tuesday has none; anchors stay NULL)
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     tpl  AS (SELECT id, code FROM public.visit_templates WHERE site_id = (SELECT id FROM site))
INSERT INTO public.rotation_programmes (site_id, visit_template_id, code, name, cycle_length_weeks)
SELECT (SELECT id FROM site), tpl.id, x.code, x.name, 4
  FROM (VALUES
    ('FRI_DRYSIDE','FRI_ROT_4WK','Friday Dryside 4-Week Rotation'),
    ('SUN_WETSIDE','SUN_ROT_4WK','Sunday Wetside 4-Week Rotation')
  ) AS x(tpl_code, code, name)
  JOIN tpl ON tpl.code = x.tpl_code
ON CONFLICT (site_id, code) DO UPDATE
   SET visit_template_id  = EXCLUDED.visit_template_id,
       name               = EXCLUDED.name,
       cycle_length_weeks = EXCLUDED.cycle_length_weeks;
-- anchor_date intentionally NOT overwritten; rpc_set_rotation_anchor owns it.

------------------------------------------------------------------------------
-- 8. Rotation steps
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     prog AS (SELECT id, code FROM public.rotation_programmes WHERE site_id = (SELECT id FROM site))
INSERT INTO public.rotation_steps (rotation_programme_id, week_number, title, display_order)
SELECT prog.id, x.week_number, x.title, x.display_order
  FROM (VALUES
    ('FRI_ROT_4WK',1,'Week 1 — Male dryside cubicle detail',10),
    ('FRI_ROT_4WK',2,'Week 2 — Female dryside cubicle detail',20),
    ('FRI_ROT_4WK',3,'Week 3 — Studio/gym deep detail',30),
    ('FRI_ROT_4WK',4,'Week 4 — Female dryside repeat focus + highest-priority defects',40),
    ('SUN_ROT_4WK',1,'Week 1 — Male wetside cubicle & shower detail',10),
    ('SUN_ROT_4WK',2,'Week 2 — Female wetside cubicle & shower detail',20),
    ('SUN_ROT_4WK',3,'Week 3 — Pool hall walls & glazing detail',30),
    ('SUN_ROT_4WK',4,'Week 4 — Drains & gullies detail + highest-priority defects',40)
  ) AS x(prog_code, week_number, title, display_order)
  JOIN prog ON prog.code = x.prog_code
ON CONFLICT (rotation_programme_id, week_number) DO UPDATE
   SET title = EXCLUDED.title, display_order = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 9. Rotation step → focus item links
------------------------------------------------------------------------------
WITH site AS (SELECT id FROM public.sites WHERE code = 'ABBEY_LC'),
     prog AS (SELECT id, code FROM public.rotation_programmes WHERE site_id = (SELECT id FROM site)),
     steps AS (SELECT rs.id, rs.week_number, p.code AS prog_code
                 FROM public.rotation_steps rs JOIN prog p ON p.id = rs.rotation_programme_id),
     fi   AS (SELECT id, code FROM public.focus_items WHERE site_id = (SELECT id FROM site))
INSERT INTO public.rotation_step_focus_items (rotation_step_id, focus_item_id, display_order)
SELECT steps.id, fi.id, x.display_order
  FROM (VALUES
    ('FRI_ROT_4WK',1,'FI_002', 10),('FRI_ROT_4WK',1,'FI_004', 20),
    ('FRI_ROT_4WK',1,'FI_006', 30),('FRI_ROT_4WK',1,'FI_007', 40),
    ('FRI_ROT_4WK',2,'FI_010', 50),('FRI_ROT_4WK',2,'FI_012', 60),
    ('FRI_ROT_4WK',2,'FI_013', 70),('FRI_ROT_4WK',2,'FI_015', 80),
    ('FRI_ROT_4WK',3,'FI_018', 90),('FRI_ROT_4WK',3,'FI_020',100),
    ('FRI_ROT_4WK',3,'FI_021',110),('FRI_ROT_4WK',3,'FI_023',120),
    ('FRI_ROT_4WK',4,'FI_010', 50),('FRI_ROT_4WK',4,'FI_012', 60),
    ('FRI_ROT_4WK',4,'FI_013', 70),('FRI_ROT_4WK',4,'FI_015', 80),
    ('FRI_ROT_4WK',4,'FI_024',200),
    ('SUN_ROT_4WK',1,'FI_001', 10),('SUN_ROT_4WK',1,'FI_003', 20),
    ('SUN_ROT_4WK',1,'FI_005', 30),
    ('SUN_ROT_4WK',2,'FI_008', 40),('SUN_ROT_4WK',2,'FI_009', 50),
    ('SUN_ROT_4WK',2,'FI_011', 60),
    ('SUN_ROT_4WK',3,'FI_014', 70),('SUN_ROT_4WK',3,'FI_016', 80),
    ('SUN_ROT_4WK',3,'FI_017', 90),
    ('SUN_ROT_4WK',4,'FI_019',100),('SUN_ROT_4WK',4,'FI_022',110),
    ('SUN_ROT_4WK',4,'FI_025',200)
  ) AS x(prog_code, week_number, fi_code, display_order)
  JOIN steps ON steps.prog_code = x.prog_code AND steps.week_number = x.week_number
  JOIN fi    ON fi.code = x.fi_code
ON CONFLICT (rotation_step_id, focus_item_id) DO UPDATE
   SET display_order = EXCLUDED.display_order;

------------------------------------------------------------------------------
-- 10. Business catalogues (upsert only the approved rows; never delete live rows)
------------------------------------------------------------------------------
INSERT INTO public.issue_types (code, label, description, is_active, sort_order) VALUES
  ('dust','Dust / build-up','Dust, debris or build-up on surfaces',true,10),
  ('marks_smears','Marks / smears','Marks, smears or splashes',true,20),
  ('limescale','Limescale','Hard water deposits',true,30),
  ('grout_mould','Grout discoloration / mould','Discoloured or mouldy grout',true,40),
  ('hair_debris','Hair / debris','Loose hair or debris',true,50),
  ('stocking','Stocking issue','Consumable stocking issue',true,60),
  ('bin','Bin overflow / not emptied','Bin not handled',true,70),
  ('odour','Odour','Lingering odour',true,80),
  ('damage_breakage','Damage / breakage','Surface, fixture or equipment damage',true,90),
  ('slip_hazard','Slip / wet floor hazard','Wet floor or slip risk',true,100),
  ('chemical_safety','Chemical / COSHH','Chemical handling or storage issue',true,110),
  ('access_blocked','Access blocked','Area was unavailable to clean',true,120),
  ('not_specified','Not specified','Unspecified issue',true,900)
ON CONFLICT (code) DO UPDATE
   SET label = EXCLUDED.label, description = EXCLUDED.description,
       is_active = EXCLUDED.is_active, sort_order = EXCLUDED.sort_order;

INSERT INTO public.constraint_types (code, label, description, is_active, sort_order) VALUES
  ('area_in_use','Area in use by customers/staff','Area could not be cleaned because it was occupied',true,10),
  ('staff_absence','Staff absence on shift','Reduced staffing affected scope',true,20),
  ('equipment_failure','Equipment failure','Cleaning equipment failure',true,30),
  ('chemical_shortage','Chemical / consumable shortage','Stock or chemical shortage',true,40),
  ('water_supply','Water supply issue','No water / hot water issue',true,50),
  ('site_event','Site event / hire','Event in the building blocked access',true,60),
  ('maintenance_in_progress','Maintenance works in progress','Maintenance blocked or extended scope',true,70),
  ('weather','Weather','Weather impact (e.g. external areas)',true,80),
  ('other','Other','Free-text constraint',true,900)
ON CONFLICT (code) DO UPDATE
   SET label = EXCLUDED.label, description = EXCLUDED.description,
       is_active = EXCLUDED.is_active, sort_order = EXCLUDED.sort_order;

INSERT INTO public.visit_team_role_options (code, label, is_active, sort_order) VALUES
  ('supervisor','Supervisor on shift',true,10),
  ('cleaner','Cleaner',true,20),
  ('trainee','Trainee',true,30),
  ('relief','Relief / agency',true,40),
  ('observer','Observer',true,50)
ON CONFLICT (code) DO UPDATE
   SET label = EXCLUDED.label, is_active = EXCLUDED.is_active, sort_order = EXCLUDED.sort_order;

------------------------------------------------------------------------------
-- 11. Non-destructive assertions
------------------------------------------------------------------------------
DO $assert$
DECLARE
  v_site uuid;
  v_tpl_count int;
  v_tue uuid; v_fri uuid; v_sun uuid;
  v_lines_tue int; v_lines_fri int; v_lines_sun int;
  v_scope_tue int; v_scope_fri int; v_scope_sun int;
  v_prog_count int;
  v_steps_fri int; v_steps_sun int;
  v_fri_prog uuid; v_sun_prog uuid;
  v_tue_prog_count int;
  v_orphan_step int;
  v_dup int;
BEGIN
  SELECT id INTO v_site FROM public.sites WHERE code='ABBEY_LC';
  IF v_site IS NULL THEN RAISE EXCEPTION 'assert: Abbey site missing'; END IF;

  SELECT count(*) INTO v_tpl_count FROM public.visit_templates WHERE site_id = v_site;
  IF v_tpl_count <> 3 THEN RAISE EXCEPTION 'assert: expected 3 Abbey templates, got %', v_tpl_count; END IF;

  SELECT id INTO v_tue FROM public.visit_templates WHERE site_id=v_site AND code='TUE_SPA';
  SELECT id INTO v_fri FROM public.visit_templates WHERE site_id=v_site AND code='FRI_DRYSIDE';
  SELECT id INTO v_sun FROM public.visit_templates WHERE site_id=v_site AND code='SUN_WETSIDE';

  SELECT count(*) INTO v_lines_tue FROM public.template_rating_lines WHERE visit_template_id=v_tue;
  SELECT count(*) INTO v_lines_fri FROM public.template_rating_lines WHERE visit_template_id=v_fri;
  SELECT count(*) INTO v_lines_sun FROM public.template_rating_lines WHERE visit_template_id=v_sun;
  IF v_lines_tue <> 7  THEN RAISE EXCEPTION 'assert: Tuesday rating lines = %, expected 7',  v_lines_tue; END IF;
  IF v_lines_fri <> 11 THEN RAISE EXCEPTION 'assert: Friday rating lines = %, expected 11',  v_lines_fri; END IF;
  IF v_lines_sun <> 9  THEN RAISE EXCEPTION 'assert: Sunday rating lines = %, expected 9',   v_lines_sun; END IF;

  SELECT count(*) INTO v_scope_tue FROM public.template_scope_items WHERE visit_template_id=v_tue;
  SELECT count(*) INTO v_scope_fri FROM public.template_scope_items WHERE visit_template_id=v_fri;
  SELECT count(*) INTO v_scope_sun FROM public.template_scope_items WHERE visit_template_id=v_sun;
  IF v_scope_tue = 0 OR v_scope_fri = 0 OR v_scope_sun = 0 THEN
    RAISE EXCEPTION 'assert: each template requires scope items (tue=%, fri=%, sun=%)',
      v_scope_tue, v_scope_fri, v_scope_sun;
  END IF;

  SELECT count(*) INTO v_prog_count FROM public.rotation_programmes WHERE site_id=v_site;
  IF v_prog_count <> 2 THEN RAISE EXCEPTION 'assert: expected 2 rotation programmes, got %', v_prog_count; END IF;

  SELECT count(*) INTO v_tue_prog_count FROM public.rotation_programmes
    WHERE site_id=v_site AND visit_template_id=v_tue;
  IF v_tue_prog_count <> 0 THEN RAISE EXCEPTION 'assert: Tuesday must have no rotation programme'; END IF;

  SELECT id INTO v_fri_prog FROM public.rotation_programmes WHERE site_id=v_site AND code='FRI_ROT_4WK';
  SELECT id INTO v_sun_prog FROM public.rotation_programmes WHERE site_id=v_site AND code='SUN_ROT_4WK';

  SELECT count(*) INTO v_steps_fri FROM public.rotation_steps WHERE rotation_programme_id=v_fri_prog;
  SELECT count(*) INTO v_steps_sun FROM public.rotation_steps WHERE rotation_programme_id=v_sun_prog;
  IF v_steps_fri <> 4 THEN RAISE EXCEPTION 'assert: Friday rotation steps = %, expected 4', v_steps_fri; END IF;
  IF v_steps_sun <> 4 THEN RAISE EXCEPTION 'assert: Sunday rotation steps = %, expected 4', v_steps_sun; END IF;

  SELECT count(*) INTO v_orphan_step
    FROM public.rotation_steps rs
    JOIN public.rotation_programmes rp ON rp.id = rs.rotation_programme_id
   WHERE rp.site_id = v_site
     AND NOT EXISTS (SELECT 1 FROM public.rotation_step_focus_items WHERE rotation_step_id = rs.id);
  IF v_orphan_step > 0 THEN
    RAISE EXCEPTION 'assert: % rotation step(s) have no focus links', v_orphan_step;
  END IF;

  SELECT count(*) INTO v_dup FROM (
    SELECT visit_template_id, code FROM public.template_rating_lines
     WHERE visit_template_id IN (v_tue, v_fri, v_sun)
     GROUP BY 1,2 HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN RAISE EXCEPTION 'assert: duplicate rating-line codes'; END IF;

  SELECT count(*) INTO v_dup FROM (
    SELECT visit_template_id, code FROM public.template_scope_items
     WHERE visit_template_id IN (v_tue, v_fri, v_sun)
     GROUP BY 1,2 HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN RAISE EXCEPTION 'assert: duplicate scope codes'; END IF;

  SELECT count(*) INTO v_dup FROM (
    SELECT code FROM public.focus_items WHERE site_id=v_site GROUP BY 1 HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN RAISE EXCEPTION 'assert: duplicate focus_item codes'; END IF;

  RAISE NOTICE 'Abbey seed assertions passed (lines: tue=%/fri=%/sun=%, steps: fri=%/sun=%)',
    v_lines_tue, v_lines_fri, v_lines_sun, v_steps_fri, v_steps_sun;
END
$assert$;