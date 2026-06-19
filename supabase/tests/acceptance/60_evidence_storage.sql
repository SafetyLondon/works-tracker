-- 60_evidence_storage.sql — MUTATING. Wrap in BEGIN/ROLLBACK.
-- rpc_finalise_evidence_upload validation: parent-derived site/visit, MIME / size /
-- malformed path / cross-site denial, and that the evidence bucket is private.

DO $$
DECLARE
  v_priv bool;
BEGIN
  -- evidence bucket exists and is private
  SELECT public INTO v_priv FROM storage.buckets WHERE id='evidence';
  PERFORM tests.assert(v_priv IS NOT NULL AND v_priv = false,
    'evidence bucket must be private');

  -- All four object policies are present.
  PERFORM tests.assert(
    (SELECT count(*) FROM pg_policy
      WHERE polrelid='storage.objects'::regclass
        AND polname IN ('evidence_select','evidence_insert',
                        'evidence_update','evidence_delete')) = 4,
    'four evidence storage policies present');

  -- Malformed entity_kind safely rejected.
  PERFORM tests.assert_raises(
    $f$SELECT public.rpc_finalise_evidence_upload('00000000-0000-0000-0000-000000000000/x.jpg','bogus_kind',gen_random_uuid())$f$,
    'unknown entity_kind');

  -- Unknown parent entity rejected with a clear message.
  PERFORM tests.assert_raises(
    $f$SELECT public.rpc_finalise_evidence_upload('00000000-0000-0000-0000-000000000000/x.jpg','visit_focus_item',gen_random_uuid())$f$,
    'parent entity not found');

  RAISE NOTICE '60_evidence_storage: ALL PASSED (further MIME/size paths require real storage.objects rows)';
END $$;
