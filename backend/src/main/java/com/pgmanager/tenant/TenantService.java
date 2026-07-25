package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.cache.EvictOccupancyCaches;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.occupancy.FacilityParty;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Party;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.PartyType;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantPatchRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import com.pgmanager.tenant.dto.TenantDtos.TenantUpdateRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.pgmanager.facility.FacilityGroupMember;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@RequiredArgsConstructor
public class TenantService {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(TenantService.class);

    private final PartyRepository partyRepository;
    private final PersonRepository personRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository facilityGroupMemberRepository;
    private final AuditService auditService;
    private final NotificationService notificationService;
    private final TenantLoginService tenantLoginService;
    private final TenantArchiveService tenantArchiveService;

    // Creating a tenant writes facility_party (bed occupant + property membership),
    // so it changes bed occupancy → drop the occupancy read models.
    @EvictOccupancyCaches
    @Transactional
    public TenantResponse create(Long organizationId, Long userLoginId, TenantCreateRequest request) {
        log.info("Tenant create START: org={}, userLogin={}, mobile={}, propertyId={}, name='{}'",
                organizationId, userLoginId, request.mobileNumber(), request.propertyId(), request.fullName());

        // ── Rejoin is checked FIRST, before the duplicate-mobile rejection ──
        // This mobile belongs to a tenant who was archived ("deleted") from this org, so
        // registering them again is not a duplicate — it is the same person coming back.
        // The order matters: archiving deliberately leaves their TENANT membership rows with a
        // null thru_date, so countActiveTenantsByMobileAtProperty still counts them and would
        // reject the rejoin with "already registered at this property" if it ran first.
        //
        // Restoring reuses their original partyId, so the invoice / payment history they built
        // up comes back with them instead of being orphaned behind a duplicate person.
        // To the caller it looks like a normal create (`restoredFromArchive: true` on the DTO).
        Optional<Long> archivedParty = tenantArchiveService.findArchivedPartyByMobile(
                organizationId, request.mobileNumber());
        if (archivedParty.isPresent()) {
            Long restoreParty = archivedParty.get();
            // The one case where a repeat mobile really is a clash: a *different* tenant with
            // that number is living here right now. Then this is not a rejoin.
            if (personRepository.countOccupyingTenantsByMobileExcluding(
                    request.mobileNumber(), organizationId, restoreParty) > 0) {
                log.warn("Tenant create REJECTED: mobile {} is archived as party {} but another tenant "
                        + "with that mobile currently occupies a bed (org {})",
                        request.mobileNumber(), restoreParty, organizationId);
                throw new com.pgmanager.common.exception.BadRequestException(
                        "Another tenant with this mobile number is currently occupying a bed");
            }
            log.info("Tenant create: mobile {} matches archived party {} in org {} — restoring instead of creating",
                    request.mobileNumber(), restoreParty, organizationId);
            return restoreFromArchive(organizationId, userLoginId, restoreParty,
                    request.propertyId(), request);
        }

        // Reject if an active TENANT with this mobile already exists at the same property.
        // No check when propertyId is absent — same mobile is allowed across different properties.
        if (request.propertyId() != null
                && personRepository.countActiveTenantsByMobileAtProperty(
                        request.mobileNumber(), organizationId, request.propertyId()) > 0) {
            log.warn("Tenant create REJECTED: mobile {} already an active tenant at property {} (org {})",
                    request.mobileNumber(), request.propertyId(), organizationId);
            throw new com.pgmanager.common.exception.BadRequestException(
                    "A tenant with this mobile number is already registered at this property");
        }

        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);
        Person person = new Person();
        person.setPartyId(party.getPartyId());
        applyFields(person, request);
        personRepository.save(person);
        log.info("Tenant create: persisted party/person partyId={} for org={}", party.getPartyId(), organizationId);

        ensureOrgTenantMembership(organizationId, party.getPartyId());
        log.debug("Tenant create: org-level TENANT membership ensured for partyId={}", party.getPartyId());

        if (request.propertyId() != null) {
            ensurePropertyTenantMembership(organizationId, party.getPartyId(), request.propertyId());
        }

