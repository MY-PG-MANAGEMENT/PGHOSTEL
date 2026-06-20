# PG Manager - Implementation Roadmap & Development Guide

**Status:** Complete Analysis & Planning  
**Date:** June 19, 2026  
**Prepared for:** Full Stack Development

---

## 📋 Quick Reference

### Documents Created
1. ✅ **MOBILE_APP_BACKEND_MAPPING.md** - Complete screen-to-database mapping
2. ✅ **API_SPECIFICATION.md** - 80+ API endpoints with request/response examples
3. ✅ **V4__phase2_enhancements.sql** - Database migration for all enhancements
4. ✅ **ER Diagrams** (4 new Mermaid files):
   - `room-photos-enhancement.mmd`
   - `payment-billing-enhancement.mmd`
   - `dashboard-analytics-module.mmd`
   - `tenant-management-module.mmd`

### What You Have
- ✅ Core database schema (60+ tables)
- ✅ Spring Boot backend structure (10+ modules)
- ✅ Multi-tenancy implementation
- ✅ JWT authentication
- ✅ RBAC system (7 roles, 7 permissions)
- ✅ Notification infrastructure
- ✅ Billing/Payment foundation

### What's Ready to Build
- ⏳ Dashboard APIs (3 endpoints)
- ⏳ Notification APIs (6 endpoints)
- ⏳ Payment APIs (8 endpoints)
- ⏳ Property APIs (7 endpoints)
- ⏳ Room/Bed APIs (6 endpoints)
- ⏳ Tenant APIs (13 endpoints)
- ⏳ Settings APIs (5 endpoints)
- ⏳ Admin APIs (8 endpoints)

---

## 🎯 Implementation Priority

### Phase 1: Database Enhancements (4-5 hours)
**Status:** Ready to execute

1. **Apply Migration V4**
   ```bash
   # Flyway will automatically run V4__phase2_enhancements.sql on next startup
   gradle bootRun
   ```
   
   **Creates:**
   - `room_photo` table
   - `payment_method_type` table
   - 4 database views
   - `analytics_cache` table
   - `activity_log` table
   - `payment_receipt` table (optional)
   - Performance indexes

2. **Verify Migration**
   ```sql
   -- Check all new tables exist
   SHOW TABLES LIKE 'room_photo';
   SHOW TABLES LIKE 'payment_method_type';
   SHOW TABLES LIKE 'analytics_cache';
   ```

3. **Test Views**
   ```sql
   SELECT * FROM facility_occupancy_summary LIMIT 5;
   SELECT * FROM pending_payment_summary LIMIT 5;
   ```

---

### Phase 2: Backend API Development (2-3 weeks)

#### Week 1: Core APIs (Priority 1)

**Sprint 1.1: Dashboard Module** (2-3 days)
```
Files to create:
- backend/src/main/java/com/pgmanager/dashboard/DashboardController.java
- backend/src/main/java/com/pgmanager/dashboard/DashboardService.java
- backend/src/main/java/com/pgmanager/dashboard/DashboardRepository.java

Endpoints:
✓ GET /api/dashboard/owner-summary
✓ GET /api/dashboard/revenue-stats
✓ GET /api/dashboard/occupancy-stats
✓ GET /api/dashboard/pending-payments
```

**Sprint 1.2: Payment Module** (3-4 days)
```
Files to create:
- backend/src/main/java/com/pgmanager/payment/PaymentController.java
- backend/src/main/java/com/pgmanager/payment/PaymentService.java
- backend/src/main/java/com/pgmanager/payment/PaymentRepository.java
- backend/src/main/java/com/pgmanager/payment/PaymentMethodTypeRepository.java

Endpoints:
✓ GET /api/payments/dashboard
✓ GET /api/payments/{invoiceId}/details
✓ POST /api/payments
✓ GET /api/payments/methods
✓ GET /api/payments/history
✓ GET /api/payments/pending-dues
✓ GET /api/payments/{paymentId}/receipt
✓ POST /api/payments/advances
```

