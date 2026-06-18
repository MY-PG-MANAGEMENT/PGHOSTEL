package com.pgmanager.rent;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.rent.dto.RentDtos.RentCreateRequest;
import com.pgmanager.rent.dto.RentDtos.RentResponse;
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
@RequestMapping("/api/rents")
@RequiredArgsConstructor
public class RentController {
    private final RentService rentService;
    private final CurrentUser currentUser;

    @PostMapping
    ApiResponse<RentResponse> create(@Valid @RequestBody RentCreateRequest request) {
        return ApiResponse.ok("Rent created", rentService.create(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @GetMapping
    ApiResponse<List<RentResponse>> list() {
        return ApiResponse.ok(rentService.list(currentUser.organizationId()));
    }
}
