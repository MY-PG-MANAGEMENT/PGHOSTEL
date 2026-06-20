# PG Manager - Mobile App to Backend Mapping & Database Analysis

**Document Date:** June 19, 2026  
**Status:** Complete Analysis with Recommendations

---

## Executive Summary

The PG Manager project has a well-structured foundation with Spring Boot backend and comprehensive database schema. This document provides:

1. ✅ Mobile app screen-to-backend API mapping
2. ✅ Database table sufficiency analysis
3. ✅ Identified gaps and recommendations
4. ✅ ER diagrams for all modules
5. 📋 Implementation roadmap

---

## Part 1: Mobile Screens Mapped to Backend APIs & Database Tables

### MODULE 1: DASHBOARD MODULE (2 Screens)

#### Screen 1.1: Owner Dashboard
**Purpose:** Main overview of property performance

**Mobile Elements:**
- Total Tenants (count)
- Occupied Beds (count)
- Vacant Beds (count)
- Today's Collection (sum)
- Monthly Revenue (sum)
- Pending Payments (sum)
- Monthly Revenue Chart (trend line)
- Pending Payments Details (table)
- Complaints (count)
- Quick Actions (5 buttons)

**Required Backend APIs:**
```
GET /api/dashboard/owner-summary
GET /api/dashboard/revenue-stats
GET /api/dashboard/occupancy-stats
GET /api/dashboard/pending-payments
```

**Required Database Tables:**
| Table | Status | Reason |
|-------|--------|--------|
| `facility` | ✅ Exists | Property/Room/Bed hierarchy |
| `facility_party` | ✅ Exists | Occupancy tracking |
| `invoice` | ✅ Exists | Payment tracking |
| `payment` | ✅ Exists | Payment records |
| `admission` | ✅ Exists | Tenant admission |
| **`room_photo`** | ❌ **MISSING** | Need to store room photos |
| **`facility_occupancy_view`** | ⚠️ Recommended | DB view for efficient occupancy queries |
| **`analytics_cache`** | ⚠️ Optional | Cache dashboard KPIs for performance |

---

#### Screen 1.2: Analytics Dashboard
**Purpose:** In-depth analytics and reporting

**Mobile Elements:**
- Occupancy Rate (percentage + chart)
- Collection Rate (percentage + chart)
- Avg Rent/Bed (chart)
- Total Revenue (KPI)
- Revenue Overview (bar chart)
- Top Properties by Revenue (table)
- Occupancy Overview (donut chart)
- Recent Activity (timeline)

**Required Backend APIs:**
```
GET /api/analytics/occupancy-rate
GET /api/analytics/collection-rate
GET /api/analytics/revenue-by-property
GET /api/analytics/recent-activity
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `invoice` | ✅ Exists | Revenue calculation |
| `payment` | ✅ Exists | Collection tracking |
| `facility_party` | ✅ Exists | Occupancy data |
| `admission` | ✅ Exists | Tenant move-in dates |
| **`analytics_event`** | ⚠️ Optional | Track activity for timeline |

---

### MODULE 2: NOTIFICATIONS MODULE (4 Screens)

#### Screens 2.1-2.4: Notifications Management
**Purpose:** Multi-channel notification delivery and preferences

**Mobile Elements:**
- Notifications list (with categories: All, Unread, Important)
- Notification details (title, message, details)
- Notification settings (toggle per category & channel)
- Archived notifications

**Required Backend APIs:**
```
GET /api/notifications
POST /api/notifications/{id}/mark-read
POST /api/notifications/{id}/archive
GET /api/notifications/preferences
PUT /api/notifications/preferences
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `notification_category` | ✅ Exists | Category types |
| `notification` | ✅ Exists | Notification records |
| `notification_recipient` | ✅ Exists | Read/archive tracking |
| `notification_preference` | ✅ Exists | User preferences |
| `notification_outbox` | ✅ Exists | Provider integration |

**✅ STATUS: ALL TABLES EXIST**

---

### MODULE 3: PAYMENT MANAGEMENT MODULE (8 Screens)

#### Screens 3.1-3.8: Payment Operations

**Mobile Elements:**
- Payment Dashboard (collection KPIs)
- Payment Details (tenant, amount breakdown)
- Make Payment (form with validation)
- Payment Methods (UPI, Card, Net Banking, Wallet, Bank Transfer)
- Payment History (list with filters)
- Pending Dues (table with override dates)
- Receipt (PDF/view)
- Advance Payment (payment application)

