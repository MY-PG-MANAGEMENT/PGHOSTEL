package com.pgmanager.complaint;

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
@Table(name = "complaint_status_history")
public class ComplaintStatusHistory extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "complaint_status_history_id")
    private Long complaintStatusHistoryId;

    @Column(name = "complaint_id", nullable = false)
    private Long complaintId;

    @Column(name = "from_status")
    private String fromStatus;

    @Column(name = "to_status", nullable = false)
    private String toStatus;

    @Column
    private String note;

    @Column(name = "changed_by_user_login_id")
    private Long changedByUserLoginId;
}
