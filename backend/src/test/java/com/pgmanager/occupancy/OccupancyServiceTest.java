package com.pgmanager.occupancy;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.facility.FacilityGroupMember;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedTransferRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.TransferResult;
import com.pgmanager.pricing.PropertySharingPrice;
import com.pgmanager.pricing.PropertySharingPriceRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Critical-path unit tests for bed assignment / checkout. Pure Mockito.
 */
@ExtendWith(MockitoExtension.class)
class OccupancyServiceTest {

    private static final long ORG = 1L;
    private static final long USER = 7L;
    private static final long PARTY = 100L;
    private static final long BED = 50L;

    @Mock FacilityPartyRepository facilityPartyRepository;
    @Mock FacilityRepository facilityRepository;
    @Mock FacilityGroupMemberRepository facilityGroupMemberRepository;
    @Mock PropertySharingPriceRepository sharingPriceRepository;
    @Mock ScheduledBedTransferRepository scheduledTransferRepository;
    @Mock AuditService auditService;
    @Mock NotificationService notificationService;

    @InjectMocks OccupancyService service;

    private FacilityGroupMember member(long parentId) {
        FacilityGroupMember m = new FacilityGroupMember();
        m.setParentFacilityId(parentId);
        return m;
    }

    private Facility roomWith(long id, String sharingType) {
        Facility f = bedWithId(id, FacilityType.ROOM);
        f.setSharingType(sharingType);
        return f;
    }

    private PropertySharingPrice price(String rent, String deposit) {
        PropertySharingPrice p = new PropertySharingPrice();
        p.setMonthlyRent(new BigDecimal(rent));
        p.setSecurityDeposit(new BigDecimal(deposit));
        return p;
    }

    private BedAssignRequest assignReq() {
        return new BedAssignRequest(PARTY, BED, LocalDate.of(2026, 1, 1),
                new BigDecimal("6000"), new BigDecimal("6000"), null);
    }

    private Facility bed(String type) {
        return bedWithId(BED, type);
    }

    private Facility bedWithId(long id, String type) {
        Facility f = new Facility();
        f.setFacilityId(id);
        f.setOrganizationId(ORG);
        f.setFacilityTypeId(type);
        return f;
    }

    private void stubTenantAndBedValid() {
        when(facilityPartyRepository.findOrgMembership(ORG, PARTY, OccupancyRole.TENANT))
                .thenReturn(Optional.of(new FacilityParty()));
        when(facilityRepository.findByFacilityIdAndOrganizationId(BED, ORG))
                .thenReturn(Optional.of(bed(FacilityType.BED)));
    }

