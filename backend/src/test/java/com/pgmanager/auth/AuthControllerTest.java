package com.pgmanager.auth;

import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Auth endpoint contract tests via standalone MockMvc (no Spring Security / DB).
 */
class AuthControllerTest {

    private MockMvc mvc;
    private AuthService authService;

    @BeforeEach
    void setUp() {
        authService = mock(AuthService.class);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new AuthController(authService))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    @Test
    void registerOwnerReturns200ForValidBody() throws Exception {
        when(authService.registerOwner(any()))
                .thenReturn(new AuthResponse("access", "refresh", 1L, "OWNER", "Asha Rao"));

        mvc.perform(post("/api/auth/register-owner").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"9876543210\"," +
                                "\"username\":\"asha_rao\",\"password\":\"secret123\",\"organizationName\":\"Asha PG\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.roleTypeId").value("OWNER"));
    }

    @Test
    void registerOwnerRejectsBadMobile() throws Exception {
        mvc.perform(post("/api/auth/register-owner").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"12\"," +
                                "\"username\":\"asha_rao\",\"password\":\"secret123\",\"organizationName\":\"Asha PG\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false));
        verify(authService, never()).registerOwner(any());
    }

    @Test
    void registerOwnerRejectsShortPassword() throws Exception {
        mvc.perform(post("/api/auth/register-owner").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"9876543210\"," +
                                "\"username\":\"asha_rao\",\"password\":\"short\",\"organizationName\":\"Asha PG\"}"))
                .andExpect(status().isBadRequest());
        verify(authService, never()).registerOwner(any());
    }

    @Test
    void loginRejectsBlankCredentials() throws Exception {
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"\",\"password\":\"\"}"))
                .andExpect(status().isBadRequest());
        verify(authService, never()).login(any());
    }
}
