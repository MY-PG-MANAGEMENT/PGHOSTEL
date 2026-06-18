package com.pgmanager.rent;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface RentRepository extends JpaRepository<Rent, Long> {
    List<Rent> findByOrganizationIdOrderByRentMonthDesc(Long organizationId);

    Optional<Rent> findByRentIdAndOrganizationId(Long rentId, Long organizationId);

}
