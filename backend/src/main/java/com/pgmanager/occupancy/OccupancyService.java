package com.pgmanager.occupancy;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedTransferRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.EndTempStayRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.ScheduledTransferResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.TempStayRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.TransferResult;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.pricing.PropertySharingPrice;
import com.pgmanager.pricing.PropertySharingPriceRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class OccupancyService {
    private static final Logger log = LoggerFactory.getLogger(OccupancyService.class);

    private final FacilityPartyRepository facilityPartyRepository;
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository facilityGroupMemberRepository;
    private final PropertySharingPriceRepository sharingPriceRepository;
    private final ScheduledBedTransferRepository scheduledTransferRepository;
    private final AuditService auditService;
    private final NotificationService notificationService;

    @Transactional
    public OccupancyResponse assign(Long organizationId, Long userLoginId, BedAssignRequest request) {
        LocalDate fromDate = request.fromDate() == null ? LocalDate.now() : request.fromDate();
        validateTenant(organizationId, request.partyId());
        validateBed(organizationId, request.bedFacilityId());
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).ifPresent(active -> {
            throw new BadRequestException("Tenant already has an active bed");
        });
        ensureBedAvailable(organizationId, request.bedFacilityId());

        BigDecimal effectiveRent = request.monthlyRent() != null
                ? request.monthlyRent()
                : resolveRent(organizationId, request.bedFacilityId());

        FacilityParty occupancy = new FacilityParty();
        occupancy.setOrganizationId(organizationId);
        occupancy.setFacilityId(request.bedFacilityId());
        occupancy.setPartyId(request.partyId());
        occupancy.setRoleTypeId(OccupancyRole.OCCUPANT);
        occupancy.setFromDate(fromDate);
        occupancy.setMonthlyRent(effectiveRent);
        occupancy.setSecurityDeposit(request.securityDeposit());
        occupancy.setExpectedCheckoutDate(request.expectedCheckoutDate());
        occupancy = facilityPartyRepository.save(occupancy);

        // Ensure the tenant also has a property-level TENANT membership row so they
        // appear in the property's tenant list even when created globally.
        ensurePropertyTenantMembership(organizationId, request.partyId(), request.bedFacilityId(), fromDate);

        auditService.log(organizationId, userLoginId, "BED_ASSIGNED", "FACILITY_PARTY", occupancy.getFacilityPartyId(), "Bed assigned");
        notificationService.notifyCheckIn(organizationId, request.partyId(), request.bedFacilityId());
        return toResponse(occupancy);
    }

    private void ensurePropertyTenantMembership(Long orgId, Long partyId, Long bedId, LocalDate fromDate) {
        Long propertyId = resolvePropertyId(bedId);
        if (propertyId == null) return;
        boolean exists = facilityPartyRepository
                .existsByOrganizationIdAndFacilityIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                        orgId, propertyId, partyId, OccupancyRole.TENANT);
        if (!exists) {
            FacilityParty propertyMembership = new FacilityParty();
            propertyMembership.setOrganizationId(orgId);
            propertyMembership.setFacilityId(propertyId);
            propertyMembership.setPartyId(partyId);
            propertyMembership.setRoleTypeId(OccupancyRole.TENANT);
            propertyMembership.setFromDate(fromDate);
            facilityPartyRepository.save(propertyMembership);
        }
    }

    private Long resolvePropertyId(Long bedId) {
        var bedParents = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId);
        if (bedParents.isEmpty()) return null;
        Long roomId = bedParents.get(0).getParentFacilityId();
        var roomParents = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(roomId);
        if (roomParents.isEmpty()) return null;
        Long floorId = roomParents.get(0).getParentFacilityId();
        var floorParents = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(floorId);
        if (floorParents.isEmpty()) return null;
        return floorParents.get(0).getParentFacilityId();
    }

    // ── Transfer ────────────────────────────────────────────────────────────────

    /**
     * Transfers a tenant to a new bed.
     * <ul>
     *   <li><b>Same sharing type</b> — applied immediately. The billing cycle (rent and
     *       the day-of-month the invoice falls due) is preserved by carrying the original
     *       move-in date onto the new occupancy row, so billing is unaffected.</li>
     *   <li><b>Different sharing type</b> — never applied mid-cycle. A pending
     *       {@link ScheduledBedTransfer} is created with an effective date equal to the
     *       tenant's next billing anniversary; the swap (and the new rent) only take
     *       effect from that date. The current month's invoice is untouched.</li>
     * </ul>
     */
    @Transactional
    public TransferResult transfer(Long organizationId, Long userLoginId, BedTransferRequest request) {
        validateBed(organizationId, request.newBedFacilityId());
        FacilityParty active = facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).orElseThrow(() -> new NotFoundException("Active occupancy not found"));

        if (request.newBedFacilityId().equals(active.getFacilityId())) {
            throw new BadRequestException("Tenant is already in this bed");
        }
        ensureBedAvailable(organizationId, request.newBedFacilityId());
        if (scheduledTransferRepository.existsByOrganizationIdAndPartyIdAndStatus(
                organizationId, request.partyId(), ScheduledBedTransfer.PENDING)) {
            throw new BadRequestException("A transfer is already scheduled for this tenant; cancel it first");
        }

        String currentSharing = resolveSharingType(active.getFacilityId());
        String newSharing = resolveSharingType(request.newBedFacilityId());
        boolean sameSharing = currentSharing != null && currentSharing.equals(newSharing);

        LocalDate today = LocalDate.now();

        if (sameSharing) {
            LocalDate transferDate = request.transferDate() == null ? today : request.transferDate();
            active.setThruDate(transferDate.minusDays(1));

            FacilityParty next = new FacilityParty();
            next.setOrganizationId(organizationId);
            next.setFacilityId(request.newBedFacilityId());
            next.setPartyId(request.partyId());
            next.setRoleTypeId(OccupancyRole.OCCUPANT);
            // Preserve the original move-in date so the billing cycle/day is unchanged.
            next.setFromDate(active.getFromDate());
            next.setMonthlyRent(request.monthlyRent() != null ? request.monthlyRent() : active.getMonthlyRent());
            next.setSecurityDeposit(active.getSecurityDeposit());
            next.setExpectedCheckoutDate(active.getExpectedCheckoutDate());
            next = facilityPartyRepository.save(next);

            ensurePropertyTenantMembership(organizationId, request.partyId(), request.newBedFacilityId(), next.getFromDate());
            auditService.log(organizationId, userLoginId, "BED_TRANSFERRED", "FACILITY_PARTY", next.getFacilityPartyId(),
                    "Bed transferred (same sharing, immediate)");
            return new TransferResult("APPLIED", toResponse(next), null);
        }

        // Different sharing → defer to the next billing anniversary.
        LocalDate effective = nextBillingAnniversaryAfter(active.getFromDate(), today);
        if (request.transferDate() != null && !request.transferDate().isEqual(effective)) {
            throw new BadRequestException("A sharing-type change can only take effect on the next billing date (" + effective + ")");
        }
        PropertySharingPrice newPrice = resolveSharingPrice(organizationId, request.newBedFacilityId()).orElse(null);
        BigDecimal newRent = request.monthlyRent() != null
                ? request.monthlyRent()
                : (newPrice != null ? newPrice.getMonthlyRent() : null);
        BigDecimal newDeposit = newPrice != null ? newPrice.getSecurityDeposit() : null;

        ScheduledBedTransfer scheduled = new ScheduledBedTransfer();
        scheduled.setOrganizationId(organizationId);
        scheduled.setPartyId(request.partyId());
        scheduled.setFromBedFacilityId(active.getFacilityId());
        scheduled.setToBedFacilityId(request.newBedFacilityId());
        scheduled.setEffectiveDate(effective);
        scheduled.setNewMonthlyRent(newRent);
        scheduled.setNewSecurityDeposit(newDeposit);
        scheduled.setStatus(ScheduledBedTransfer.PENDING);
        scheduled.setNote("Sharing change " + currentSharing + " → " + newSharing);
        scheduled = scheduledTransferRepository.save(scheduled);

        auditService.log(organizationId, userLoginId, "BED_TRANSFER_SCHEDULED", "SCHEDULED_BED_TRANSFER",
                scheduled.getScheduledBedTransferId(), "Bed transfer scheduled for " + effective);
        return new TransferResult("SCHEDULED", null, toScheduledResponse(scheduled));
    }

    /** Applies all pending scheduled transfers whose effective date has arrived. */
    @Transactional
    public int applyDueTransfers() {
        List<ScheduledBedTransfer> due = scheduledTransferRepository
                .findByStatusAndEffectiveDateLessThanEqual(ScheduledBedTransfer.PENDING, LocalDate.now());
        int applied = 0;
        for (ScheduledBedTransfer s : due) {
            try {
                FacilityParty active = facilityPartyRepository
                        .findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                                s.getOrganizationId(), s.getPartyId(), OccupancyRole.OCCUPANT)
                        .orElse(null);
                boolean targetTaken = isBedTaken(s.getOrganizationId(), s.getToBedFacilityId());
                if (active == null) {
                    s.setStatus(ScheduledBedTransfer.FAILED);
                    s.setNote("No active occupancy to transfer");
                    continue;
                }
                if (targetTaken) {
                    s.setStatus(ScheduledBedTransfer.FAILED);
                    s.setNote("Target bed was occupied before the transfer could apply");
                    continue;
                }
                active.setThruDate(s.getEffectiveDate().minusDays(1));

                FacilityParty next = new FacilityParty();
                next.setOrganizationId(s.getOrganizationId());
                next.setFacilityId(s.getToBedFacilityId());
                next.setPartyId(s.getPartyId());
                next.setRoleTypeId(OccupancyRole.OCCUPANT);
                next.setFromDate(s.getEffectiveDate());
                next.setMonthlyRent(s.getNewMonthlyRent());
                next.setSecurityDeposit(s.getNewSecurityDeposit());
                next.setExpectedCheckoutDate(active.getExpectedCheckoutDate());
                next = facilityPartyRepository.save(next);

                ensurePropertyTenantMembership(s.getOrganizationId(), s.getPartyId(), s.getToBedFacilityId(), s.getEffectiveDate());
                s.setStatus(ScheduledBedTransfer.APPLIED);
                auditService.log(s.getOrganizationId(), null, "BED_TRANSFER_APPLIED", "FACILITY_PARTY",
                        next.getFacilityPartyId(), "Scheduled bed transfer applied");
                applied++;
            } catch (Exception e) {
                log.warn("Failed to apply scheduled transfer {}: {}", s.getScheduledBedTransferId(), e.getMessage());
                s.setStatus(ScheduledBedTransfer.FAILED);
                s.setNote(e.getMessage());
            }
        }
        return applied;
    }

    @Transactional(readOnly = true)
    public List<ScheduledTransferResponse> pendingTransfers(Long organizationId, Long partyId) {
        return scheduledTransferRepository
                .findByOrganizationIdAndPartyIdAndStatus(organizationId, partyId, ScheduledBedTransfer.PENDING)
                .stream().map(this::toScheduledResponse).toList();
    }

    @Transactional
    public void cancelScheduledTransfer(Long organizationId, Long userLoginId, Long scheduledTransferId) {
        ScheduledBedTransfer s = scheduledTransferRepository
                .findByScheduledBedTransferIdAndOrganizationId(scheduledTransferId, organizationId)
                .orElseThrow(() -> new NotFoundException("Scheduled transfer not found"));
        if (!ScheduledBedTransfer.PENDING.equals(s.getStatus())) {
            throw new BadRequestException("Only a pending transfer can be cancelled");
        }
        s.setStatus(ScheduledBedTransfer.CANCELLED);
        auditService.log(organizationId, userLoginId, "BED_TRANSFER_CANCELLED", "SCHEDULED_BED_TRANSFER",
                scheduledTransferId, "Scheduled bed transfer cancelled");
    }

    // ── Temporary stay ────────────────────────────────────────────────────────────

    /**
     * Places a tenant in a bed on a temporary basis. No billing is created for the
     * temporary period; the bed is marked occupied (TEMP_OCCUPANT) so it cannot be
     * double-booked. End it with {@link #endTempStay} or convert it to a permanent
     * assignment via the make-permanent flow.
     */
    @Transactional
    public OccupancyResponse tempStay(Long organizationId, Long userLoginId, TempStayRequest request) {
        LocalDate fromDate = request.fromDate() == null ? LocalDate.now() : request.fromDate();
        validateTenant(organizationId, request.partyId());
        validateBed(organizationId, request.bedFacilityId());
        ensureBedAvailable(organizationId, request.bedFacilityId());
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId, request.partyId(), OccupancyRole.TEMP_OCCUPANT
        ).ifPresent(active -> {
            throw new BadRequestException("Tenant is already in a temporary stay");
        });

        FacilityParty temp = new FacilityParty();
        temp.setOrganizationId(organizationId);
        temp.setFacilityId(request.bedFacilityId());
        temp.setPartyId(request.partyId());
        temp.setRoleTypeId(OccupancyRole.TEMP_OCCUPANT);
        temp.setFromDate(fromDate);
        temp = facilityPartyRepository.save(temp);

        ensurePropertyTenantMembership(organizationId, request.partyId(), request.bedFacilityId(), fromDate);
        auditService.log(organizationId, userLoginId, "TEMP_STAY_STARTED", "FACILITY_PARTY", temp.getFacilityPartyId(),
                "Temporary stay started (no billing)");
        return toResponse(temp);
    }

    @Transactional
    public OccupancyResponse endTempStay(Long organizationId, Long userLoginId, EndTempStayRequest request) {
        LocalDate endDate = request.endDate() == null ? LocalDate.now() : request.endDate();
        FacilityParty temp = facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId, request.partyId(), OccupancyRole.TEMP_OCCUPANT
        ).orElseThrow(() -> new NotFoundException("No active temporary stay found"));
        temp.setThruDate(endDate);
        auditService.log(organizationId, userLoginId, "TEMP_STAY_ENDED", "FACILITY_PARTY", temp.getFacilityPartyId(),
                "Temporary stay ended");
        return toResponse(temp);
    }

    // ── Checkout / history ──────────────────────────────────────────────────────

    @Transactional
    public OccupancyResponse checkout(Long organizationId, Long userLoginId, CheckoutRequest request) {
        LocalDate checkoutDate = request.checkoutDate() == null ? LocalDate.now() : request.checkoutDate();
        FacilityParty active = facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).orElseThrow(() -> new NotFoundException("Active occupancy not found"));
        active.setThruDate(checkoutDate);
        // Drop any pending transfer — the tenant is leaving.
        scheduledTransferRepository
                .findByOrganizationIdAndPartyIdAndStatus(organizationId, request.partyId(), ScheduledBedTransfer.PENDING)
                .forEach(s -> { s.setStatus(ScheduledBedTransfer.CANCELLED); s.setNote("Tenant checked out"); });
        auditService.log(organizationId, userLoginId, "CHECKOUT", "FACILITY_PARTY", active.getFacilityPartyId(), "Tenant checked out");
        return toResponse(active);
    }

    @Transactional(readOnly = true)
    public boolean hasActiveOccupant(Long organizationId, Long partyId) {
        return facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId, partyId, OccupancyRole.OCCUPANT).isPresent();
    }

    @Transactional(readOnly = true)
    public List<OccupancyResponse> history(Long organizationId, Long partyId) {
        return facilityPartyRepository.findByOrganizationIdAndPartyIdOrderByFromDateDesc(organizationId, partyId).stream()
                .map(this::toResponse)
                .toList();
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────

    private void validateTenant(Long organizationId, Long partyId) {
        facilityPartyRepository.findOrgMembership(organizationId, partyId, OccupancyRole.TENANT)
                .orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));
    }

    private void validateBed(Long organizationId, Long bedFacilityId) {
        Facility bed = facilityRepository.findByFacilityIdAndOrganizationId(bedFacilityId, organizationId)
                .orElseThrow(() -> new NotFoundException("Bed not found"));
        if (!FacilityType.BED.equals(bed.getFacilityTypeId())) {
            throw new BadRequestException("Selected facility is not a bed");
        }
    }

    /** Throws if the bed is already occupied (permanent or temporary) or reserved by a pending transfer. */
    private void ensureBedAvailable(Long organizationId, Long bedFacilityId) {
        facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                organizationId, bedFacilityId, OccupancyRole.OCCUPANT
        ).ifPresent(o -> { throw new BadRequestException("Bed is already occupied"); });
        facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                organizationId, bedFacilityId, OccupancyRole.TEMP_OCCUPANT
        ).ifPresent(o -> { throw new BadRequestException("Bed is occupied by a temporary stay"); });
        if (scheduledTransferRepository.existsByToBedFacilityIdAndStatus(bedFacilityId, ScheduledBedTransfer.PENDING)) {
            throw new BadRequestException("Bed is reserved for an upcoming scheduled transfer");
        }
    }

    private boolean isBedTaken(Long organizationId, Long bedFacilityId) {
        return facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, bedFacilityId, OccupancyRole.OCCUPANT).isPresent()
                || facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, bedFacilityId, OccupancyRole.TEMP_OCCUPANT).isPresent();
    }

    /** The next occurrence of the move-in day-of-month strictly after {@code today}. */
    private LocalDate nextBillingAnniversaryAfter(LocalDate moveIn, LocalDate today) {
        int day = moveIn.getDayOfMonth();
        LocalDate candidate = today.withDayOfMonth(Math.min(day, today.lengthOfMonth()));
        if (!candidate.isAfter(today)) {
            LocalDate nextMonth = today.plusMonths(1);
            candidate = nextMonth.withDayOfMonth(Math.min(day, nextMonth.lengthOfMonth()));
        }
        return candidate;
    }

    private String resolveSharingType(Long bedFacilityId) {
        var bedParents = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedFacilityId);
        if (bedParents.isEmpty()) return null;
        Long roomId = bedParents.get(0).getParentFacilityId();
        return facilityRepository.findById(roomId).map(Facility::getSharingType).orElse(null);
    }

    private Optional<PropertySharingPrice> resolveSharingPrice(Long orgId, Long bedFacilityId) {
        var bedParents = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedFacilityId);
        if (bedParents.isEmpty()) return Optional.empty();
        Long roomId = bedParents.get(0).getParentFacilityId();

        Facility room = facilityRepository.findById(roomId).orElse(null);
        if (room == null || room.getSharingType() == null) return Optional.empty();

        Long propertyId = resolvePropertyId(bedFacilityId);
        if (propertyId == null) return Optional.empty();

        return sharingPriceRepository
                .findByOrganizationIdAndPropertyFacilityIdAndSharingType(orgId, propertyId, room.getSharingType());
    }

    private BigDecimal resolveRent(Long orgId, Long bedFacilityId) {
        return resolveSharingPrice(orgId, bedFacilityId).map(PropertySharingPrice::getMonthlyRent).orElse(null);
    }

    private OccupancyResponse toResponse(FacilityParty facilityParty) {
        return new OccupancyResponse(
                facilityParty.getFacilityPartyId(),
                facilityParty.getPartyId(),
                facilityParty.getFacilityId(),
                facilityParty.getRoleTypeId(),
                facilityParty.getFromDate(),
                facilityParty.getThruDate(),
                facilityParty.getMonthlyRent(),
                facilityParty.getSecurityDeposit(),
                facilityParty.getExpectedCheckoutDate()
        );
    }

    private ScheduledTransferResponse toScheduledResponse(ScheduledBedTransfer s) {
        return new ScheduledTransferResponse(
                s.getScheduledBedTransferId(), s.getPartyId(),
                s.getFromBedFacilityId(), s.getToBedFacilityId(),
                s.getEffectiveDate(), s.getNewMonthlyRent(), s.getNewSecurityDeposit(),
                s.getStatus(), s.getNote()
        );
    }
}
