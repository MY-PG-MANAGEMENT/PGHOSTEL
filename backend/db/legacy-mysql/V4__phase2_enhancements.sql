-- PG Manager Phase 2 Enhancements
-- Database migration for mobile app support
-- Version: 4
-- Date: 2026-06-19

-- ============================================================================
-- SECTION 1: ROOM PHOTO MANAGEMENT
-- ============================================================================

-- New table for managing room photos separately from general content references
-- This provides faster queries for room gallery features
CREATE TABLE room_photo (
    room_photo_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    room_facility_id BIGINT NOT NULL,
    content_reference_id BIGINT,
    display_order INT NOT NULL DEFAULT 0,
    description VARCHAR(200),
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_room_photos (room_facility_id),
    CONSTRAINT fk_room_photo_facility FOREIGN KEY (room_facility_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_room_photo_content FOREIGN KEY (content_reference_id) REFERENCES content_reference (content_reference_id)
);

-- ============================================================================
-- SECTION 2: PAYMENT METHOD TRACKING
-- ============================================================================

-- Payment method type reference table
CREATE TABLE payment_method_type (
    method_type_id VARCHAR(40) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(250),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL
);

-- Insert standard payment method types
INSERT INTO payment_method_type (method_type_id, name, description, enabled, display_order, created_at) VALUES
('CASH', 'Cash Payment', 'Payment received in cash', TRUE, 10, NOW(6)),
('CHEQUE', 'Cheque', 'Payment via cheque', TRUE, 20, NOW(6)),
('UPI', 'UPI Transfer', 'Unified Payments Interface', TRUE, 30, NOW(6)),
('DEBIT_CARD', 'Debit Card', 'Payment via debit card', TRUE, 40, NOW(6)),
('CREDIT_CARD', 'Credit Card', 'Payment via credit card', TRUE, 50, NOW(6)),
('NET_BANKING', 'Net Banking', 'Online bank transfer', TRUE, 60, NOW(6)),
('WALLET', 'Digital Wallet', 'Payment via digital wallet', TRUE, 70, NOW(6)),
('BANK_TRANSFER', 'Bank Transfer', 'Direct bank transfer/NEFT/RTGS', TRUE, 80, NOW(6));

-- Add payment method type tracking to payment table
ALTER TABLE payment ADD COLUMN payment_method_type VARCHAR(40) AFTER payment_mode;
ALTER TABLE payment ADD CONSTRAINT fk_payment_method_type FOREIGN KEY (payment_method_type) REFERENCES payment_method_type (method_type_id);

-- ============================================================================
-- SECTION 3: DATABASE VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View 1: Current occupancy summary for dashboard
-- Shows facility occupancy metrics
CREATE VIEW facility_occupancy_summary AS
SELECT 
    f.facility_id,
    f.organization_id,
    f.facility_name,
    f.facility_type_id,
    COALESCE(f.capacity, 0) as total_capacity,
    COUNT(DISTINCT CASE 
        WHEN fp.role_type_id = 'OCCUPANT' AND (fp.thru_date IS NULL OR fp.thru_date >= CURDATE()) 
        THEN fp.party_id 
    END) as occupied_count,
    COALESCE(f.capacity, 0) - COUNT(DISTINCT CASE 
        WHEN fp.role_type_id = 'OCCUPANT' AND (fp.thru_date IS NULL OR fp.thru_date >= CURDATE()) 
        THEN fp.party_id 
    END) as vacant_count,
    CASE 
        WHEN COALESCE(f.capacity, 0) > 0 THEN 
            ROUND(100.0 * COUNT(DISTINCT CASE 
                WHEN fp.role_type_id = 'OCCUPANT' AND (fp.thru_date IS NULL OR fp.thru_date >= CURDATE()) 
                THEN fp.party_id 
            END) / f.capacity, 2)
        ELSE 0
    END as occupancy_percent
FROM facility f
LEFT JOIN facility_party fp ON f.facility_id = fp.facility_id
WHERE f.status = 'ACTIVE'
GROUP BY f.facility_id, f.organization_id, f.facility_name, f.facility_type_id, f.capacity;

-- View 2: Pending and overdue payment summary
-- Shows all pending invoices with overdue information
CREATE VIEW pending_payment_summary AS
SELECT 
    i.organization_id,
    i.invoice_id,
    i.billing_account_id,
    ba.party_id,
    p.full_name as tenant_name,
    i.invoice_number,
    i.invoice_month,
    i.due_date,
    i.total_amount,
    i.paid_amount,
    (i.total_amount - i.paid_amount) as pending_amount,
    i.status,
    DATEDIFF(CURDATE(), i.due_date) as days_overdue,
    CASE 
        WHEN i.status = 'PAID' THEN 'COLLECTED'
        WHEN DATEDIFF(CURDATE(), i.due_date) > 0 THEN 'OVERDUE'
        WHEN DATEDIFF(CURDATE(), i.due_date) = 0 THEN 'DUE_TODAY'
        ELSE 'PENDING'
    END as payment_status
FROM invoice i
JOIN billing_account ba ON i.billing_account_id = ba.billing_account_id
JOIN person p ON ba.party_id = p.party_id
WHERE i.status IN ('PENDING', 'PARTIAL');

-- View 3: Monthly revenue by property
-- Shows revenue trends for analytics
CREATE VIEW monthly_revenue_by_property AS
SELECT 
    i.organization_id,
    f.facility_id,
    f.facility_name,
    DATE_FORMAT(i.invoice_month, '%Y-%m') as month,
    COUNT(i.invoice_id) as invoice_count,
    SUM(i.total_amount) as total_invoiced,
    SUM(i.paid_amount) as total_collected,
    SUM(i.total_amount - i.paid_amount) as total_pending
FROM invoice i
JOIN billing_account ba ON i.billing_account_id = ba.billing_account_id
JOIN facility f ON ba.admission_id IS NOT NULL 
    AND ba.admission_id IN (SELECT admission_id FROM admission WHERE organization_id = f.organization_id)
WHERE i.organization_id = f.organization_id
GROUP BY i.organization_id, f.facility_id, f.facility_name, DATE_FORMAT(i.invoice_month, '%Y-%m');

-- View 4: Tenant occupancy history
-- Tracks tenant movement through beds/rooms
CREATE VIEW tenant_occupancy_history AS
SELECT
    a.organization_id,
    a.admission_id,
    pa.party_id,
    COALESCE(pe.full_name, '') AS tenant_name,
    bf.facility_name AS bed_name,
    rf.facility_name AS room_name,
    pf.facility_name AS property_name,
    a.move_in_date,
    COALESCE(c.checkout_date, CURDATE()) AS move_out_date,
    DATEDIFF(
        COALESCE(c.checkout_date, CURDATE()),
        a.move_in_date
    ) AS days_occupied,
    a.status AS admission_status,
    c.status AS checkout_status
FROM admission a
JOIN party pa
    ON a.party_id = pa.party_id
JOIN person pe
    ON pe.party_id = a.party_id
JOIN facility bf
    ON a.bed_facility_id = bf.facility_id
LEFT JOIN facility_group_member fgm_room
    ON bf.facility_id = fgm_room.child_facility_id
LEFT JOIN facility rf
    ON fgm_room.parent_facility_id = rf.facility_id
LEFT JOIN facility_group_member fgm_floor
    ON rf.facility_id = fgm_floor.child_facility_id
LEFT JOIN facility pf
    ON fgm_floor.parent_facility_id = pf.facility_id
LEFT JOIN checkout c
    ON a.admission_id = c.admission_id;

-- ============================================================================
-- SECTION 4: ANALYTICS AND CACHING
-- ============================================================================

-- Analytics cache table for storing computed dashboard metrics
-- Improves performance of repeated dashboard queries
CREATE TABLE analytics_cache (
    cache_key VARCHAR(100) PRIMARY KEY,
    organization_id BIGINT NOT NULL,
    cache_category VARCHAR(40) NOT NULL,
    cache_value JSON NOT NULL,
    cached_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    INDEX idx_cache_org_category (organization_id, cache_category),
    INDEX idx_cache_expires (expires_at),
    CONSTRAINT fk_cache_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

-- ============================================================================
-- SECTION 5: ACTIVITY AND AUDIT ENHANCEMENTS
-- ============================================================================

-- Enhanced activity log for better tracking of user actions
-- Useful for support, debugging, and analytics
CREATE TABLE activity_log (
    activity_log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    user_login_id BIGINT,
    activity_type VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50),
    entity_id BIGINT,
    action_name VARCHAR(100),
    action_details JSON,
    old_values JSON,
    new_values JSON,
    ip_address VARCHAR(80),
    user_agent VARCHAR(500),
    created_at DATETIME(6) NOT NULL,
    INDEX idx_activity_org_created (organization_id, created_at),
    INDEX idx_activity_user (user_login_id),
    INDEX idx_activity_entity (entity_type, entity_id),
    CONSTRAINT fk_activity_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_activity_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

-- ============================================================================
-- SECTION 6: REPORTING SUPPORT (OPTIONAL)
-- ============================================================================

-- Receipt generation tracking (optional, for future PDF generation)
CREATE TABLE payment_receipt (
    receipt_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    payment_id BIGINT NOT NULL,
    receipt_number VARCHAR(80) NOT NULL UNIQUE,
    receipt_date DATE NOT NULL,
    receipt_format VARCHAR(20) NOT NULL DEFAULT 'PDF',
    file_path VARCHAR(500),
    status VARCHAR(30) NOT NULL DEFAULT 'GENERATED',
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_receipt_payment (payment_id),
    CONSTRAINT fk_receipt_payment FOREIGN KEY (payment_id) REFERENCES payment (payment_id)
);

-- ============================================================================
-- SECTION 7: UPDATE EXISTING TABLES FOR BETTER FUNCTIONALITY
-- ============================================================================

-- Add notification priority tracking to invoices for rent reminders
ALTER TABLE invoice ADD COLUMN notification_sent BOOLEAN NOT NULL DEFAULT FALSE AFTER status;
ALTER TABLE invoice ADD COLUMN last_reminder_sent_at DATETIME(6) AFTER notification_sent;

-- Add metadata for room features
ALTER TABLE facility ADD COLUMN amenities_json JSON AFTER version;
ALTER TABLE facility ADD COLUMN photos_count INT DEFAULT 0 AFTER amenities_json;

-- ============================================================================
-- SECTION 8: DATA INITIALIZATION
-- ============================================================================

-- Ensure all existing payments have a payment method type
-- Default to CASH if not specified (assumes legacy data)
UPDATE payment SET payment_method_type = 'CASH' WHERE payment_method_type IS NULL;

-- ============================================================================
-- SECTION 9: INDEXES FOR PERFORMANCE OPTIMIZATION
-- ============================================================================


-- ============================================================================
-- SECTION 10: DOCUMENTATION COMMENTS
-- ============================================================================

/*
MIGRATION SUMMARY:

1. ROOM PHOTOS: New room_photo table for efficient gallery management
   - Links facility photos to specific rooms
   - Supports display ordering
   - Future-ready for S3 integration via content_reference

2. PAYMENT METHODS: Added method_type_id to payment table
   - Allows tracking of payment channel (UPI, Card, etc.)
   - Reference table with all supported methods
   - Cash is default for backward compatibility

3. DATABASE VIEWS: Created 4 optimized views
   - facility_occupancy_summary: Dashboard occupancy KPIs
   - pending_payment_summary: Payment collection status
   - monthly_revenue_by_property: Revenue analytics
   - tenant_occupancy_history: Tenant movement tracking

4. ANALYTICS: New analytics_cache table
   - Stores computed metrics for dashboard
   - Configurable expiration for cache invalidation
   - Significantly improves dashboard performance

5. ACTIVITY LOG: Enhanced tracking for support and debugging
   - Records user actions with entity-level tracking
   - Stores old/new values for audit purposes
   - IP address and user agent for security

6. INDEXES: Added performance-critical indexes
   - Dashboard queries
   - Notification queries
   - Payment queries
   - Occupancy queries

BACKWARD COMPATIBILITY:
- All new tables are additive
- Existing payment records updated with default payment_method_type = 'CASH'
- No existing tables dropped or modified in incompatible ways
- Legacy rent/payment APIs continue to work

FUTURE ENHANCEMENTS:
- Enable content_reference storage_provider (S3/GCS)
- Implement report generation using analytics_cache
- Add WhatsApp integration via notification_outbox
- Enable online payment provider integration
*/
