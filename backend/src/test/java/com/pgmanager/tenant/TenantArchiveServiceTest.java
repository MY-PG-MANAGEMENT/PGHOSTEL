package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Guards on the archive ("delete tenant") path: an occupied tenant must never be
 * archivable (their dues and deposit are settled by checkout, not by hiding them), and the
 * bulk path must tally skips instead of failing the whole selection on one bad id.
 */
class TenantArchiveServiceTest {

    private static final long ORG = 1L;
    private static final long USER = 7L;
    private static final long PARTY = 100L;

    private JdbcTemplate jdbc;
    private AuditService auditService;
    private TenantLoginService tenantLoginService;
    private TenantArchiveService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        auditService = mock(AuditService.class);
        tenantLoginService = mock(TenantLoginService.class);
        service = new TenantArchiveService(jdbc, auditService, tenantLoginService);
    }

    /**
     * Routes the three COUNT(*) guards by their SQL: org-TENANT membership, active bed
     * (OCCUPANT / TEMP_OCCUPANT), and "already archived".
     */
    private void stubGuards(long orgTenantRows, long activeBeds, long archivedRows) {
        when(jdbc.queryForObject(anyString(), eq(Long.class), any(Object[].class))).thenAnswer(inv -> {
            String sql = inv.getArgument(0);
            if (sql.contains("FROM tenant_archive")) return archivedRows;
            if (sql.contains("role_type_id IN")) return activeBeds;
            return orgTenantRows;
        });
        Map<String, Object> snapshot = new HashMap<>();
        snapshot.put("full_name", "Asha Rao");
        snapshot.put("mobile_number", "9876543210");
        when(jdbc.queryForList(contains("FROM person"), any(Object[].class))).thenReturn(List.of(snapshot));
    }

    @Test
    void archiveOne_writesTheRowSnapshotAndKillsTheLogin() {
        stubGuards(1, 0, 0);

        service.archiveOne(ORG, USER, PARTY);

        // property_facility_id is null: this tenant never had a property row or a bed.
        verify(jdbc).update(contains("INSERT INTO tenant_archive"),
                eq(ORG), isNull(), eq(PARTY), eq("Asha Rao"), eq("9876543210"), any(), eq(USER), any(), any());
        verify(tenantLoginService).disableForArchive(ORG, PARTY);
        verify(auditService).log(eq(ORG), eq(USER), eq("TENANT_ARCHIVED"), eq("PARTY"), eq(PARTY), anyString());
    }

    @Test
    void archiveOne_rejectsATenantStillHoldingABed() {
        stubGuards(1, 1, 0);

        assertThatThrownBy(() -> service.archiveOne(ORG, USER, PARTY))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("Check them out");

        verify(jdbc, never()).update(contains("INSERT INTO tenant_archive"), any(Object[].class));
    }

    @Test
    void archiveOne_rejectsAPartyOutsideTheOrganization() {
        stubGuards(0, 0, 0);

        assertThatThrownBy(() -> service.archiveOne(ORG, USER, PARTY))
                .isInstanceOf(NotFoundException.class);
    }

    /** Archiving twice is a no-op, not an error — a retried tap must not 400. */
    @Test
    void archiveOne_isIdempotent() {
        stubGuards(1, 0, 1);

        service.archiveOne(ORG, USER, PARTY);

        verify(jdbc, never()).update(contains("INSERT INTO tenant_archive"), any(Object[].class));
    }

    @Test
    void archiveMany_talliesSkipsInsteadOfFailing() {
        // 100 archivable · 101 still occupying a bed · 102 not a tenant of this org.
        when(jdbc.queryForObject(anyString(), eq(Long.class), any(Object[].class))).thenAnswer(inv -> {
            String sql = inv.getArgument(0);
            List<Object> args = Arrays.asList(inv.getArguments());
            if (sql.contains("FROM tenant_archive")) return 0L;
            if (sql.contains("role_type_id IN")) return args.contains(101L) ? 1L : 0L;
            return args.contains(102L) ? 0L : 1L;
        });
        when(jdbc.queryForList(contains("FROM person"), any(Object[].class))).thenReturn(List.of());

        Map<String, Object> summary = service.archiveMany(ORG, USER, List.of(100L, 101L, 102L, 100L));

        assertThat(summary).containsEntry("total", 3)          // the repeated 100 is de-duped
                .containsEntry("archived", 1)
                .containsEntry("skippedActive", 1)
                .containsEntry("skippedNotFound", 1)
                .containsEntry("skippedAlreadyArchived", 0);
    }

    @Test
    void unarchive_isFalseAndSilentWhenTheTenantWasNotArchived() {
        when(jdbc.update(contains("DELETE FROM tenant_archive"), any(Object[].class))).thenReturn(0);

        assertThat(service.unarchive(ORG, USER, PARTY)).isFalse();
        verify(auditService, never()).log(any(), any(), anyString(), any(), any(), any());
    }

    @Test
    void unarchive_removesTheRowAndAudits() {
        when(jdbc.update(contains("DELETE FROM tenant_archive"), any(Object[].class))).thenReturn(1);

        assertThat(service.unarchive(ORG, USER, PARTY)).isTrue();
        verify(auditService).log(eq(ORG), eq(USER), eq("TENANT_RESTORED"), eq("PARTY"), eq(PARTY), anyString());
    }

    @Test
    void findArchivedPartyByMobile_isEmptyWhenNothingMatches() {
        when(jdbc.queryForList(anyString(), eq(Long.class), any(Object[].class))).thenReturn(List.of());

        assertThat(service.findArchivedPartyByMobile(ORG, "9876543210")).isEmpty();
        assertThat(service.findArchivedPartyByMobile(ORG, "  ")).isEmpty();
    }

    @Test
    void findArchivedPartyByMobile_returnsTheMostRecentlyArchivedParty() {
        when(jdbc.queryForList(anyString(), eq(Long.class), any(Object[].class))).thenReturn(List.of(PARTY));

        assertThat(service.findArchivedPartyByMobile(ORG, "9876543210")).contains(PARTY);
    }
}