**Required Backend APIs:**
```
GET /api/payments/dashboard
GET /api/payments/{invoiceId}
POST /api/payments
GET /api/payments/methods
GET /api/payments/history?tenant=...&status=...
GET /api/payments/pending-dues
GET /api/payments/{paymentId}/receipt
POST /api/payments/advances
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `invoice` | ✅ Exists | Invoice tracking |
| `invoice_item` | ✅ Exists | Line items |
| `payment` | ✅ Exists | Payment records |
| `payment_allocation` | ✅ Exists | Invoice-Payment mapping |
| `payment_refund` | ✅ Exists | Refund tracking |
| `billing_account` | ✅ Exists | Advance balance tracking |
| **`payment_method`** | ❌ **MISSING** | Payment method details |
| **`payment_receipt`** | ⚠️ Recommended | Receipt generation tracking |

---

### MODULE 4: PROPERTY MANAGEMENT MODULE (6 Screens)

#### Screens 4.1-4.6: Property Operations

**Mobile Elements:**
- Property List (with search & filters)
- Add Property (form with image upload)
- Property Details (info + stats)
- Edit Property (update form)
- Floors (hierarchy with room counts)
- Amenities (toggle list with details)

**Required Backend APIs:**
```
GET /api/properties
POST /api/properties
GET /api/properties/{id}
PUT /api/properties/{id}
GET /api/properties/{id}/floors
GET /api/properties/{id}/amenities
PUT /api/properties/{id}/amenities
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `facility` | ✅ Exists | Property hierarchy |
| `facility_group_member` | ✅ Exists | Floor/Room/Bed hierarchy |
| `facility_contact_mech` | ✅ Exists | Address & contact |
| `facility_amenity` | ✅ Exists | Amenities |
| `amenity_type` | ✅ Exists | Amenity catalog |
| `content_reference` | ✅ Exists | Property images (currently disabled) |
| **`property_amenity_schedule`** | ⚠️ Optional | Scheduled maintenance |
| **`property_occupancy_summary`** | ⚠️ Recommended | DB view |

---

### MODULE 5: ROOM MANAGEMENT MODULE (6 Screens)

#### Screens 5.1-5.6: Room & Bed Operations

**Mobile Elements:**
- Room List (with filters, property selector)
- Room Details (info, statistics, images)
- Bed Details (individual bed info, occupancy)
- Vacant Bed (availability info, assign button)
- Assign Tenant (search & select)
- Room Photos (gallery + upload)

**Required Backend APIs:**
```
GET /api/rooms?property={propertyId}
GET /api/rooms/{id}
POST /api/rooms
PUT /api/rooms/{id}
GET /api/rooms/{id}/beds
GET /api/beds/{id}
PUT /api/beds/{id}/tenant
GET /api/rooms/{id}/photos
POST /api/rooms/{id}/photos
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `facility` (type=ROOM,BED) | ✅ Exists | Room/Bed entity |
| `facility_party` | ✅ Exists | Occupancy data |
| `admission` | ✅ Exists | Tenant admission |
| `content_reference` | ✅ Exists | Photos (storage disabled) |
| **`room_photo`** | ❌ **MISSING** | Separate tracking for room photos |
| **`bed_occupancy_history`** | ⚠️ Recommended | Better tracking |

---

### MODULE 6: SETTINGS MODULE (5 Screens)

#### Screens 6.1-6.5: User Settings

**Mobile Elements:**
- Settings Home (menu options)
- Profile Information (editable user details)
- Change Password (validation flow)
- Notification Settings (category & channel toggles)
- App & Preferences (theme, language, date format)

**Required Backend APIs:**
```
GET /api/settings/profile
PUT /api/settings/profile
PUT /api/settings/change-password
GET /api/settings/preferences
PUT /api/settings/preferences
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `person` | ✅ Exists | User profile |
| `user_login` | ✅ Exists | Login/auth |
| `user_preference` | ✅ Exists | App preferences |
| `notification_preference` | ✅ Exists | Notification preferences |
| `user_device` | ✅ Exists | Device tracking |

**✅ STATUS: ALL TABLES EXIST**

---

### MODULE 7: SUPER ADMIN MODULE (10 Screens)

#### Screens 7.1-7.10: Platform Administration