**Sprint 1.3: Property Module** (2-3 days)
```
Files to create:
- backend/src/main/java/com/pgmanager/facility/PropertyController.java
- backend/src/main/java/com/pgmanager/facility/PropertyService.java
- backend/src/main/java/com/pgmanager/facility/PropertyRepository.java

Endpoints:
✓ GET /api/properties
✓ POST /api/properties
✓ GET /api/properties/{id}
✓ PUT /api/properties/{id}
✓ GET /api/properties/{id}/floors
✓ GET /api/properties/{id}/amenities
✓ PUT /api/properties/{id}/amenities
```

#### Week 2: Entity Management APIs

**Sprint 2.1: Room/Bed Module** (2-3 days)
```
Endpoints:
✓ GET /api/rooms
✓ GET /api/rooms/{id}
✓ POST /api/rooms
✓ PUT /api/rooms/{id}
✓ GET /api/beds/{id}
✓ PUT /api/beds/{id}/tenant
✓ GET /api/rooms/{id}/photos
✓ POST /api/rooms/{id}/photos
```

**Sprint 2.2: Tenant Module** (3-4 days)
```
Endpoints:
✓ GET /api/tenants
✓ GET /api/tenants/{id}
✓ PUT /api/tenants/{id}/personal-details
✓ POST /api/tenants/{id}/documents
✓ GET /api/tenants/{id}/emergency-contacts
✓ POST /api/tenants/{id}/emergency-contacts
✓ GET /api/tenants/{id}/employment
✓ PUT /api/tenants/{id}/employment
✓ POST /api/admissions
✓ GET /api/admissions/{id}/agreement
✓ POST /api/admissions/{id}/agreement/sign
✓ POST /api/admissions/{id}/checkout
✓ POST /api/admissions/{id}/checkout/settle
```

#### Week 3: Settings & Admin APIs

**Sprint 3.1: Settings & Notifications** (1-2 days)
```
Endpoints:
✓ GET /api/settings/profile
✓ PUT /api/settings/profile
✓ PUT /api/settings/change-password
✓ GET /api/settings/preferences
✓ PUT /api/settings/preferences
✓ GET /api/notifications
✓ GET /api/notifications/{id}
✓ POST /api/notifications/{id}/mark-read
✓ POST /api/notifications/{id}/archive
✓ GET /api/notifications/preferences
✓ PUT /api/notifications/preferences
```

**Sprint 3.2: Admin Module** (2-3 days)
```
Endpoints:
✓ GET /api/admin/dashboard
✓ GET /api/admin/properties
✓ POST /api/admin/properties/status
✓ GET /api/admin/users
✓ POST /api/admin/users
✓ GET /api/admin/roles
✓ PUT /api/admin/roles/{id}
✓ GET /api/admin/plans
✓ PUT /api/admin/plans/{id}
✓ GET /api/admin/customers
✓ GET /api/admin/audit-logs
✓ GET /api/admin/settings
✓ PUT /api/admin/settings
```

---

## 📊 Development Checklist

### Database Layer
- [ ] Run migration V4 (Flyway will auto-run)
- [ ] Verify all new tables created
- [ ] Test all new views with sample queries
- [ ] Create indexes and verify performance

### API Layer - Dashboard
- [ ] Create DashboardController
- [ ] Create DashboardService with business logic
- [ ] Create DashboardRepository for queries
- [ ] Implement exception handling
- [ ] Add unit tests
- [ ] Test with Postman/Swagger

### API Layer - Payments
- [ ] Extend Payment entity with payment_method_type
- [ ] Create PaymentController
- [ ] Create PaymentService
- [ ] Update PaymentRepository
- [ ] Create PaymentMethodTypeRepository
- [ ] Implement all 8 payment endpoints
- [ ] Add validation (amount > 0, valid method type, etc.)
- [ ] Test receipt generation

### API Layer - Properties
- [ ] Extend Facility entity for property features
- [ ] Create PropertyController
- [ ] Create PropertyService
- [ ] Implement hierarchy queries (floors, rooms, beds)
- [ ] Implement amenity management
- [ ] Add photo management APIs

