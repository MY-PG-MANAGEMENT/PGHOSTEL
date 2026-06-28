package com.pgmanager.payment;

import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.payment.dto.PaymentDtos.PaymentResponse;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import java.math.BigDecimal;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PaymentControllerTest {

    private MockMvc mvc;
    private PaymentService paymentService;

    @BeforeEach
    void setUp() {
        paymentService = mock(PaymentService.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        when(currentUser.organizationId()).thenReturn(1L);
        when(currentUser.userLoginId()).thenReturn(7L);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new PaymentController(paymentService, currentUser))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    @Test
    void createReturns200ForValidBody() throws Exception {
        when(paymentService.create(anyLong(), anyLong(), any()))
                .thenReturn(new PaymentResponse(1L, null, 10L, new BigDecimal("100"), "CASH", null, null, null));

        mvc.perform(post("/api/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":10,\"amount\":100,\"paymentMode\":\"CASH\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));
    }

    @Test
    void createRejectsZeroAmount() throws Exception {
        mvc.perform(post("/api/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":10,\"amount\":0,\"paymentMode\":\"CASH\"}"))
                .andExpect(status().isBadRequest());
        verify(paymentService, never()).create(anyLong(), anyLong(), any());
    }

    @Test
    void createRejectsMissingParty() throws Exception {
        mvc.perform(post("/api/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":100,\"paymentMode\":\"CASH\"}"))
                .andExpect(status().isBadRequest());
        verify(paymentService, never()).create(anyLong(), anyLong(), any());
    }

    @Test
    void createRejectsBlankPaymentMode() throws Exception {
        mvc.perform(post("/api/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"partyId\":10,\"amount\":100,\"paymentMode\":\"\"}"))
                .andExpect(status().isBadRequest());
        verify(paymentService, never()).create(anyLong(), anyLong(), any());
    }
}