**Mobile Elements:**
- Dashboard (platform KPIs)
- Properties (all properties, status management)
- Users (team members, role assignment)
- Roles & Permissions (RBAC management)
- Plans & Pricing (subscription tiers)
- Customers (organization accounts)
- Reports (various reports with filters)
- Audit Logs (system activity)
- System Settings (configuration)
- Profile (admin profile management)

**Required Backend APIs:**
```
GET /api/admin/dashboard
GET /api/admin/properties
POST /api/admin/properties/status
GET /api/admin/users
POST /api/admin/users
GET /api/admin/roles
PUT /api/admin/roles/{id}
GET /api/admin/plans
PUT /api/admin/plans/{id}
GET /api/admin/customers
GET /api/admin/reports/*
GET /api/admin/audit-logs
GET /api/admin/settings
PUT /api/admin/settings
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `role_type` | ✅ Exists | Role definitions |
| `role_permission` | ✅ Exists | Permission assignment |
| `permission` | ✅ Exists | Permission catalog |
| `subscription_plan` | ✅ Exists | Plans |
| `plan_feature` | ✅ Exists | Plan features |
| `feature_master` | ✅ Exists | Feature catalog |
| `audit_log` | ✅ Exists | Activity tracking |
| `user_login` | ✅ Exists | User management |
| `system_setting` | ✅ Exists | Configuration |
| **`admin_report_template`** | ⚠️ Recommended | Customizable reports |
| **`admin_audit_advanced`** | ⚠️ Optional | Enhanced audit details |

---

### MODULE 8: TENANT MANAGEMENT MODULE (10 Screens)

#### Screens 8.1-8.10: Tenant Lifecycle

**Mobile Elements:**
- Tenant List (search, filter by status)
- Tenant Profile (summary info)
- Personal Details (editable)
- ID Documents (upload + verification)
- Emergency Contact (details & actions)
- Job Information (employment details)
- New Admission (onboarding flow)
- Agreement (terms & signature)
- Checkout (settlement calculation)
- Deposit Settlement (refund calculation)

**Required Backend APIs:**
```
GET /api/tenants?property={id}&status=...
GET /api/tenants/{id}
PUT /api/tenants/{id}
GET /api/tenants/{id}/documents
POST /api/tenants/{id}/documents
GET /api/tenants/{id}/emergency-contacts
POST /api/tenants/{id}/emergency-contacts
GET /api/tenants/{id}/employment
PUT /api/tenants/{id}/employment
POST /api/admissions
GET /api/admissions/{id}
GET /api/admissions/{id}/agreement
POST /api/admissions/{id}/agreement/sign
GET /api/admissions/{id}/checkout
POST /api/admissions/{id}/checkout
```

**Required Database Tables:**
| Table | Status | Comment |
|-------|--------|---------|
| `party` | ✅ Exists | Tenant entity |
| `person` | ✅ Exists | Personal info |
| `identity_document` | ✅ Exists | ID docs |
| `emergency_contact` | ✅ Exists | Emergency contacts |
| `tenant_employment` | ✅ Exists | Job info |
| `admission` | ✅ Exists | Tenant admission |
| `agreement` | ✅ Exists | Agreement tracking |
| `checkout` | ✅ Exists | Checkout process |
| `billing_account` | ✅ Exists | Billing |
| `content_reference` | ✅ Exists | Document storage |

**✅ STATUS: ALL TABLES EXIST**

---

## Part 2: Database Gap Analysis & Recommendations

### Critical Gaps (Must Have)

#### Gap 1: Room Photo Management
**Current State:** `content_reference` exists but storage is DISABLED

**Recommendation:** 
- ✅ Keep `content_reference` as is (future-proof for S3/GCS)
- Create dedicated `room_photo` table for simplified access pattern:

```sql
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
```

---

#### Gap 2: Payment Method Configuration
**Current State:** Payment records don't track payment method type

**Recommendation:**
```sql
ALTER TABLE payment ADD COLUMN payment_method_type VARCHAR(40);
-- Values: CASH, UPI, CARD, NET_BANKING, WALLET, BANK_TRANSFER

