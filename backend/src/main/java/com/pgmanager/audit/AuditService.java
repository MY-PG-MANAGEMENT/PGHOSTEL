package com.pgmanager.audit;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuditService {
    private final AuditLogRepository auditLogRepository;

    public void log(Long organizationId, Long userLoginId, String action, String entityType, Object entityId, String details) {
        AuditLog log = new AuditLog();
        log.setOrganizationId(organizationId);
        log.setUserLoginId(userLoginId);
        log.setAction(action);
        log.setEntityType(entityType);
        log.setEntityId(entityId == null ? null : String.valueOf(entityId));
        log.setDetails(details);
        auditLogRepository.save(log);
    }
}