### API Layer - Rooms/Beds
- [ ] Create RoomController
- [ ] Create BedController
- [ ] Implement room photo management
- [ ] Implement tenant assignment
- [ ] Add occupancy tracking

### API Layer - Tenants
- [ ] Extend Person/Party entities
- [ ] Create TenantController
- [ ] Create AdmissionService
- [ ] Implement document upload (with placeholder for storage)
- [ ] Implement checkout/settlement flow
- [ ] Add comprehensive filtering

### API Layer - Settings & Admin
- [ ] Create SettingsController
- [ ] Create AdminController
- [ ] Implement RBAC checks
- [ ] Add audit logging to all write operations
- [ ] Create reporting views

### Testing
- [ ] Unit tests for all services
- [ ] Integration tests for APIs
- [ ] Performance tests on dashboard queries
- [ ] Multi-tenancy isolation tests
- [ ] Permission/RBAC tests

---

## 🔧 Development Setup

### Prerequisites
```
✓ JDK 21+
✓ Gradle 8.x
✓ MySQL 8.0+
✓ Git
```

### Backend Setup
```bash
# 1. Navigate to backend
cd backend

# 2. Build project
gradle clean build

# 3. Run migrations automatically
gradle bootRun

# 4. Access API documentation
http://localhost:8080/swagger-ui.html
```

### Database Setup
```sql
-- Create database
CREATE DATABASE pg_manager;

-- Run migrations (automatic via Flyway)
-- Just start Spring Boot and Flyway runs all V*.sql files
```

---

## 📝 Code Structure

### Suggested Package Organization
```
com.pgmanager/
├── auth/                    # Authentication (already exists)
├── security/                # JWT & RBAC (already exists)
├── party/                   # Party/Person (already exists)
├── facility/                # Property/Room/Bed management
│   ├── PropertyController
│   ├── PropertyService
│   ├── PropertyRepository
│   ├── RoomController
│   ├── RoomService
│   ├── RoomRepository
│   └── RoomPhotoService
├── tenant/                  # Tenant management (extend existing)
├── occupancy/               # Room occupancy (already exists)
├── billing/                 # Billing & Invoices (already exists)
├── payment/                 # Payment management (EXTEND)
│   ├── PaymentController
│   ├── PaymentService
│   ├── PaymentMethodTypeRepository
│   └── PaymentReceiptService
├── dashboard/               # Analytics & KPIs (NEW)
│   ├── DashboardController
│   ├── DashboardService
│   ├── DashboardRepository
│   └── AnalyticsService
├── notification/            # Notifications (already exists)
├── settings/                # User settings (already exists)
├── admin/                   # Super admin (extend)
│   ├── AdminController
│   ├── AdminService
│   ├── AdminRepository
│   └── ReportingService
└── common/                  # Shared utilities (already exists)
```

---

## 🎨 Key Implementation Patterns

### 1. Repository Pattern
```java
@Repository
public interface PaymentRepository extends JpaRepository<Payment, Long> {
    List<Payment> findByOrganizationIdAndPaymentDateBetween(
        Long orgId, LocalDate fromDate, LocalDate toDate);
    
    List<Payment> findByInvoiceIdAndStatus(Long invoiceId, String status);
}
```

### 2. Service Layer
```java
@Service
@Transactional
public class PaymentService {
    
    private final PaymentRepository paymentRepository;
    private final InvoiceRepository invoiceRepository;
    
    public PaymentResponse recordPayment(PaymentRequest req) {
        // Validation
        // Business logic
        // Transaction handling
        // Return response
    }
}
```

### 3. Controller Pattern
```java
@RestController
@RequestMapping("/api/payments")
public class PaymentController {
    
    @GetMapping
    @PreAuthorize("hasAnyRole('OWNER', 'PROPERTY_MANAGER')")
    public ResponseEntity<PageResponse<PaymentDTO>> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size) {
        // Implementation
    }
}
```

