package com.pgmanager.auth;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
@Table(name = "user_login")
public class UserLogin extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_login_id")
    private Long userLoginId;

    @Column(name = "party_id", nullable = false)
    private Long partyId;

    @Column(nullable = false, unique = true)
    private String username;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(name = "role_type_id", nullable = false)
    private String roleTypeId;

    @Column(name = "organization_id")
    private Long organizationId;

    @Column(nullable = false)
    private String status = "ACTIVE";

    /** Why the login is INACTIVE (e.g. {@code CHECKED_OUT}); null while ACTIVE. */
    @Column(name = "disabled_reason")
    private String disabledReason;

    /** Forces a password change on next login (temp password abc@123 for auto-provisioned tenants). */
    @Column(name = "must_change_password", nullable = false)
    private boolean mustChangePassword = false;

    @Column(name = "last_login_at")
    private java.time.LocalDateTime lastLoginAt;
}