-- Optional: Create lookup table
CREATE TABLE payment_method_type (
    method_type_id VARCHAR(40) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(250),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0
);
```

---

### Recommended Enhancements (Should Have)

#### Enhancement 1: Database Views for Common Queries

**View 1: Current Occupancy**
```sql
CREATE VIEW facility_occupancy_summary AS
SELECT 
    f.facility_id,
    f.facility_name,
    f.capacity,
    COUNT(DISTINCT CASE WHEN fp.thru_date IS NULL THEN fp.party_id END) as occupied_count,
    f.capacity - COUNT(DISTINCT CASE WHEN fp.thru_date IS NULL THEN fp.party_id END) as vacant_count,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN fp.thru_date IS NULL THEN fp.party_id END) / f.capacity, 2) as occupancy_percent
FROM facility f
LEFT JOIN facility_party fp ON f.facility_id = fp.facility_id
WHERE f.facility_type_id = 'BED' AND fp.thru_date IS NULL OR fp.thru_date >= CURDATE()
GROUP BY f.facility_id, f.facility_name, f.capacity;
```

**View 2: Pending Payment Summary**
```sql
CREATE VIEW pending_payment_summary AS
SELECT 
    i.organization_id,
    i.billing_account_id,
    i.invoice_id,
    i.invoice_month,
    i.due_date,
    (i.total_amount - i.paid_amount) as pending_amount,
    DATEDIFF(CURDATE(), i.due_date) as days_overdue
FROM invoice i
WHERE i.status IN ('PENDING', 'PARTIAL');
```

---

#### Enhancement 2: Analytics Cache Table
```sql
CREATE TABLE analytics_cache (
    cache_key VARCHAR(100) PRIMARY KEY,
    organization_id BIGINT NOT NULL,
    cache_value JSON,
    cached_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    INDEX idx_cache_expires (expires_at),
    INDEX idx_cache_org (organization_id)
);
```

---

#### Enhancement 3: Activity Audit Trail
```sql
CREATE TABLE activity_log (
    activity_log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    user_login_id BIGINT,
    activity_type VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50),
    entity_id BIGINT,
    action_details JSON,
    ip_address VARCHAR(80),
    created_at DATETIME(6) NOT NULL,
    INDEX idx_activity_org_created (organization_id, created_at),
    CONSTRAINT fk_activity_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);
```

---

### Nice-to-Have Enhancements

1. **Receipt Storage:** `payment_receipt` table for receipt generation tracking
2. **Bulk Operations:** Support for bulk tenant import, payment uploads
3. **Tenant History:** `tenant_occupancy_history` for detailed tracking
4. **Facility Images:** Separate table for primary facility images (not just content_reference)

---

## Part 3: Complete ER Diagrams

### Diagram 1: Core Party & Facility Hierarchy

```
PARTY (tenant/user/owner)
  ├── PERSON (detailed profile)
  ├── USER_LOGIN (authentication)
  │   ├── REFRESH_TOKEN
  │   ├── USER_DEVICE (biometric)
  │   ├── USER_PREFERENCE
  │   └── LOGIN_HISTORY
  ├── PARTY_ROLE (role assignments)
  │   └── ROLE_PERMISSION
  ├── FACILITY_PARTY (occupancy)
  ├── EMERGENCY_CONTACT
  ├── TENANT_EMPLOYMENT
  └── IDENTITY_DOCUMENT
     └── CONTENT_REFERENCE

FACILITY (Org/Property/Floor/Room/Bed)
  ├── FACILITY_GROUP_MEMBER (hierarchy)
  ├── FACILITY_CONTACT_MECH (address/phone)
  │   └── POSTAL_ADDRESS / CONTACT_MECH
  ├── FACILITY_AMENITY
  │   └── AMENITY_TYPE
  ├── FACILITY_PARTY (occupancy)
  ├── ROOM_PHOTO (NEW)
  │   └── CONTENT_REFERENCE
  ├── ADMISSION
  │   ├── AGREEMENT
  │   ├── CHECKOUT
  │   └── BILLING_ACCOUNT
  └── CONTENT_REFERENCE (images/docs)
```

---

### Diagram 2: Billing & Payment Flow

```
BILLING_ACCOUNT
  ├── RECURRING_CHARGE (subscriptions)
  ├── INVOICE
  │   ├── INVOICE_ITEM
  │   ├── PAYMENT_ALLOCATION ←──→ PAYMENT
  │   └── STATUS: PENDING/PARTIAL/PAID/OVERDUE
  └── ADVANCE_BALANCE

PAYMENT
  ├── PAYMENT_ALLOCATION (links to invoices)
  ├── PAYMENT_REFUND (refund tracking)
  ├── PAYMENT_METHOD_TYPE (NEW: CASH/UPI/CARD/etc)
  └── STATUS: RECEIVED/APPROVED/FAILED/REFUNDED
