package com.pgmanager.notice;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

@Getter
@Setter
@Entity
@Table(name = "notice")
public class Notice extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "notice_id")
    private Long noticeId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    /** Null = org-wide; otherwise scoped to a property. */
    @Column(name = "property_facility_id")
    private Long propertyFacilityId;

    @Column(name = "notice_type", nullable = false)
    private String noticeType = NoticeType.ANNOUNCEMENT;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String body;

    @Column(name = "published_at", nullable = false)
    private LocalDateTime publishedAt;

    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @Column(name = "created_by_user_login_id")
    private Long createdByUserLoginId;

    @Column(nullable = false)
    private boolean active = true;
}
