-- Messaging channels are toggled per organization via organization_feature rows
-- keyed by these feature_master codes. WHATSAPP is already seeded in V2.
-- Channels are opt-in: a channel is enabled for an org only when an
-- organization_feature row exists with enabled = TRUE.
INSERT IGNORE INTO feature_master (feature_code, feature_name, active, created_at, updated_at) VALUES
('EMAIL', 'Email Notifications', TRUE, NOW(6), NOW(6)),
('SMS', 'SMS Notifications', TRUE, NOW(6), NOW(6));
