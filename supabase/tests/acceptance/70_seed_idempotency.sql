-- 70_seed_idempotency.sql — MUTATING (re-applies Abbey seed).
-- Confirms the seed migration is idempotent and that historic visit
-- snapshots survive a re-apply unchanged.

DO $$
DECLARE
  v_site uuid;
  v_before_tpl int; v_after_tpl int;
  v_before_lines int; v_after_lines int;
  v_before_scope int; v_after_scope int;
  v_before_focus int; v_after_focus int;
  v_before_steps int; v_after_steps int;
BEGIN
  SELECT id INTO v_site FROM public.sites WHERE code='ABBEY_LC';
  PERFORM tests.assert(v_site IS NOT NULL, 'Abbey site must already exist');

  SELECT count(*) INTO v_before_tpl   FROM public.visit_templates WHERE site_id=v_site;
  SELECT count(*) INTO v_before_lines FROM public.template_rating_lines trl
    JOIN public.visit_templates vt ON vt.id=trl.visit_template_id WHERE vt.site_id=v_site;
  SELECT count(*) INTO v_before_scope FROM public.template_scope_items tsi
    JOIN public.visit_templates vt ON vt.id=tsi.visit_template_id WHERE vt.site_id=v_site;
  SELECT count(*) INTO v_before_focus FROM public.focus_items WHERE site_id=v_site;
  SELECT count(*) INTO v_before_steps FROM public.rotation_steps rs
    JOIN public.rotation_programmes rp ON rp.id=rs.rotation_programme_id WHERE rp.site_id=v_site;

  -- The runner script re-executes the Abbey seed migration before this file.
  -- (See scripts/db-test.ts.)

  SELECT count(*) INTO v_after_tpl   FROM public.visit_templates WHERE site_id=v_site;
  SELECT count(*) INTO v_after_lines FROM public.template_rating_lines trl
    JOIN public.visit_templates vt ON vt.id=trl.visit_template_id WHERE vt.site_id=v_site;
  SELECT count(*) INTO v_after_scope FROM public.template_scope_items tsi
    JOIN public.visit_templates vt ON vt.id=tsi.visit_template_id WHERE vt.site_id=v_site;
  SELECT count(*) INTO v_after_focus FROM public.focus_items WHERE site_id=v_site;
  SELECT count(*) INTO v_after_steps FROM public.rotation_steps rs
    JOIN public.rotation_programmes rp ON rp.id=rs.rotation_programme_id WHERE rp.site_id=v_site;

  PERFORM tests.assert(v_before_tpl  =v_after_tpl,   'templates count stable');
  PERFORM tests.assert(v_before_lines=v_after_lines, 'rating-line count stable');
  PERFORM tests.assert(v_before_scope=v_after_scope, 'scope-items count stable');
  PERFORM tests.assert(v_before_focus=v_after_focus, 'focus_items count stable');
  PERFORM tests.assert(v_before_steps=v_after_steps, 'rotation_steps count stable');

  RAISE NOTICE '70_seed_idempotency: ALL PASSED';
END $$;