        // Post-persist side effects are best-effort: a failure in audit / welcome notification /
        // login provisioning must NEVER 500 or roll back the tenant creation itself. Each is
        // isolated so one failing does not skip the others, and the cause is logged.
        try {
            auditService.log(organizationId, userLoginId, "TENANT_CREATED", "PARTY", party.getPartyId(), "Tenant created");
        } catch (Exception e) {
            log.warn("Tenant create: audit log failed for partyId={} (tenant still created): {}", party.getPartyId(), e.getMessage(), e);
        }
        try {
            notificationService.notifyTenantWelcome(organizationId, party.getPartyId());
        } catch (Exception e) {
            log.warn("Tenant create: welcome notification failed for partyId={} (tenant still created): {}", party.getPartyId(), e.getMessage(), e);
        }
        // Auto-provision a tenant login when the org has opted into the feature (no-op otherwise).
        // This single funnel covers manual add, Excel bulk upload, and self check-in.
        tenantLoginService.provisionForTenant(organizationId, party.getPartyId(), request.mobileNumber());
        log.info("Tenant create OK (pending commit): partyId={} for org={} (propertyId={})",
                party.getPartyId(), organizationId, request.propertyId());
        return toResponse(person, null, null, null, null, false, null, null, null, null);
    }

    /**
     * Writes the property-scoped TENANT membership row (so the tenant shows up in
     * property-scoped lists), validating that the property belongs to the caller's org.
     * Idempotent — an existing active row is left alone.
     */
    private void ensurePropertyTenantMembership(Long organizationId, Long partyId, Long propertyId) {
        Facility property = facilityRepository.findById(propertyId)
                .orElseThrow(() -> {
                    log.warn("Tenant property membership FAILED: property {} not found (org {})", propertyId, organizationId);
                    return new com.pgmanager.common.exception.BadRequestException("Property not found");
                });
        if (!organizationId.equals(property.getOrganizationId())) {
            log.warn("Tenant property membership FAILED: property {} belongs to org {} but caller org is {}",
                    propertyId, property.getOrganizationId(), organizationId);
            throw new com.pgmanager.common.exception.BadRequestException("Property not in current organization");
        }
        boolean exists = facilityPartyRepository
                .findByOrganizationIdAndPartyIdAndRoleTypeId(organizationId, partyId, OccupancyRole.TENANT)
                .stream().anyMatch(fp -> propertyId.equals(fp.getFacilityId()) && fp.getThruDate() == null);
        if (exists) return;
        FacilityParty propertyMembership = new FacilityParty();
        propertyMembership.setOrganizationId(organizationId);
        propertyMembership.setFacilityId(propertyId);
        propertyMembership.setPartyId(partyId);
        propertyMembership.setRoleTypeId(OccupancyRole.TENANT);
        propertyMembership.setFromDate(LocalDate.now());
        facilityPartyRepository.save(propertyMembership);
        log.info("Tenant: property-level TENANT membership written partyId={} property={}", partyId, propertyId);
    }

    /**
     * Un-archives a tenant so they reappear in the tenant lists (as Inactive — no bed yet),
     * keeping the original partyId and therefore every invoice, payment and document they
     * already had.
     *
     * <p>Two callers: the owner's explicit "Restore" action on the Archived Tenants screen
     * ({@code details == null}), and {@link #create} when a rejoining tenant is re-registered
     * through the Add Tenant form ({@code details} = that form). In the second case only the
     * fields the form actually filled in are written over the stored profile — a blank field
     * keeps its old value rather than wiping emergency-contact / employment details the form
     * never asks for.
     */
    @Transactional
    public TenantResponse restoreFromArchive(Long organizationId, Long userLoginId, Long partyId,
            Long propertyId, TenantCreateRequest details) {
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        boolean wasArchived = tenantArchiveService.unarchive(organizationId, userLoginId, partyId);
        if (!wasArchived) {
            throw new com.pgmanager.common.exception.BadRequestException("This tenant is not archived");
        }
        if (details != null) {
            applyEnteredFields(person, details);
            personRepository.save(person);
        }
        // Archiving never ended the membership rows, so these are safety nets for a tenant
        // whose org row was missing, plus the property scope they are rejoining at.
        ensureOrgTenantMembership(organizationId, partyId);
        if (propertyId != null) {
            ensurePropertyTenantMembership(organizationId, partyId, propertyId);
        }
        try {
            auditService.log(organizationId, userLoginId, "TENANT_RESTORED_FROM_ARCHIVE", "PARTY", partyId,
                    details != null ? "Tenant restored on re-registration" : "Tenant restored from archive");
        } catch (Exception e) {
            log.warn("Tenant restore: audit log failed for partyId={} (restore still applied): {}", partyId, e.getMessage(), e);
        }
        // Reactivates the tenant's portal login when the org has the feature on (no-op otherwise).
        tenantLoginService.provisionForTenant(organizationId, partyId, person.getMobileNumber());
        log.info("Tenant restore OK (pending commit): partyId={} org={} propertyId={}", partyId, organizationId, propertyId);
        return toResponse(person, true);
    }

    public void ensureOrgTenantMembership(Long organizationId, Long partyId) {
        if (facilityPartyRepository.findOrgMembership(organizationId, partyId, OccupancyRole.TENANT).isEmpty()) {
            FacilityParty fp = new FacilityParty();
            fp.setOrganizationId(organizationId);
            fp.setFacilityId(organizationId);
            fp.setPartyId(partyId);
            fp.setRoleTypeId(OccupancyRole.TENANT);
            fp.setFromDate(LocalDate.now());
            facilityPartyRepository.save(fp);
        }
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> list(Long organizationId) {
        // Query only org-level TENANT rows (facilityId = organizationId) so that
        // property-scoped TENANT rows don't produce duplicate entries.
        List<FacilityParty> tenantRows = facilityPartyRepository
                .findTenantsAtFacility(organizationId, organizationId, OccupancyRole.TENANT);
        log.info("Tenant list (org-level): org={} found {} org-level TENANT membership rows", organizationId, tenantRows.size());
        return buildTenantResponses(organizationId, tenantRows);
    }

    /**
     * Builds tenant responses for a set of TENANT membership rows using a fixed number of
     * batch queries (person, active occupant/temp, bed, room) regardless of tenant count —
     * no per-tenant queries. Shared by {@link #list} and {@link #listByProperty}.
     */
    private List<TenantResponse> buildTenantResponses(Long organizationId, List<FacilityParty> tenantRows) {
        if (tenantRows.isEmpty()) return List.of();

        // Archived ("deleted") tenants are hidden from every tenant list. One query for the
        // whole org — filtering here covers both list() and listByProperty().
        Set<Long> archived = tenantArchiveService.archivedPartyIds(organizationId);
        if (!archived.isEmpty()) {
            int before = tenantRows.size();
            tenantRows = tenantRows.stream().filter(fp -> !archived.contains(fp.getPartyId())).toList();
            log.debug("Tenant list: org={} hid {} archived tenant(s) of {}", organizationId, before - tenantRows.size(), before);
            if (tenantRows.isEmpty()) return List.of();
        }

        List<Long> partyIds = tenantRows.stream().map(FacilityParty::getPartyId).distinct().toList();

        Map<Long, Person> personMap = personRepository.findAllById(partyIds).stream()
                .collect(Collectors.toMap(Person::getPartyId, p -> p));

        Map<Long, FacilityParty> occupantMap = facilityPartyRepository
                .findActiveOccupantsByPartyIds(organizationId, partyIds, OccupancyRole.OCCUPANT).stream()
                .collect(Collectors.toMap(FacilityParty::getPartyId, fp -> fp, (a, b) -> a));

        // Active temporary stays also count as "in a bed" — the tenant is treated as active.
        Map<Long, FacilityParty> tempMap = facilityPartyRepository
                .findActiveOccupantsByPartyIds(organizationId, partyIds, OccupancyRole.TEMP_OCCUPANT).stream()
                .collect(Collectors.toMap(FacilityParty::getPartyId, fp -> fp, (a, b) -> a));

        List<Long> bedIds = Stream.concat(
                        occupantMap.values().stream(), tempMap.values().stream())
                .map(FacilityParty::getFacilityId).distinct().toList();

        Map<Long, Facility> bedMap = bedIds.isEmpty() ? Map.of()
                : facilityRepository.findAllById(bedIds).stream()
                        .collect(Collectors.toMap(Facility::getFacilityId, f -> f));

        Map<Long, Long> bedToRoomId = bedIds.isEmpty() ? Map.of()
                : facilityGroupMemberRepository.findByChildFacilityIdInAndThruDateIsNull(bedIds).stream()
                        .collect(Collectors.toMap(
                                FacilityGroupMember::getChildFacilityId, FacilityGroupMember::getParentFacilityId, (a, b) -> a));

        List<Long> roomIds = bedToRoomId.values().stream().distinct().toList();
        Map<Long, Facility> roomMap = roomIds.isEmpty() ? Map.of()
                : facilityRepository.findAllById(roomIds).stream()
                        .collect(Collectors.toMap(Facility::getFacilityId, f -> f));

        return tenantRows.stream()
                .map(fp -> {
                    Person person = personMap.get(fp.getPartyId());
                    if (person == null) return null;
                    FacilityParty occupant = occupantMap.get(fp.getPartyId());
                    // Prefer a permanent bed; fall back to an active temporary stay.
                    FacilityParty active = occupant != null ? occupant : tempMap.get(fp.getPartyId());
                    String bedName = null, roomName = null;
                    boolean hasAdmission = false;
                    LocalDate moveInDate = null;
                    BigDecimal monthlyRent = null, securityDeposit = null;
                    LocalDate expectedCheckoutDate = null;
                    if (active != null) {
                        hasAdmission = true;
                        Long bedId = active.getFacilityId();
                        moveInDate = active.getFromDate();
                        monthlyRent = active.getMonthlyRent();
                        securityDeposit = active.getSecurityDeposit();
                        expectedCheckoutDate = active.getExpectedCheckoutDate();
                        Facility bed = bedMap.get(bedId);
                        bedName = bed != null ? bed.getFacilityName() : null;
                        Long roomId = bedToRoomId.get(bedId);
                        Facility room = roomId != null ? roomMap.get(roomId) : null;
                        roomName = room != null ? room.getFacilityName() : null;
                    }
                    return toResponse(person, bedName, roomName, null, null, hasAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate);
                })
                .filter(r -> r != null)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> listByProperty(Long organizationId, Long propertyId) {
        // Primary: tenants with an explicit property-level TENANT row.
        List<FacilityParty> explicit = facilityPartyRepository
                .findTenantsAtFacility(organizationId, propertyId, OccupancyRole.TENANT);

        // Union: org-level tenants who have any OCCUPANT bed (active OR historical) in this
        // property. This covers (a) tenants created globally and assigned via the bed-assign
        // flow with no property-level row, and (b) tenants now checked out (thru_date set).
        // Membership is resolved in a fixed set of batch queries — no per-tenant lookups.
        List<FacilityParty> orgRows = facilityPartyRepository
                .findTenantsAtFacility(organizationId, organizationId, OccupancyRole.TENANT);
        List<Long> orgPartyIds = orgRows.stream().map(FacilityParty::getPartyId).distinct().toList();
        List<FacilityParty> allOccupants = orgPartyIds.isEmpty() ? List.of()
                : facilityPartyRepository.findByOrganizationIdAndPartyIdInAndRoleTypeId(
                        organizationId, orgPartyIds, OccupancyRole.OCCUPANT);
        Map<Long, Long> bedToProperty = resolvePropertyIds(
                allOccupants.stream().map(FacilityParty::getFacilityId).toList());
        Set<Long> partiesInProperty = allOccupants.stream()
                .filter(occ -> propertyId.equals(bedToProperty.get(occ.getFacilityId())))
                .map(FacilityParty::getPartyId)
                .collect(Collectors.toSet());

        // Combine explicit + union, deduping by partyId (keep first occurrence).
        LinkedHashMap<Long, FacilityParty> byParty = new LinkedHashMap<>();
        for (FacilityParty fp : explicit) byParty.putIfAbsent(fp.getPartyId(), fp);
        for (FacilityParty fp : orgRows) {
            if (partiesInProperty.contains(fp.getPartyId())) byParty.putIfAbsent(fp.getPartyId(), fp);
        }
        log.info("Tenant list (by property): org={} property={} matched {} tenants",
                organizationId, propertyId, byParty.size());
        return buildTenantResponses(organizationId, new ArrayList<>(byParty.values()));
    }

    /**
     * Resolves each bed to its owning property (bed → room → floor → property) in three
     * batch queries, returning a bed-id → property-id map. Beds that don't resolve to a
     * property are omitted.
     */
    private Map<Long, Long> resolvePropertyIds(Collection<Long> bedFacilityIds) {
        List<Long> beds = bedFacilityIds.stream().filter(java.util.Objects::nonNull).distinct().toList();
        if (beds.isEmpty()) return Map.of();
        Map<Long, Long> bedToRoom = parentMap(beds);
        Map<Long, Long> roomToFloor = parentMap(bedToRoom.values());
        Map<Long, Long> floorToProperty = parentMap(roomToFloor.values());
        Map<Long, Long> bedToProperty = new HashMap<>();
        for (Long bed : beds) {
            Long room = bedToRoom.get(bed);
            Long floor = room != null ? roomToFloor.get(room) : null;
            Long property = floor != null ? floorToProperty.get(floor) : null;
            if (property != null) bedToProperty.put(bed, property);
        }
        return bedToProperty;
    }

    /** child-facility-id → parent-facility-id for a batch of children (active links only). */
    private Map<Long, Long> parentMap(Collection<Long> childIds) {
        List<Long> ids = childIds.stream().filter(java.util.Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) return Map.of();
        return facilityGroupMemberRepository.findByChildFacilityIdInAndThruDateIsNull(ids).stream()
                .collect(Collectors.toMap(
                        FacilityGroupMember::getChildFacilityId, FacilityGroupMember::getParentFacilityId, (a, b) -> a));
    }

    @Transactional(readOnly = true)
    public TenantResponse get(Long organizationId, Long partyId) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        String bedName = null;
        String roomName = null;
        boolean hasAdmission = false;
        Optional<FacilityParty> bedAssignment = facilityPartyRepository
                .findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, partyId, OccupancyRole.OCCUPANT);
        LocalDate moveInDate = null;
        BigDecimal monthlyRent = null;
        BigDecimal securityDeposit = null;
        LocalDate expectedCheckoutDate = null;
        Long currentBedFacilityId = null;
        Long currentPropertyId = null;
        String currentSharingType = null;
        if (bedAssignment.isPresent()) {
            hasAdmission = true;
            Long bedId = bedAssignment.get().getFacilityId();
            currentBedFacilityId = bedId;
            currentPropertyId = resolvePropertyId(bedId);
            currentSharingType = resolveSharingType(bedId);
            moveInDate = bedAssignment.get().getFromDate();
            monthlyRent = bedAssignment.get().getMonthlyRent();
            securityDeposit = bedAssignment.get().getSecurityDeposit();
            expectedCheckoutDate = bedAssignment.get().getExpectedCheckoutDate();
            bedName = facilityRepository.findById(bedId).map(Facility::getFacilityName).orElse(null);
            roomName = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId)
                    .stream().findFirst()
                    .flatMap(fgm -> facilityRepository.findById(fgm.getParentFacilityId()))
                    .map(Facility::getFacilityName).orElse(null);
        }

        // Temporary-stay state (a bed held with no billing).
        boolean inTemporaryStay = false;
        Long tempBedFacilityId = null;
        String tempBedName = null;
        boolean tempIsAllocation = false;
        LocalDate tempFromDate = null;
        LocalDate tempExpectedCheckoutDate = null;
        Optional<FacilityParty> tempStay = facilityPartyRepository
                .findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, partyId, OccupancyRole.TEMP_OCCUPANT);
        if (tempStay.isPresent()) {
            inTemporaryStay = true;
            tempBedFacilityId = tempStay.get().getFacilityId();
            tempBedName = facilityRepository.findById(tempBedFacilityId).map(Facility::getFacilityName).orElse(null);
            // No expected checkout ⇒ a Temporary Bed allocation (Case 2), which can be
            // made permanent. A day-wise Temporary Stay (Case 1) has a checkout and cannot.
            tempIsAllocation = tempStay.get().getExpectedCheckoutDate() == null;
            tempFromDate = tempStay.get().getFromDate();
            tempExpectedCheckoutDate = tempStay.get().getExpectedCheckoutDate();
            // Surface the sharing type from the temp bed so the UI can show it even
            // when there is no permanent admission.
            if (currentSharingType == null) {
                currentSharingType = resolveSharingType(tempBedFacilityId);
            }
            if (!hasAdmission) {
                // Holding tenant with no permanent bed: surface the temp property for the UI.
                currentPropertyId = resolvePropertyId(tempBedFacilityId);
            }
        }

        return toResponse(person, bedName, roomName, currentPropertyId, currentBedFacilityId, hasAdmission,
                moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate,
                currentSharingType, inTemporaryStay, tempBedFacilityId, tempBedName, tempIsAllocation,
                tempFromDate, tempExpectedCheckoutDate, false);
    }

    private String resolveSharingType(Long bedId) {
        return facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId)
                .stream().findFirst()
                .flatMap(fgm -> facilityRepository.findById(fgm.getParentFacilityId()))
                .map(Facility::getSharingType).orElse(null);
    }

    @Transactional
    public TenantResponse update(Long organizationId, Long partyId, TenantUpdateRequest request) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        applyFields(person, request);
        return toResponse(person, null, null, null, null, false, null, null, null, null);
    }

    @Transactional
    public TenantResponse patch(Long organizationId, Long partyId, TenantPatchRequest request) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        if (request.emergencyContactName() != null) person.setEmergencyContactName(request.emergencyContactName());
        if (request.emergencyContactMobile() != null) person.setEmergencyContactMobile(request.emergencyContactMobile());
        if (request.emergencyContactRelation() != null) person.setEmergencyContactRelation(request.emergencyContactRelation());
        if (request.employerName() != null) person.setEmployerName(request.employerName());
        if (request.designation() != null) person.setDesignation(request.designation());
        if (request.workAddress() != null) person.setWorkAddress(request.workAddress());
        return toResponse(person, null, null, null, null, false, null, null, null, null);
    }

    private void assertTenantInOrganization(Long organizationId, Long partyId) {
        facilityPartyRepository.findOrgMembership(organizationId, partyId, OccupancyRole.TENANT)
                .orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));
    }

    private void applyFields(Person person, TenantCreateRequest r) {
        person.setFullName(r.fullName());
        person.setMobileNumber(r.mobileNumber());
        person.setEmail(r.email());
        person.setGender(r.gender());
        person.setDateOfBirth(r.dateOfBirth());
        person.setAadhaarNumber(r.aadhaarNumber());
        person.setOccupation(r.occupation());
        person.setPermanentAddress(r.permanentAddress());
        person.setEmergencyContactName(r.emergencyContactName());
        person.setEmergencyContactMobile(r.emergencyContactMobile());
        person.setEmergencyContactRelation(r.emergencyContactRelation());
        person.setEmployerName(r.employerName());
        person.setDesignation(r.designation());
        person.setWorkAddress(r.workAddress());
        person.setHasVehicle(r.hasVehicle());
    }

    private void applyFields(Person person, TenantUpdateRequest r) {
        person.setFullName(r.fullName());
        person.setMobileNumber(r.mobileNumber());
        person.setEmail(r.email());
        person.setGender(r.gender());
        person.setDateOfBirth(r.dateOfBirth());
        person.setAadhaarNumber(r.aadhaarNumber());
        person.setOccupation(r.occupation());
        person.setPermanentAddress(r.permanentAddress());
        person.setEmergencyContactName(r.emergencyContactName());
        person.setEmergencyContactMobile(r.emergencyContactMobile());
        person.setEmergencyContactRelation(r.emergencyContactRelation());
        person.setEmployerName(r.employerName());
        person.setDesignation(r.designation());
        person.setWorkAddress(r.workAddress());
        person.setHasVehicle(r.hasVehicle());
    }

    /**
     * Merge-applies only the fields the Add Tenant form actually supplied — used when a
     * rejoining tenant is restored from the archive. A blank/null field is left untouched so
     * the stored profile (emergency contact, employment, …) survives the re-registration.
     */
    private void applyEnteredFields(Person person, TenantCreateRequest r) {
        if (notBlank(r.fullName())) person.setFullName(r.fullName().trim());
        if (notBlank(r.mobileNumber())) person.setMobileNumber(r.mobileNumber().trim());
        if (notBlank(r.email())) person.setEmail(r.email().trim());
        if (notBlank(r.gender())) person.setGender(r.gender());
        if (r.dateOfBirth() != null) person.setDateOfBirth(r.dateOfBirth());
        if (notBlank(r.aadhaarNumber())) person.setAadhaarNumber(r.aadhaarNumber().trim());
        if (notBlank(r.occupation())) person.setOccupation(r.occupation());
        if (notBlank(r.permanentAddress())) person.setPermanentAddress(r.permanentAddress());
        if (notBlank(r.emergencyContactName())) person.setEmergencyContactName(r.emergencyContactName());
        if (notBlank(r.emergencyContactMobile())) person.setEmergencyContactMobile(r.emergencyContactMobile());
        if (notBlank(r.emergencyContactRelation())) person.setEmergencyContactRelation(r.emergencyContactRelation());
        if (notBlank(r.employerName())) person.setEmployerName(r.employerName());
        if (notBlank(r.designation())) person.setDesignation(r.designation());
        if (notBlank(r.workAddress())) person.setWorkAddress(r.workAddress());
        // hasVehicle is a primitive — the form always states it, so it always applies.
        person.setHasVehicle(r.hasVehicle());
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    public TenantResponse toResponse(Person person, String currentBedName, String currentRoomName,
            Long currentPropertyId, Long currentBedFacilityId,
            boolean hasActiveAdmission, LocalDate moveInDate, BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate) {
        return toResponse(person, currentBedName, currentRoomName, currentPropertyId, currentBedFacilityId,
                hasActiveAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate,
                null, false, null, null, false, null, null, false);
    }

    /** Profile-only response carrying the restore flag (no bed/occupancy context). */
    public TenantResponse toResponse(Person person, boolean restoredFromArchive) {
        return toResponse(person, null, null, null, null, false, null, null, null, null,
                null, false, null, null, false, null, null, restoredFromArchive);
    }

    public TenantResponse toResponse(Person person, String currentBedName, String currentRoomName,
            Long currentPropertyId, Long currentBedFacilityId,
            boolean hasActiveAdmission, LocalDate moveInDate, BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate, String currentSharingType, boolean inTemporaryStay,
            Long tempBedFacilityId, String tempBedName, boolean tempIsAllocation,
            LocalDate tempFromDate, LocalDate tempExpectedCheckoutDate, boolean restoredFromArchive) {
        return new TenantResponse(
                person.getPartyId(),
                person.getFullName(),
                person.getMobileNumber(),
                person.getEmail(),
                person.getGender(),
                person.getDateOfBirth(),
                person.getAadhaarNumber(),
                person.getPermanentAddress(),
                person.getEmergencyContactName(),
                person.getEmergencyContactMobile(),
                person.getEmergencyContactRelation(),
                person.getEmployerName(),
                person.getDesignation(),
                person.getWorkAddress(),
                person.isHasVehicle(),
                currentBedName,
                currentRoomName,
                currentPropertyId,
                currentBedFacilityId,
                hasActiveAdmission,
                moveInDate,
                monthlyRent,
                securityDeposit,
                expectedCheckoutDate,
                currentSharingType,
                inTemporaryStay,
                tempBedFacilityId,
                tempBedName,
                tempIsAllocation,
                tempFromDate,
                tempExpectedCheckoutDate,
                restoredFromArchive
        );
    }

    private Long resolvePropertyId(Long bedId) {
        return facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId)
                .stream().findFirst()
                .flatMap(rgm -> facilityGroupMemberRepository
                        .findByChildFacilityIdAndThruDateIsNull(rgm.getParentFacilityId())
                        .stream().findFirst())
                .flatMap(fgm -> facilityGroupMemberRepository
                        .findByChildFacilityIdAndThruDateIsNull(fgm.getParentFacilityId())
                        .stream().findFirst())
                .map(pgm -> pgm.getParentFacilityId())
                .orElse(null);
    }
}
