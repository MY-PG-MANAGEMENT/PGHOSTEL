package com.pgmanager.pricing;

import com.pgmanager.common.cache.CacheConfig;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.pricing.dto.SharingPriceDtos.SharingPriceItem;
import com.pgmanager.pricing.dto.SharingPriceDtos.SharingPriceResponse;
import com.pgmanager.pricing.dto.SharingPriceDtos.SharingPriceUpsertRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class PropertySharingPriceService {

    private final PropertySharingPriceRepository repo;
    private final FacilityRepository facilityRepo;

    /**
     * Cached per {@code org:propertyId} (see {@link CacheConfig#SHARING_PRICES}); prices
     * change rarely (Price Master edits) and are evicted by {@link #upsert}. Note the
     * bed-assignment path ({@code OccupancyService.resolveRent}) reads the repository
     * directly, so it is always fresh and unaffected by this cache.
     */
    @Cacheable(cacheNames = CacheConfig.SHARING_PRICES, key = "#orgId + ':' + #propertyId")
    @Transactional(readOnly = true)
    public List<SharingPriceResponse> list(Long orgId, Long propertyId) {
        validateProperty(orgId, propertyId);
        return repo.findByOrganizationIdAndPropertyFacilityId(orgId, propertyId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @CacheEvict(cacheNames = CacheConfig.SHARING_PRICES, key = "#orgId + ':' + #propertyId")
    @Transactional
    public List<SharingPriceResponse> upsert(Long orgId, Long propertyId, SharingPriceUpsertRequest req) {
        validateProperty(orgId, propertyId);
        for (SharingPriceItem item : req.prices()) {
            PropertySharingPrice entity = repo
                    .findByOrganizationIdAndPropertyFacilityIdAndSharingType(orgId, propertyId, item.sharingType())
                    .orElseGet(PropertySharingPrice::new);
            entity.setOrganizationId(orgId);
            entity.setPropertyFacilityId(propertyId);
            entity.setSharingType(item.sharingType());
            entity.setMonthlyRent(item.monthlyRent());
            entity.setSecurityDeposit(item.securityDeposit() != null ? item.securityDeposit() : BigDecimal.ZERO);
            entity.setAcCharges(item.acCharges() != null ? item.acCharges() : BigDecimal.ZERO);
            entity.setPerDayPrice(item.perDayPrice() != null ? item.perDayPrice() : BigDecimal.ZERO);
            repo.save(entity);
        }
        return list(orgId, propertyId);
    }

    @Transactional(readOnly = true)
    public Optional<SharingPriceResponse> getByType(Long orgId, Long propertyId, String sharingType) {
        validateProperty(orgId, propertyId);
        return repo.findByOrganizationIdAndPropertyFacilityIdAndSharingType(orgId, propertyId, sharingType)
                .map(this::toResponse);
    }

    private void validateProperty(Long orgId, Long propertyId) {
        facilityRepo.findByFacilityIdAndOrganizationId(propertyId, orgId)
                .orElseThrow(() -> new NotFoundException("Property not found"));
    }

    private SharingPriceResponse toResponse(PropertySharingPrice p) {
        return new SharingPriceResponse(p.getSharingType(), p.getMonthlyRent(), p.getSecurityDeposit(),
                p.getAcCharges(), p.getPerDayPrice());
    }
}
