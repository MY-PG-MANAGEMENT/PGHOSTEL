package com.pgmanager.payment;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.payment.dto.PaymentDtos.PaymentCreateRequest;
import com.pgmanager.payment.dto.PaymentDtos.PaymentResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/payments")
@RequiredArgsConstructor
public class PaymentController {
    private final PaymentService paymentService;
    private final CurrentUser currentUser;

    @PostMapping
    ApiResponse<PaymentResponse> create(@Valid @RequestBody PaymentCreateRequest request) {
        return ApiResponse.ok("Payment recorded", paymentService.create(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @GetMapping
    ApiResponse<List<PaymentResponse>> list() {
        return ApiResponse.ok(paymentService.list(currentUser.organizationId()));
    }
}
