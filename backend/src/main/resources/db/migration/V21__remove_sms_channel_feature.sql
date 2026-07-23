-- Remove the SMS messaging channel: the device-SIM SMS due-reminder feature and
-- its per-org channel toggle have been retired. Drop the org-level toggle rows
-- first (FK to feature_master), then the SMS feature_master seed row itself.
-- EMAIL (V20) and WHATSAPP (V2) channels are unaffected.
DELETE org_feat FROM organization_feature org_feat
  JOIN feature_master fm ON fm.feature_id = org_feat.feature_id
  WHERE fm.feature_code = 'SMS';

DELETE FROM feature_master WHERE feature_code = 'SMS';
