package com.pgmanager.apilog;

import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.RoleType;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Captures the two things only the inside of the dispatch can see, and parks them on the
 * request for the filter to pick up.
 *
 * <p><b>Why this exists at all — the subtle bit.</b> The obvious implementation reads
 * {@code SecurityContextHolder} in the filter after {@code chain.doFilter} returns. That yields
 * null on every request. Spring Security's {@code SecurityContextHolderFilter} clears the
 * holder in its own {@code finally}, which runs <em>before</em> control unwinds to a filter
 * registered outside the security chain — and outside is exactly where our filter must sit to
 * observe 401/403 responses. So identity has to be snapshotted while the dispatch is still in
 * flight. {@code preHandle} is that moment.
 *
 * <p>The same applies to {@code controllerName}/{@code methodName}: the resolved
 * {@link HandlerMethod} exists only after {@code HandlerMapping} has run, which is inside
 * {@code DispatcherServlet}. A filter can never see it.
 *
 * <p>Requests that never reach a handler — an unmapped 404, or anything the security chain
 * rejects — simply skip this interceptor. Those rows keep null handler/identity columns, which
 * is the honest answer, and the filter still logs the hit.
 */
@Component
@RequiredArgsConstructor
public class ApiLogHandlerInterceptor implements HandlerInterceptor {

    private final ApiLogProperties properties;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        if (!properties.isEnabled()) return true;
        ApiLogContext context = ApiLogContext.from(request);
        if (context == null) return true;

        if (handler instanceof HandlerMethod handlerMethod) {
            context.setControllerName(handlerMethod.getBeanType().getSimpleName());
            context.setMethodName(handlerMethod.getMethod().getName());
        }
        applyIdentity(context);
        return true;
    }

    /**
     * Copies org/user/tenant off the authenticated principal. Anonymous traffic leaves all three
     * null, which is what the spec asks for and what makes "who hit this endpoint" queryable.
     */
    private void applyIdentity(ApiLogContext context) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) return;
        if (!(authentication.getPrincipal() instanceof AppUserPrincipal principal)) return;

        context.setOrganizationId(principal.organizationId());
        context.setUserLoginId(principal.userLoginId());
        // A "tenant" here is a resident party, so partyId only means tenantId for a TENANT login.
        // Setting it for an owner would make the column mean two different things.
        if (RoleType.TENANT.equals(principal.roleTypeId())) {
            context.setTenantId(principal.partyId());
        }
    }
}
