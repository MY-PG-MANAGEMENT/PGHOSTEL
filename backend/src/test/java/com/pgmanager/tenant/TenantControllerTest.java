package com.pgmanager.tenant;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Controller-contract tests via standalone MockMvc: exercises @Valid handling
 * and delegation without loading Spring Security or a database (no Docker needed).
 */
class TenantControllerTest {

    private MockMvc mvc;
    private TenantService tenantService;
    private final ObjectMapper json = new ObjectMapper();

    @BeforeEach
    void setUp() {
        tenantService = mock(TenantService.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        when(currentUser.organizationId()).thenReturn(1L);
        when(currentUser.userLoginId()).thenReturn(7L);

        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();

        mvc = MockMvcBuilders.standaloneSetup(new TenantController(tenantService, currentUser))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    private TenantResponse sampleResponse() {
        return new TenantResponse(100L, "Asha Rao", "9876543210", null, null, null, null, null,
                null, null, null, null, null, null, null, null, null, null, false, null, null, null, null,
                null, false, null, null);
    }

    @Test
    void createReturns200ForValidBody() throws Exception {
        when(tenantService.create(anyLong(), anyLong(), any())).thenReturn(sampleResponse());

        mvc.perform(post("/api/tenants").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"9876543210\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.fullName").value("Asha Rao"));
    }

    @Test
    void createRejectsBlankName() throws Exception {
        mvc.perform(post("/api/tenants").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"\",\"mobileNumber\":\"9876543210\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false));
        verify(tenantService, never()).create(anyLong(), anyLong(), any());
    }

    @Test
    void createRejectsInvalidMobile() throws Exception {
        mvc.perform(post("/api/tenants").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"123\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false));
        verify(tenantService, never()).create(anyLong(), anyLong(), any());
    }
}
