package com.pgmanager.selfcheckin;

import com.pgmanager.common.util.HashUtil;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Signs / verifies the (org, property) pair embedded in the public self check-in URL so
 * that a QR link cannot be forged for an arbitrary organization/property by guessing ids.
 * A {@code propertyId} of 0 means "organization-level" (no property scope).
 */
@Service
public class SelfCheckinTokenService {

    private final String secret;
    private final String publicBaseUrl;

    public SelfCheckinTokenService(
            @Value("${app.security.jwt-secret}") String secret,
            @Value("${app.public-base-url}") String publicBaseUrl) {
        this.secret = secret;
        this.publicBaseUrl = publicBaseUrl.endsWith("/")
                ? publicBaseUrl.substring(0, publicBaseUrl.length() - 1)
                : publicBaseUrl;
    }

    public String sign(long organizationId, long propertyId) {
        return HashUtil.sha256("self-checkin:" + organizationId + ":" + propertyId + ":" + secret)
                .substring(0, 16);
    }

    public boolean verify(long organizationId, long propertyId, String sig) {
        return sig != null && sign(organizationId, propertyId).equals(sig);
    }

    /** Signed relative path — the app prepends its own backend origin so the QR host
     *  always matches the server the app is actually talking to. */
    public String pathFor(long organizationId, long propertyId) {
        return "/api/public/self-checkin/" + organizationId + "/" + propertyId + "/"
                + sign(organizationId, propertyId);
    }

    public String linkFor(long organizationId, long propertyId) {
        return publicBaseUrl + pathFor(organizationId, propertyId);
    }
}
