package com.pgmanager.payment;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;

public interface PaymentRepository extends JpaRepository<Payment, Long> {
    List<Payment> findByOrganizationIdOrderByPaymentDateDesc(Long organizationId);

    @Query("SELECT COALESCE(SUM(p.amount), 0) FROM Payment p WHERE p.organizationId = :orgId")
    BigDecimal sumAmountByOrganizationId(@Param("orgId") Long organizationId);
}