    @Test
    void assignRejectsTenantOutsideOrganization() {
        when(facilityPartyRepository.findOrgMembership(ORG, PARTY, OccupancyRole.TENANT))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.assign(ORG, USER, assignReq()))
                .isInstanceOf(NotFoundException.class)
                .hasMessageContaining("Tenant not found");
    }

    @Test
    void assignRejectsMissingBed() {
        when(facilityPartyRepository.findOrgMembership(ORG, PARTY, OccupancyRole.TENANT))
                .thenReturn(Optional.of(new FacilityParty()));
        when(facilityRepository.findByFacilityIdAndOrganizationId(BED, ORG)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.assign(ORG, USER, assignReq()))
                .isInstanceOf(NotFoundException.class)
                .hasMessageContaining("Bed not found");
    }

    @Test
    void assignRejectsFacilityThatIsNotABed() {
        when(facilityPartyRepository.findOrgMembership(ORG, PARTY, OccupancyRole.TENANT))
                .thenReturn(Optional.of(new FacilityParty()));
        when(facilityRepository.findByFacilityIdAndOrganizationId(BED, ORG))
                .thenReturn(Optional.of(bed(FacilityType.PROPERTY)));

        assertThatThrownBy(() -> service.assign(ORG, USER, assignReq()))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("not a bed");
    }

    @Test
    void assignRejectsWhenTenantAlreadyHasActiveBed() {
        stubTenantAndBedValid();
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(new FacilityParty()));

        assertThatThrownBy(() -> service.assign(ORG, USER, assignReq()))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("already has an active bed");
    }

    @Test
    void assignRejectsWhenBedAlreadyOccupied() {
        stubTenantAndBedValid();
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());
        when(facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                ORG, BED, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(new FacilityParty()));

        assertThatThrownBy(() -> service.assign(ORG, USER, assignReq()))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("already occupied");
    }

    @Test
    void assignHappyPathSavesOccupancyAndNotifies() {
        stubTenantAndBedValid();
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());
        when(facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                ORG, BED, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(BED))
                .thenReturn(List.of()); // no parent chain -> property membership skipped
        when(facilityPartyRepository.save(any(FacilityParty.class))).thenAnswer(inv -> {
            FacilityParty fp = inv.getArgument(0);
            fp.setFacilityPartyId(900L);
            return fp;
        });

        OccupancyResponse res = service.assign(ORG, USER, assignReq());

        assertThat(res.facilityId()).isEqualTo(BED);
        assertThat(res.monthlyRent()).isEqualByComparingTo("6000");
        verify(notificationService).notifyCheckIn(ORG, PARTY, BED);
        verify(auditService).log(eq(ORG), eq(USER), eq("BED_ASSIGNED"), any(), any(), any());
    }

    @Test
    void checkoutRejectsWhenNoActiveOccupancy() {
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.checkout(ORG, USER, new CheckoutRequest(PARTY, null)))
                .isInstanceOf(NotFoundException.class)
                .hasMessageContaining("Active occupancy not found");
    }

    @Test
    void transferRejectsWhenNoActiveOccupancy() {
        when(facilityRepository.findByFacilityIdAndOrganizationId(60L, ORG))
                .thenReturn(Optional.of(bedWithId(60L, FacilityType.BED)));
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.transfer(ORG, USER,
                new BedTransferRequest(PARTY, 60L, null, new BigDecimal("6000"))))
                .isInstanceOf(NotFoundException.class)
                .hasMessageContaining("Active occupancy not found");
    }

    @Test
    void transferRejectsWhenNewBedOccupied() {
        when(facilityRepository.findByFacilityIdAndOrganizationId(60L, ORG))
                .thenReturn(Optional.of(bedWithId(60L, FacilityType.BED)));
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(new FacilityParty()));
        when(facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                ORG, 60L, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(new FacilityParty()));

        assertThatThrownBy(() -> service.transfer(ORG, USER,
                new BedTransferRequest(PARTY, 60L, null, new BigDecimal("6000"))))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("already occupied");
    }

    @Test
    void transferSameSharingAppliesImmediately() {
        when(facilityRepository.findByFacilityIdAndOrganizationId(60L, ORG))
                .thenReturn(Optional.of(bedWithId(60L, FacilityType.BED)));
        FacilityParty active = new FacilityParty();
        active.setFacilityId(BED);
        active.setFromDate(LocalDate.of(2026, 1, 2));
        active.setMonthlyRent(new BigDecimal("6000"));
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(active));
        when(facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                ORG, 60L, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());
        // both rooms are the same sharing type → immediate move
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(BED)).thenReturn(List.of(member(500L)));
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(60L)).thenReturn(List.of(member(600L)));
        when(facilityRepository.findById(500L)).thenReturn(Optional.of(roomWith(500L, "2")));
        when(facilityRepository.findById(600L)).thenReturn(Optional.of(roomWith(600L, "2")));
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(600L)).thenReturn(List.of());
        when(facilityPartyRepository.save(any(FacilityParty.class))).thenAnswer(inv -> {
            FacilityParty fp = inv.getArgument(0);
            fp.setFacilityPartyId(901L);
            return fp;
        });

        TransferResult res = service.transfer(ORG, USER,
                new BedTransferRequest(PARTY, 60L, LocalDate.of(2026, 7, 1), new BigDecimal("6500")));

        assertThat(res.mode()).isEqualTo("APPLIED");
        assertThat(res.occupancy().facilityId()).isEqualTo(60L);
        assertThat(res.occupancy().monthlyRent()).isEqualByComparingTo("6500");
        // billing cycle preserved: new row keeps the original move-in date
        assertThat(res.occupancy().fromDate()).isEqualTo(LocalDate.of(2026, 1, 2));
        // old occupancy ended the day before the transfer
        assertThat(active.getThruDate()).isEqualTo(LocalDate.of(2026, 6, 30));
    }

    @Test
    void transferDifferentSharingSchedulesAtNextCycle() {
        when(facilityRepository.findByFacilityIdAndOrganizationId(60L, ORG))
                .thenReturn(Optional.of(bedWithId(60L, FacilityType.BED)));
        FacilityParty active = new FacilityParty();
        active.setFacilityId(BED);
        active.setFromDate(LocalDate.of(2026, 1, 2));
        active.setMonthlyRent(new BigDecimal("4000"));
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(active));
        when(facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                ORG, 60L, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());
        // current sharing "4", target sharing "3" → scheduled
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(BED)).thenReturn(List.of(member(500L)));
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(60L)).thenReturn(List.of(member(600L)));
        when(facilityRepository.findById(500L)).thenReturn(Optional.of(roomWith(500L, "4")));
        when(facilityRepository.findById(600L)).thenReturn(Optional.of(roomWith(600L, "3")));
        // resolvePropertyId(60): room600 → floor700 → property800
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(600L)).thenReturn(List.of(member(700L)));
        when(facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(700L)).thenReturn(List.of(member(800L)));
        when(sharingPriceRepository.findByOrganizationIdAndPropertyFacilityIdAndSharingType(ORG, 800L, "3"))
                .thenReturn(Optional.of(price("5000", "5000")));
        when(scheduledTransferRepository.save(any(ScheduledBedTransfer.class))).thenAnswer(inv -> {
            ScheduledBedTransfer s = inv.getArgument(0);
            s.setScheduledBedTransferId(77L);
            return s;
        });

        TransferResult res = service.transfer(ORG, USER,
                new BedTransferRequest(PARTY, 60L, null, null));

        assertThat(res.mode()).isEqualTo("SCHEDULED");
        assertThat(res.scheduled().toBedFacilityId()).isEqualTo(60L);
        assertThat(res.scheduled().newMonthlyRent()).isEqualByComparingTo("5000");
        // the swap has NOT happened yet — current occupancy is untouched
        assertThat(active.getThruDate()).isNull();
        verify(facilityPartyRepository, never()).save(any(FacilityParty.class));
    }

    @Test
    void checkoutSetsThruDate() {
        FacilityParty active = new FacilityParty();
        active.setFacilityPartyId(900L);
        active.setFacilityId(BED);
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, PARTY, OccupancyRole.OCCUPANT)).thenReturn(Optional.of(active));

        LocalDate when = LocalDate.of(2026, 6, 30);
        OccupancyResponse res = service.checkout(ORG, USER, new CheckoutRequest(PARTY, when));

        assertThat(res.thruDate()).isEqualTo(when);
        assertThat(active.getThruDate()).isEqualTo(when);
    }
}
