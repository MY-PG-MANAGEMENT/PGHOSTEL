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

    private String email;

    private String gender;

    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    @Column(name = "aadhaar_number")
    private String aadhaarNumber;

    private String occupation;

    @Column(name = "company_name")
    private String companyName;

    @Column(name = "employer_name")
    private String employerName;

    private String designation;

    @Column(name = "work_address", length = 500)
    private String workAddress;

    @Column(name = "guardian_name")
    private String guardianName;

    @Column(name = "guardian_mobile_number")
    private String guardianMobileNumber;

    private String address;

    @Column(name = "permanent_address", length = 500)
    private String permanentAddress;

    @Column(name = "emergency_contact_name")
    private String emergencyContactName;

    @Column(name = "emergency_contact_mobile")
    private String emergencyContactMobile;

    @Column(name = "emergency_contact_relation")
    private String emergencyContactRelation;
}