### 4. Error Handling
```java
@ExceptionHandler(EntityNotFoundException.class)
public ResponseEntity<ErrorResponse> handleNotFound(
    EntityNotFoundException ex, HttpServletRequest req) {
    return ResponseEntity.status(HttpStatus.NOT_FOUND)
        .body(ErrorResponse.error(ex.getMessage()));
}
```

---

## 🔍 Testing Strategy

### Unit Tests
```java
@ExtendWith(MockitoExtension.class)
class PaymentServiceTest {
    
    @Mock
    private PaymentRepository paymentRepository;
    
    @InjectMocks
    private PaymentService paymentService;
    
    @Test
    void testRecordPayment_Success() {
        // Arrange
        // Act
        // Assert
    }
}
```

### Integration Tests
```java
@SpringBootTest
@TestContainers
class PaymentControllerIT {
    
    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>();
    
    @Test
    void testPaymentFlow() {
        // Full flow test
    }
}
```

---

## 📋 SQL Queries Reference

### Dashboard Queries
```sql
-- Occupancy Summary
SELECT f.facility_id, f.facility_name, 
       COUNT(CASE WHEN fp.thru_date IS NULL THEN 1 END) as occupied,
       f.capacity - COUNT(CASE WHEN fp.thru_date IS NULL THEN 1 END) as vacant
FROM facility f
LEFT JOIN facility_party fp ON f.facility_id = fp.facility_id
WHERE f.organization_id = ? AND f.facility_type_id IN ('ROOM', 'BED')
GROUP BY f.facility_id;

-- Revenue by Period
SELECT DATE_FORMAT(i.invoice_month, '%Y-%m') as month,
       SUM(i.total_amount) as invoiced,
       SUM(i.paid_amount) as collected,
       SUM(i.total_amount - i.paid_amount) as pending
FROM invoice i
WHERE i.organization_id = ?
GROUP BY DATE_FORMAT(i.invoice_month, '%Y-%m')
ORDER BY month DESC;

-- Pending Payments
SELECT i.invoice_id, i.invoice_number,
       (i.total_amount - i.paid_amount) as pending_amount,
       DATEDIFF(CURDATE(), i.due_date) as days_overdue
FROM invoice i
WHERE i.organization_id = ? AND i.status IN ('PENDING', 'PARTIAL')
ORDER BY i.due_date ASC;
```

---

## 🔐 Security Checklist

- [ ] JWT tokens validated on all endpoints
- [ ] Organization ID derived from authenticated user (not from request)
- [ ] Row-level security enforced (users only see their org data)
- [ ] Sensitive fields (passwords) never returned in API
- [ ] File uploads scanned for malware
- [ ] SQL injection prevention (use parameterized queries)
- [ ] CSRF protection enabled
- [ ] Rate limiting configured
- [ ] Audit logging for all write operations
- [ ] Encryption for sensitive data at rest

---

## 📈 Performance Optimization

### Database Indexes (Already in V4)
- ✅ `idx_invoice_org_month_status`
- ✅ `idx_invoice_due_date`
- ✅ `idx_facility_party_active`
- ✅ `idx_admission_org_status`

### Application-Level
- ✅ Database views for complex queries
- ✅ Analytics cache table for dashboard KPIs
- ✅ Pagination for large result sets
- ✅ Lazy loading for related entities

### Caching Strategy (Future)
```java
@Cacheable(value = "occupancy", key = "#orgId")
public OccupancyStats getOccupancyStats(Long orgId) {
    // Will be cached for 1 hour
}
```

---

## 📞 Support & Troubleshooting

### Common Issues

**Issue: Migration fails with "Table already exists"**
- Solution: Migrations are idempotent with `CREATE TABLE IF NOT EXISTS`, but check if table structure changed

**Issue: Payment method type shows NULL**
- Solution: Update existing payments with `UPDATE payment SET payment_method_type = 'CASH' WHERE payment_method_type IS NULL`

**Issue: Dashboard queries are slow**
- Solution: Run `EXPLAIN` on queries, check indexes are being used, consider analytics_cache table

