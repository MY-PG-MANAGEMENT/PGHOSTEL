# Caching (Redis)

The backend has an **opt-in, fail-open** Redis cache layer built on Spring's cache
abstraction (`@Cacheable` / `@CacheEvict`). Central config lives in
`common/cache/CacheConfig.java`.

## How it behaves

- **Toggle:** `app.cache.enabled` (env `CACHE_ENABLED`), default **`false`**.
  - `false` → a `NoOpCacheManager` is wired; annotated methods run normally, no Redis
    needed. Local dev and existing deployments boot unchanged.
  - `true` → a `RedisCacheManager` is wired (JSON values, `pgm:cache:` key prefix,
    per-cache TTLs, transaction-aware so a rolled-back write never poisons the cache).
- **Fail-open:** a `CacheErrorHandler` swallows Redis errors (timeout / down /
  serialization) and logs a warning, so an outage degrades to direct DB reads instead of
  failing requests. Lettuce connects lazily, so `enabled=true` with Redis down still boots.
- **Multi-tenant safe:** every key begins with `organizationId`. Nothing is cached across
  orgs except (future) truly-global reference tables.

### Enabling in production

```
CACHE_ENABLED=true
REDIS_HOST=<host>
REDIS_PORT=6379
REDIS_PASSWORD=<secret>   # optional
```

## What is cached today

### Reference / config (single clean eviction point each)

| Cache | Read method | Key | Evicted by | TTL |
|---|---|---|---|---|
| `ORG_FEATURES` | `OrganizationChannelService.enabled`; `TenantLoginPolicy.enabled` | `org:CODE` | `setChannel`, `setEnabled`, `OnboardingService.run` (clears all — rare) | 30 min |
| `SHARING_PRICES` | `PropertySharingPriceService.list` | `org:propertyId` | `PropertySharingPriceService.upsert` | 30 min |
| `FACILITY_TREE` | `FacilityService.tree` | `org` | `FacilityService.createChild/update/deleteBed/link`, `BulkUploadController.uploadFacilities` | 60 min |

`list()` is the only cached price read — the bed-assignment `OccupancyService.resolveRent`
reads the repository directly, so rent is always fresh regardless of this cache.

### Occupancy read models (wholesale eviction on every occupancy write)

These mirror live bed occupancy, so they are evicted **wholesale** (`allEntries=true`) on
every occupancy/structure write via the composed `@EvictOccupancyCaches` annotation —
eliminating any chance of a key-mismatch showing an occupied bed as vacant.

| Cache | Read method | Key |
|---|---|---|
| `ROOM_SUMMARY` | `FacilityService.getRoomSummary` | `org:propertyId` |
| `PROPERTY_STATS` | `FacilityService.propertyStats` | `org:propertyId` |
| `VACANT_BEDS` | `FacilityController.vacantBeds` | `org:propertyId` |
| `TEMP_STAYS` | `TemporaryStayController.list` | `org:propertyId:status:q` |

**`@EvictOccupancyCaches`** (`common/cache/`) is on every write entry point that touches
`facility_party` occupancy: `OccupancyService.{assign, transfer, applyDueTransfers,
cancelScheduledTransfer, tempStay, updateTempStay, endTempStay, checkout}`,
`OccupancyController.setExpectedCheckout`, `TenantService.create`; structural writes
(`FacilityService.*`, `BulkUploadController.uploadFacilities`) evict them too. All occupancy
mutations funnel through these methods (e.g. `TenantLifecycleController` delegates to
`OccupancyService`), so the set is complete. Add a new occupancy read model to the
`@EvictOccupancyCaches` list once and every writer picks it up.

## Adding a new cache

1. Add a constant + TTL entry in `CacheConfig`.
2. `@Cacheable(cacheNames = CacheConfig.X, key = "#organizationId + ':' + …")` on the read
   (always lead the key with `organizationId`). Add `condition` to skip null-org paths.
   Avoid caching `Optional`-returning methods (serialization friction) — cache the
   `List`/value form instead.
3. `@CacheEvict` with the **same key** on *every* method that mutates that data. Miss one
   and you serve stale data.

## Deliberately NOT cached — decision

The **money dashboards are intentionally left live** (owners must never see stale
financials, and at single-org scale the queries are fast). If read cost ever bites, add
them only with a **short TTL** (30–60s), not fine-grained eviction:

- **Billing dashboard** — `BillingController.dashboard` (8 queries/hit).
- **Expense dashboard** — `ExpenseController.dashboard` (~12 queries/hit; key must include `month`).
- **Transactions ledger** — `TransactionController.ledger` (key includes `month`).
- **Property report** — `FacilityController.propertyReport` (4× full 5-level tree walk; includes defaulters/invoices).
- **Owner / super-admin dashboards** — money aggregates, invalidated by almost any write.

## Further opt-in extensions

1. **Facility tree resolvers** — `OccupancyService.resolvePropertyId/resolveSharingType/
   resolveSharingPrice`, `TenantService.resolvePropertyId/resolveSharingType`. 3–5 DB
   round-trips each on every assign/transfer and tenant-portal load. Key
   `facility:{bedId}:property` / `facility:{roomId}:sharingType`; evict on `facility` /
   `facility_group_member` writes (would slot into `@EvictOccupancyCaches`).
2. **Staff list** — `StaffController.list` (key includes `month`; evict on staff writes + pay).
3. **Global reference tables** — `amenity_type`, `role_type`/`permission`,
   `feature_master`. Cross-org, effectively immutable at runtime →
   cache globally (no org key), long TTL, lowest complexity.

Avoid caching the super-admin `dashboard`/`revenueReport` with fine-grained eviction —
they are global aggregates invalidated by almost any write system-wide; short TTL only.

> Note: `FacilityType`, `OccupancyRole`, `RoleType`, expense category/method lists, etc. are
> Java compile-time constants, **not** DB tables — already in memory, nothing to cache.
