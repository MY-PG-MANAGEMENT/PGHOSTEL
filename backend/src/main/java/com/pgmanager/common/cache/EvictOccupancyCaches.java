package com.pgmanager.common.cache;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import org.springframework.cache.annotation.CacheEvict;

/**
 * Composed shortcut for "this write changed bed occupancy — drop every occupancy-derived
 * read model". Put it on every method that mutates {@code facility_party} occupancy (bed
 * assign / transfer / temp-stay / checkout / expected-checkout / tenant creation).
 *
 * <p>Evicts {@link CacheConfig#ROOM_SUMMARY}, {@link CacheConfig#PROPERTY_STATS},
 * {@link CacheConfig#VACANT_BEDS} and {@link CacheConfig#TEMP_STAYS} wholesale
 * ({@code allEntries=true}) so there is no key to mismatch. Centralizing the cache set
 * here keeps every write site in sync — add a cache to the list once and all writers evict it.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@CacheEvict(cacheNames = {CacheConfig.ROOM_SUMMARY, CacheConfig.PROPERTY_STATS,
        CacheConfig.VACANT_BEDS, CacheConfig.TEMP_STAYS}, allEntries = true)
public @interface EvictOccupancyCaches {
}