**Issue: Multi-tenancy violation (seeing other org's data)**
- Solution: Always filter by `organization_id` derived from authenticated user, never from request

---

## 📚 References

### Spring Boot Documentation
- [Spring Data JPA](https://spring.io/projects/spring-data-jpa)
- [Spring Security](https://spring.io/projects/spring-security)
- [Spring REST Docs](https://spring.io/projects/spring-restdocs)

### MySQL Documentation
- [JSON Functions](https://dev.mysql.com/doc/refman/8.0/en/json-functions.html)
- [Window Functions](https://dev.mysql.com/doc/refman/8.0/en/window-functions.html)
- [Dates and Times](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html)

### Architecture
- [Microservices Patterns](https://microservices.io/patterns/index.html)
- [API Best Practices](https://google.aip.dev/general-guidance)

---

## 🚀 Deployment Checklist

- [ ] All tests passing (unit + integration)
- [ ] Code coverage > 80%
- [ ] No security vulnerabilities (OWASP)
- [ ] API documentation updated (Swagger)
- [ ] Database migration tested
- [ ] Performance benchmarks passed
- [ ] Error handling comprehensive
- [ ] Logging configured (debug/info/warn/error)
- [ ] Environment variables configured
- [ ] Docker image built and tested

---

## 📞 Questions & Next Steps

### Questions to Answer Before Development
1. **File Storage**: Ready to enable S3/GCS for room photos and documents?
2. **Payment Gateway**: Planning online payment integration (UPI, Cards)?
3. **Email Service**: Configure SMTP for email notifications?
4. **SMS Gateway**: Planning SMS notifications?
5. **Reporting**: Need advanced reporting beyond basic dashboard?

### Next Steps
1. ✅ **Done**: Database schema analysis
2. ✅ **Done**: API specification
3. ⏳ **Next**: Apply database migration V4
4. ⏳ **Then**: Start backend API development
5. ⏳ **Then**: Develop Flutter app UI screens
6. ⏳ **Finally**: Integration testing

---

## 📊 Project Timeline Estimate

| Phase | Duration | Status |
|-------|----------|--------|
| Database Enhancements | 4-5 hours | Ready |
| Dashboard APIs | 2-3 days | Planned |
| Payment APIs | 3-4 days | Planned |
| Property/Room APIs | 2-3 days | Planned |
| Tenant APIs | 3-4 days | Planned |
| Settings/Admin APIs | 3-4 days | Planned |
| Testing & Fixes | 3-5 days | Planned |
| Documentation | 2-3 days | Planned |
| **TOTAL** | **3-4 weeks** | **On Track** |

---

## ✨ Clean Code Principles

**Your Requirements:**
> "Make functionality clean and clear way and future development make easy"

### Implementation Strategy

1. **Clear Naming**
   ```java
   ✅ Good: getOccupancyPercentageForProperty()
   ❌ Bad: getOccupancy(), getOccPct()
   ```

2. **Single Responsibility**
   ```java
   ✅ PaymentService (payment operations)
   ✅ PaymentReceiptService (receipt generation)
   ✅ PaymentMethodService (method management)
   ❌ PaymentService (does everything)
   ```

3. **Dependency Injection**
   ```java
   ✅ Constructor injection
   ❌ Field injection or static methods
   ```

4. **Meaningful Comments**
   ```java
   ✅ // Calculate remaining balance after allocation
   ❌ // var b = amt - paid;
   ```

5. **Logging for Debugging**
   ```java
   logger.info("Payment recorded: invoiceId={}, amount={}", invoiceId, amount);
   logger.debug("Occupancy calculation: totalBeds={}, occupied={}", total, occupied);
   ```

6. **Consistent Exception Handling**
   ```java
   ✅ throw new PaymentNotFoundException("Invoice not found: " + invoiceId);
   ❌ throw new Exception("Error!");
   ```

---

**Document Version:** 1.0  
**Created:** June 19, 2026  
**Status:** Ready for Implementation  
**Next Review:** After Phase 1 completion
