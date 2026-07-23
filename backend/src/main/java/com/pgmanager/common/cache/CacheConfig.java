package com.pgmanager.common.cache;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.CachingConfigurer;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.interceptor.CacheErrorHandler;
import org.springframework.cache.support.NoOpCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext.SerializationPair;
import org.springframework.data.redis.serializer.StringRedisSerializer;

/**
 * Central caching configuration for the backend, backed by Redis.
 *
 * <h2>Design goals</h2>
 * <ul>
 *   <li><b>Opt-in.</b> Controlled by {@code app.cache.enabled} (default {@code false}).
 *       When off, a {@link NoOpCacheManager} is wired so {@code @Cacheable} methods
 *       simply execute normally — the app boots and runs identically with no Redis
 *       server present (important for local dev / existing deployments).</li>
 *   <li><b>Fail-open.</b> A {@link CacheErrorHandler} swallows Redis errors (timeouts,
 *       connection drops, serialization issues) and logs them, so a Redis outage
 *       degrades to direct DB reads instead of failing requests.</li>
 *   <li><b>Multi-tenant safe.</b> Every cached method keys on {@code organizationId}
 *       (see the {@code @Cacheable} SpEL keys on the annotated services). Cache names
 *       here only set TTLs; org isolation lives in the key.</li>
 *   <li><b>Transaction aware.</b> Cache writes/evictions are deferred until the
 *       surrounding {@code @Transactional} commits, so a rolled-back write never
 *       poisons the cache.</li>
 * </ul>
 *
 * <p>To add a new cache: declare a constant here, give it a TTL in
 * {@link #redisCacheManager(RedisConnectionFactory)}, then annotate the read method
 * with {@code @Cacheable(cacheNames = CacheConfig.X, key = "...organizationId...")}
 * and every mutating method with a matching {@code @CacheEvict}.
 */
@Configuration
@EnableCaching
public class CacheConfig implements CachingConfigurer {

    private static final Logger log = LoggerFactory.getLogger(CacheConfig.class);

    /** Per-org messaging/feature toggles ({@code organization_feature}); key {@code org:CODE}. */
    public static final String ORG_FEATURES = "orgFeatures";

    /** Per-property sharing-price list ({@code property_sharing_price}); key {@code org:propertyId}. */
    public static final String SHARING_PRICES = "sharingPrices";

    /** Facility hierarchy tree per org (structure only); key {@code org}. Rarely changes. */
    public static final String FACILITY_TREE = "facilityTree";

    /**
     * Occupancy-reflecting read models. These mirror live bed occupancy, so they are
     * evicted <b>wholesale</b> ({@code allEntries=true}) on every occupancy/structure
     * write entry point (see the {@code @CacheEvict}s on OccupancyService / TenantService.create
     * / OccupancyController.setExpectedCheckout / FacilityService / BulkUpload). Wholesale
     * eviction is used deliberately: it removes any chance of a key-mismatch leaving a bed
     * shown as vacant when it is actually occupied.
     */
    public static final String ROOM_SUMMARY = "roomSummary";
    public static final String PROPERTY_STATS = "propertyStats";
    public static final String VACANT_BEDS = "vacantBeds";
    public static final String TEMP_STAYS = "tempStays";

    /** Default TTL for caches that do not override it. */
    private static final Duration DEFAULT_TTL = Duration.ofMinutes(10);

    @Bean
    @ConditionalOnProperty(name = "app.cache.enabled", havingValue = "true")
    CacheManager redisCacheManager(RedisConnectionFactory connectionFactory) {
        RedisCacheConfiguration defaults = RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(DEFAULT_TTL)
                .disableCachingNullValues()
                .prefixCacheNameWith("pgm:cache:")
                .serializeKeysWith(SerializationPair.fromSerializer(new StringRedisSerializer()))
                .serializeValuesWith(SerializationPair.fromSerializer(new GenericJackson2JsonRedisSerializer()));

        Map<String, RedisCacheConfiguration> perCache = new HashMap<>();
        perCache.put(ORG_FEATURES, defaults.entryTtl(Duration.ofMinutes(30)));
        perCache.put(SHARING_PRICES, defaults.entryTtl(Duration.ofMinutes(30)));
        perCache.put(FACILITY_TREE, defaults.entryTtl(Duration.ofMinutes(60)));
        // Occupancy read models: evicted on every occupancy write, so TTL is only a backstop.
        perCache.put(ROOM_SUMMARY, defaults.entryTtl(Duration.ofMinutes(15)));
        perCache.put(PROPERTY_STATS, defaults.entryTtl(Duration.ofMinutes(15)));
        perCache.put(VACANT_BEDS, defaults.entryTtl(Duration.ofMinutes(15)));
        perCache.put(TEMP_STAYS, defaults.entryTtl(Duration.ofMinutes(15)));

        log.info("Redis cache manager ENABLED (caches={}, default TTL={})", perCache.keySet(), DEFAULT_TTL);
        return RedisCacheManager.builder(connectionFactory)
                .cacheDefaults(defaults)
                .withInitialCacheConfigurations(perCache)
                .transactionAware()
                .build();
    }

    @Bean
    @ConditionalOnProperty(name = "app.cache.enabled", havingValue = "false", matchIfMissing = true)
    CacheManager noOpCacheManager() {
        log.info("Caching DISABLED (app.cache.enabled=false) — using NoOpCacheManager");
        return new NoOpCacheManager();
    }

    /** Never let a Redis hiccup break a request: log and fall through to the source. */
    @Override
    public CacheErrorHandler errorHandler() {
        return new CacheErrorHandler() {
            @Override
            public void handleCacheGetError(RuntimeException e, Cache cache, Object key) {
                log.warn("Cache GET failed [{}::{}] — serving from source ({})", cache.getName(), key, e.toString());
            }

            @Override
            public void handleCachePutError(RuntimeException e, Cache cache, Object key, Object value) {
                log.warn("Cache PUT failed [{}::{}] ({})", cache.getName(), key, e.toString());
            }

            @Override
            public void handleCacheEvictError(RuntimeException e, Cache cache, Object key) {
                log.warn("Cache EVICT failed [{}::{}] ({})", cache.getName(), key, e.toString());
            }

            @Override
            public void handleCacheClearError(RuntimeException e, Cache cache) {
                log.warn("Cache CLEAR failed [{}] ({})", cache.getName(), e.toString());
            }
        };
    }
}
