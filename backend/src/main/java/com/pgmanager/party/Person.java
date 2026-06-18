package com.pgmanager.party;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;

@Getter
@Setter
@Entity
@Table(name = "person")
public class Person extends BaseEntity {
    @Id
    @Column(name = "party_id")
    private Long partyId;

    @Column(name = "full_name", nullable = false)
    private String fullName;

    @Column(name = "mobile_number", nullable = false)
    private String mobileNumber;

    private String gender;

    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    @Column(name = "aadhaar_number")
    private String aadhaarNumber;

    private String occupation;

    @Column(name = "company_name")
    private String companyName;

    @Column(name = "guardian_name")
    private String guardianName;

    @Column(name = "guardian_mobile_number")
    private String guardianMobileNumber;

    private String address;
}
