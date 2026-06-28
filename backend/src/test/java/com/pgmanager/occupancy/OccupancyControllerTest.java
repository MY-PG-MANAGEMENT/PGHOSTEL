package com.pgmanager.occupancy;

import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import java.sql.Date;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Controller tests for occupancy endpoints, focused on the expected-checkout
 * date rule (JdbcTemplate mocked) and checkout delegation. No DB / Docker.
 */
class OccupancyControllerTest {

    private MockMvc mvc;
    private OccupancyService occupancyService;
    private JdbcTemplate jdbc;

    @BeforeEach
    void setUp() {
        occupancyService = mock(OccupancyService.class);
        jdbc = mock(JdbcTemplate.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.organizationId()).thenReturn(1L);
        lenient().when(currentUser.userLoginId()).thenReturn(7L);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new OccupancyController(occupancyService, currentUser, jdbc))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    @Test
    void expectedCheckoutRejectsInvalidDateFormat() throws Exception {
        mvc.perform(put("/api/occupancy/expected-checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":1,\"expectedCheckoutDate\":\"not-a-date\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("Invalid date format")));
    }

    @Test
    void expectedCheckoutRejectsDateOnOrAfterNextPaymentDate() throws Exception {
        // Active assignment exists; a far-future checkout date must be rejected.
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class)))
                .thenReturn(List.of(Map.of("from_date", Date.valueOf(LocalDate.of(2026, 1, 1)))));

        mvc.perform(put("/api/occupancy/expected-checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":1,\"expectedCheckoutDate\":\"2030-12-31\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("before next payment date")));
    }

    @Test
    void expectedCheckoutReturns404WhenNoActiveAssignment() throws Exception {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class))).thenReturn(List.of());
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(0);

        mvc.perform(put("/api/occupancy/expected-checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":1,\"expectedCheckoutDate\":\"2026-06-29\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void expectedCheckoutClearsDateWhenBlank() throws Exception {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        mvc.perform(put("/api/occupancy/expected-checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":1,\"expectedCheckoutDate\":null}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));
    }

    @Test
    void checkoutDelegatesToService() throws Exception {
        when(occupancyService.checkout(anyLong(), anyLong(), any()))
                .thenReturn(new OccupancyResponse(1L, 1L, 50L, "OCCUPANT",
                        LocalDate.of(2026, 1, 1), LocalDate.of(2026, 6, 30), null, null, null));

        mvc.perform(post("/api/occupancy/checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":1}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.facilityId").value(50))
                .andExpect(jsonPath("$.data.roleTypeId").value("OCCUPANT"));
    }

    @Test
    void checkoutRejectsMissingPartyId() throws Exception {
        mvc.perform(post("/api/occupancy/checkout").contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
        verify(occupancyService, never()).checkout(anyLong(), anyLong(), any());
    }
}