```

---

### Diagram 3: Notification System

```
NOTIFICATION_CATEGORY
  ├── RENT_REMINDER
  ├── PAYMENT_UPDATE
  ├── MAINTENANCE
  ├── COMPLAINT
  ├── TENANT_UPDATE
  ├── AGREEMENT
  └── PROMOTION

NOTIFICATION
  ├── NOTIFICATION_RECIPIENT (multi-recipient)
  │   └── READ/ARCHIVED state
  ├── NOTIFICATION_PREFERENCE (per party/category/channel)
  └── NOTIFICATION_OUTBOX (provider integration)
     ├── Channel: IN_APP / EMAIL / SMS / WHATSAPP
     └── Status: PENDING / SENT / FAILED / DISABLED
```

---

### Diagram 4: RBAC System

```
ROLE_TYPE
  ├── SUPER_ADMIN → All permissions
  ├── OWNER → Org operations
  ├── PROPERTY_MANAGER → Property level
  ├── MANAGER → Team management
  ├── ACCOUNTANT → Billing/Accounting
  ├── SUPPORT → Support operations
  └── VIEWER → Read-only access

ROLE_PERMISSION (effective-dated)
  └── PERMISSION (by module)
      ├── DASHBOARD_VIEW
      ├── PROPERTY_MANAGE
      ├── TENANT_MANAGE
      ├── BILLING_MANAGE
      ├── REPORT_VIEW
      ├── SETTINGS_MANAGE
      └── PLATFORM_MANAGE
```

---

## Part 4: Implementation Roadmap

### Phase 1: Database Enhancements ⏭️ **START HERE**

- [ ] Create `room_photo` table
- [ ] Add `payment_method_type` tracking to payments
- [ ] Create database views (occupancy, pending payments)
- [ ] (Optional) Create `analytics_cache` table
- [ ] (Optional) Create `activity_log` table

**Estimated Time:** 4 hours  
**Risk:** Low  
**Impact:** Medium

---

### Phase 2: Backend API Development

**Priority 1 (Critical for all modules):**
- [ ] Dashboard APIs (summary, revenue, occupancy stats)
- [ ] Payment APIs (all 8 screens)
- [ ] Property/Room/Bed management APIs
- [ ] Tenant management APIs

**Priority 2 (Super Admin):**
- [ ] Admin dashboard APIs
- [ ] User/Role management APIs
- [ ] Reports APIs
- [ ] Settings APIs

**Priority 3 (Enhancements):**
- [ ] Advanced analytics
- [ ] Bulk operations
- [ ] File upload APIs

---

### Phase 3: Mobile App Refinements

- [ ] Implement all 8 modules
- [ ] Add offline support
- [ ] Integrate payment methods UI
- [ ] Add photo gallery
- [ ] Push notifications

---

## Part 5: Summary & Recommendations

### ✅ What's Good

1. **Database Foundation:** 60+ tables already provide excellent coverage
2. **RBAC System:** Comprehensive role-based access control in place
3. **Multi-Tenancy:** Organization-scoped security implemented
4. **Notification System:** Full infrastructure for multi-channel delivery
5. **Audit Trail:** Built-in audit logging for compliance

### ⚠️ What Needs Attention

1. **Photo Management:** No dedicated tracking for room photos (recommend `room_photo` table)
2. **Payment Methods:** No explicit method type tracking (recommend adding column)
3. **Analytics Performance:** Dashboard queries may need optimization with views/caching
4. **File Storage:** Currently disabled, needs configuration for production

### 🚀 Quick Wins

1. Add `room_photo` table (30 mins)
2. Create occupancy & pending payment views (30 mins)
3. Build dashboard APIs (2 hours)
4. Implement payment flow APIs (3 hours)

### 📊 Data Consistency Notes

- Use `organization_id` in all queries for multi-tenant isolation
- Keep `effective-dated` rows (from_date, thru_date) for history tracking
- Maintain audit_log entries for compliance
- Use version fields for optimistic locking in concurrent updates

---

## Appendix: SQL Scripts

All migration scripts should be placed in:
```
backend/src/main/resources/db/migration/V4__phase2_enhancements.sql
```

See Part 2 above for DDL statements.

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-19  
**Next Review:** After database migration
