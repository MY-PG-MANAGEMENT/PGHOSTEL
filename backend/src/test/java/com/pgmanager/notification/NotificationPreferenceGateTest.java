package com.pgmanager.notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.startsWith;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The owner-facing Notification Settings toggles must actually suppress delivery.
 *
 * <p>{@code notifyOwners} used to select every OWNER/PROPERTY_MANAGER/MANAGER login
 * unconditionally and never consult {@code notification_preference}. The settings
 * screen wrote {@code IN_APP} preference rows that no code path ever read, so
 * switching a category off updated a row and the notifications kept coming.
 *
 * <p>Delivery is now <b>opt-in</b>: the recipient query inner-joins an enabled
 * {@code IN_APP} row, so a category with no row is not delivered. That has to match
 * {@code NotificationController.preferences()}, which defaults the switch to off.
 */
class NotificationPreferenceGateTest {

    private JdbcTemplate jdbc;
    private NotificationService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        service = new NotificationService(jdbc, mock(OrganizationChannelService.class));
    }

    /** Stub the recipient lookup (the only queryForList(String, Class, Object...) call). */
    private void stubRecipients(List<Long> partyIds) {
        when(jdbc.queryForList(anyString(), eq(Long.class), any(Object[].class))).thenReturn(partyIds);
        // The notification id now comes back from RETURNING on the INSERT itself, so the insert
        // is a queryForObject rather than an update followed by a LAST_INSERT_ID() read.
        lenient().when(jdbc.queryForObject(startsWith("INSERT INTO notification("), eq(Long.class), any(Object[].class)))
                .thenReturn(77L);
    }

    private String recipientSql() {
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForList(sql.capture(), eq(Long.class), any(Object[].class));
        return sql.getValue();
    }

    @Test
    void deliversToOwnersWhoHaveTheCategorySwitchedOn() {
        stubRecipients(List.of(11L, 12L));

        service.notifyOwners(1L, "RENT_REMINDER", "Rent due", "Body", "RENT", 5L, false);

        // One notification row, then one recipient row per opted-in party.
        verify(jdbc).queryForObject(anyString(), eq(Long.class), eq(1L), eq("RENT_REMINDER"), eq("Rent due"),
                eq("Body"), eq("RENT"), eq(5L), eq("NORMAL"), any());
        verify(jdbc).update(anyString(), eq(77L), eq(11L), eq(false));
        verify(jdbc).update(anyString(), eq(77L), eq(12L), eq(false));
    }

    @Test
    void writesNothingAtAllWhenNobodyOptedIn() {
        stubRecipients(List.of());

        service.notifyOwners(1L, "RENT_REMINDER", "Rent due", "Body", "RENT", 5L, false);

        // Not merely "no recipients" — the notification row itself must not be
        // written, or the table fills with rows nobody can ever read.
        verify(jdbc, never()).update(anyString(), any(), any(), any(), any(), any(), any(), any(), any());
        verify(jdbc, never()).update(anyString(), any(), any(), any());
    }

    /**
     * The gate lives in SQL, so these assertions are what stop a future edit from
     * quietly reverting to "notify everyone".
     */
    @Test
    void therecipientQueryGatesOnAnEnabledInAppPreference() {
        stubRecipients(List.of(11L));

        service.notifyOwners(1L, "CHECK_IN", "T", "B", "PARTY", 2L, false);

        String sql = recipientSql();
        assertThat(sql)
                .as("must join the preference table, not select every login")
                .contains("JOIN notification_preference");
        assertThat(sql)
                .as("opt-in: only an explicitly enabled row counts")
                .contains("np.enabled = TRUE");
        assertThat(sql)
                .as("a LEFT join would let a missing row through and default back to on")
                .doesNotContain("LEFT JOIN notification_preference");
        assertThat(sql)
                .as("one party can hold several user_login rows")
                .contains("DISTINCT");
    }

    @Test
    void theGateIsPerCategoryAndPerChannel() {
        stubRecipients(List.of(11L));

        service.notifyOwners(1L, "PAYMENT_RECEIPT", "T", "B", "PAYMENT", 3L, false);

        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).queryForList(anyString(), eq(Long.class), args.capture());
        // Switching one category off must not silence the others, and the owner
        // screen writes IN_APP rows — matching on the wrong channel would read the
        // tenant email preferences instead.
        assertThat(args.getValue()).containsExactly("PAYMENT_RECEIPT", "IN_APP", 1L);
    }

    @Test
    void importantNotificationsAreGatedToo() {
        stubRecipients(List.of());

        service.notifyOwners(1L, "RENT_REMINDER", "T", "B", "RENT", 9L, true);

        // "important" raises the priority; it is not a licence to bypass the toggle.
        verify(jdbc, never()).update(anyString(), any(), any(), any(), any(), any(), any(), any(), any());
    }
}
