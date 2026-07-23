package com.pgmanager.security;

import com.pgmanager.common.exception.BadRequestException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

@Component
public class CurrentUser {
    public AppUserPrincipal principal() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !(authentication.getPrincipal() instanceof AppUserPrincipal principal)) {
            throw new BadRequestException("Authenticated user not available");
        }
        return principal;
    }

    public Long organizationId() {
        Long organizationId = principal().organizationId();
        if (organizationId == null) {
            throw new BadRequestException("Organization context not available");
        }
        return organizationId;
    }

    public Long userLoginId() {
        return principal().userLoginId();
    }

    /** The authenticated principal's party id (e.g. the tenant's person/party for the tenant portal). */
    public Long partyId() {
        return principal().partyId();
    }
}
