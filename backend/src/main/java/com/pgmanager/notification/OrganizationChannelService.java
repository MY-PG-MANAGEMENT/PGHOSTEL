package com.pgmanager.notification;

import com.pgmanager.common.cache.CacheConfig;
import com.pgmanager.common.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Per-organization on/off control for outbound messaging channels
 * ({@code EMAIL} and future {@code WHATSAPP}), stored as
 * {@code organization_feature} rows keyed by the matching
 * {@code feature_master.feature_code} (seeded in V2/V20).
 *
 * <p>Channels are <b>opt-in</b>: a channel counts as enabled only when an
 * {@code organization_feature} row exists with {@code enabled = TRUE}. A missing
 * row (or {@code enabled = FALSE}) means the channel is disabled for that org.
 * Super admins toggle these from the admin panel; the owner app reads them to
 * decide whether to expose channel-specific features (e.g. email notifications).
 */
@Service
@RequiredArgsConstructor
public class OrganizationChannelService {

    /** The messaging channels an org can toggle, in display order. */
    public static final List<String> CHANNELS = List.of("EMAIL", "WHATSAPP");

    private final JdbcTemplate jdbc;

    /** Returns each channel code mapped to whether it is enabled for the org. */
    public Map<String, Boolean> channels(Long organizationId) {
        Map<String, Boolean> result = new LinkedHashMap<>();
        for (String code : CHANNELS) {
            result.put(code, enabled(organizationId, code));
        }
        return result;
    }

    /**
     * True only when an enabled {@code organization_feature} row exists for the code.
     * Cached per {@code org:CODE} (see {@link CacheConfig#ORG_FEATURES}) — this is read
     * on every notification/notice send. The null-org fast path is not cached
     * ({@code condition}), and evicted by {@link #setChannel}.
     */
    @Cacheable(cacheNames = CacheConfig.ORG_FEATURES,
            key = "#organizationId + ':' + #code",
            condition = "#organizationId != null && #code != null")
    public boolean enabled(Long organizationId, String code) {
        if (organizationId == null) return false;
        // NOTE: organization_feature is aliased `orgf`, not `of`. That was forced under MySQL 8
        // (`of` is reserved there, so it was a syntax error); PostgreSQL accepts it, but the
        // alias stays — renaming it across every query buys nothing and `of` reads worse.
        Boolean value = jdbc.query(
                "SELECT orgf.enabled FROM organization_feature orgf " +
                "JOIN feature_master fm ON fm.feature_id = orgf.feature_id " +
                "WHERE orgf.organization_id = ? AND fm.feature_code = ?",
                rs -> rs.next() ? rs.getBoolean(1) : Boolean.FALSE,
                organizationId, code);
        return Boolean.TRUE.equals(value);
    }

    /**
     * Enable/disable a channel for an org (upsert); returns the full channel map.
     * Evicts the cached {@code org:CODE} flag so the next {@link #enabled} read is fresh.
     * The key is normalized to upper-case to match how {@link #enabled} is called.
     */
    @CacheEvict(cacheNames = CacheConfig.ORG_FEATURES,
            key = "#organizationId + ':' + (#code == null ? '' : #code.trim().toUpperCase())")
    public Map<String, Boolean> setChannel(Long organizationId, String code, boolean enabled) {
        String norm = code == null ? "" : code.trim().toUpperCase();
        if (!CHANNELS.contains(norm)) {
            throw new BadRequestException("channel must be one of " + CHANNELS);
        }
        Long featureId = featureId(norm);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update(
                "INSERT INTO organization_feature(organization_id,feature_id,enabled,created_at,updated_at) " +
                "VALUES(?,?,?,?,?) " +
                "ON CONFLICT (organization_id,feature_id) " +
                "DO UPDATE SET enabled=EXCLUDED.enabled,updated_at=EXCLUDED.updated_at",
                organizationId, featureId, enabled, now, now);
        return channels(organizationId);
    }

    private Long featureId(String code) {
        List<Long> ids = jdbc.queryForList(
                "SELECT feature_id FROM feature_master WHERE feature_code=?", Long.class, code);
        if (ids.isEmpty()) throw new BadRequestException("Unknown feature code: " + code);
        return ids.get(0);
    }
}
