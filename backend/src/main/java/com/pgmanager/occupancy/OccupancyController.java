package com.pgmanager.occupancy;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedTransferRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/occupancy")
@RequiredArgsConstructor
public class OccupancyController {
    private final OccupancyService occupancyService;
    private final CurrentUser currentUser;

    @PostMapping("/assign-bed")
    ApiResponse<OccupancyResponse> assign(@Valid @RequestBody BedAssignRequest request) {
        return ApiResponse.ok("Bed assigned", occupancyService.assign(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @PostMapping("/transfer-bed")
    ApiResponse<OccupancyResponse> transfer(@Valid @RequestBody BedTransferRequest request) {
        return ApiResponse.ok("Bed transferred", occupancyService.transfer(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @PostMapping("/checkout")
    ApiResponse<OccupancyResponse> checkout(@Valid @RequestBody CheckoutRequest request) {
        return ApiResponse.ok("Checkout completed", occupancyService.checkout(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @GetMapping("/history/{partyId}")
    ApiResponse<List<OccupancyResponse>> history(@PathVariable Long partyId) {
        return ApiResponse.ok(occupancyService.history(currentUser.organizationId(), partyId));
    }
}
