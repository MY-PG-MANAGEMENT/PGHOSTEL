package com.pgmanager.notification;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    @GetMapping
    ApiResponse<Map<String, Object>> list(@RequestParam(defaultValue = "ACTIVE") String state,
                                          @RequestParam(defaultValue = "0") int page,
                                          @RequestParam(defaultValue = "25") int size) {
        AppUserPrincipal user = currentUser.principal();
        String stateClause = switch (state.toUpperCase()) {
            case "ARCHIVED" -> "nr.archived_at IS NOT NULL";
            case "UNREAD" -> "nr.archived_at IS NULL AND nr.read_at IS NULL";
            case "IMPORTANT" -> "nr.archived_at IS NULL AND nr.important=TRUE";
            default -> "nr.archived_at IS NULL";
        };
        String base = " FROM notification n JOIN notification_recipient nr ON nr.notification_id=n.notification_id " +
                "WHERE n.organization_id=? AND nr.party_id=? AND " + stateClause;
        Long total = jdbc.queryForObject("SELECT COUNT(*)" + base, Long.class, user.organizationId(), user.partyId());
        List<Map<String, Object>> items = jdbc.queryForList("SELECT n.notification_id,n.category_id,n.title,n.message,n.entity_type,n.entity_id," +
                        "n.priority,n.created_at,nr.read_at,nr.archived_at,nr.important" + base + " ORDER BY n.created_at DESC LIMIT ? OFFSET ?",
                user.organizationId(), user.partyId(), Math.min(Math.max(size, 1), 100), Math.max(page, 0) * Math.min(Math.max(size, 1), 100));
        return ApiResponse.ok(Map.of("items", items, "page", page, "size", size, "total", total == null ? 0 : total));
    }

    @GetMapping("/{notificationId}")
    ApiResponse<Map<String, Object>> detail(@PathVariable Long notificationId) {
        AppUserPrincipal user = currentUser.principal();
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT n.notification_id,n.category_id,n.title,n.message,n.entity_type,n.entity_id," +
                        "n.priority,n.created_at,nr.read_at,nr.archived_at,nr.important FROM notification n " +
                        "JOIN notification_recipient nr ON nr.notification_id=n.notification_id " +
                        "WHERE n.notification_id=? AND n.organization_id=? AND nr.party_id=?",
                notificationId, user.organizationId(), user.partyId());
        if (rows.isEmpty()) throw new NotFoundException("Notification not found");
        return ApiResponse.ok(rows.getFirst());
    }

    @PatchMapping("/{notificationId}/read")
    ApiResponse<Void> markRead(@PathVariable Long notificationId) {
        int count = jdbc.update("UPDATE notification_recipient nr JOIN notification n ON n.notification_id=nr.notification_id " +
                        "SET nr.read_at=COALESCE(nr.read_at,?) WHERE nr.notification_id=? AND nr.party_id=? AND n.organization_id=?",
                LocalDateTime.now(), notificationId, currentUser.principal().partyId(), currentUser.organizationId());
        if (count == 0) throw new NotFoundException("Notification not found");
        return ApiResponse.ok(null);
    }

    @PatchMapping("/{notificationId}/archive")
    ApiResponse<Void> archive(@PathVariable Long notificationId) {
        int count = jdbc.update("UPDATE notification_recipient nr JOIN notification n ON n.notification_id=nr.notification_id " +
                        "SET nr.archived_at=? WHERE nr.notification_id=? AND nr.party_id=? AND n.organization_id=?",
                LocalDateTime.now(), notificationId, currentUser.principal().partyId(), currentUser.organizationId());
        if (count == 0) throw new NotFoundException("Notification not found");
        return ApiResponse.ok(null);
    }

    @DeleteMapping("/archives")
    ApiResponse<Void> clearArchives() {
        jdbc.update("DELETE nr FROM notification_recipient nr JOIN notification n ON n.notification_id=nr.notification_id " +
                        "WHERE nr.party_id=? AND n.organization_id=? AND nr.archived_at IS NOT NULL",
                currentUser.principal().partyId(), currentUser.organizationId());
        return ApiResponse.ok(null);
    }

    @GetMapping("/preferences")
    ApiResponse<List<Map<String, Object>>> preferences() {
        return ApiResponse.ok(jdbc.queryForList("SELECT c.category_id,c.name,c.description,COALESCE(p.enabled,TRUE) enabled " +
                        "FROM notification_category c LEFT JOIN notification_preference p ON p.category_id=c.category_id " +
                        "AND p.party_id=? AND p.channel_type_id='IN_APP' WHERE c.active=TRUE ORDER BY c.name",
                currentUser.principal().partyId()));
    }

    @PatchMapping("/preferences")
    ApiResponse<List<Map<String, Object>>> updatePreferences(@RequestBody Map<String, Boolean> updates) {
        updates.forEach((category, enabled) -> jdbc.update("INSERT INTO notification_preference(party_id,category_id,channel_type_id,enabled,updated_at) " +
                        "VALUES(?,?,'IN_APP',?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),updated_at=VALUES(updated_at)",
                currentUser.principal().partyId(), category, enabled, LocalDateTime.now()));
        return preferences();
    }

    @PostMapping
    ApiResponse<Map<String, Object>> create(@Valid @RequestBody CreateNotification request) {
        AppUserPrincipal user = currentUser.principal();
        jdbc.update("INSERT INTO notification(organization_id,category_id,title,message,entity_type,entity_id,priority,created_at) VALUES(?,?,?,?,?,?,?,?)",
                user.organizationId(), request.categoryId(), request.title(), request.message(), request.entityType(), request.entityId(),
                request.priority() == null ? "NORMAL" : request.priority(), LocalDateTime.now());
        Long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        jdbc.update("INSERT INTO notification_recipient(notification_id,party_id,important) VALUES(?,?,?)", id, user.partyId(), request.important());
        return ApiResponse.ok(Map.of("notificationId", id, "deliveryChannel", "IN_APP", "externalDelivery", "DISABLED"));
    }

    public record CreateNotification(@NotBlank String categoryId, @NotBlank String title, @NotBlank String message,
                                     String entityType, Long entityId, String priority, boolean important) {}
}
