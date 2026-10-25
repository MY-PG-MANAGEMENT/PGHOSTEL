package com.pgmanager.whatsapp;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.jackson.JacksonAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The reminder reaches the Flutter app as JSON nested inside the invoice-detail payload, and the
 * app keys off `reminder.canRemind`. Nothing else asserts that wire shape — the service tests work
 * on the record directly — so a serialisation problem (a record component Jackson cannot see, a
 * LocalDate written as an array) would show up only as a missing icon at runtime.
 */
class InvoiceReminderJsonTest {

    @Test
    void serialisesWithTheFieldNamesTheAppReads() {
        new ApplicationContextRunner()
                .withConfiguration(org.springframework.boot.autoconfigure.AutoConfigurations.of(JacksonAutoConfiguration.class))
                .run(context -> {
                    ObjectMapper mapper = context.getBean(ObjectMapper.class);
                    InvoiceReminder reminder = new InvoiceReminderService(new WhatsAppProperties())
                            .build(new InvoiceReminderService.ReminderInput(
                                    "Ravi Kumar", "9876543210", "Sri Lakshmi PG", List.of("MONTHLY_RENT"),
                                    LocalDate.now(), new BigDecimal("8500.00"), BigDecimal.ZERO, "PENDING"));

                    // Nested exactly as BillingController puts it on the response.
                    Map<String, Object> payload = new LinkedHashMap<>();
                    payload.put("invoice_id", 99L);
                    payload.put("reminder", reminder);

                    String json = mapper.writeValueAsString(payload);

                    assertThat(json).contains("\"reminder\":{");
                    assertThat(json).contains("\"canRemind\":true");
                    assertThat(json).contains("\"status\":\"DUE\"");
                    assertThat(json).contains("\"whatsappNumber\":\"919876543210\"");
                    // The card's line breaks must survive as JSON \n escapes — the app pastes the
                    // string straight into the wa.me link and never reflows it.
                    assertThat(json).contains("\"message\":\"Hi Ravi Kumar 👋\\n\\n");
                    assertThat(json).contains("🧾 Payment: Monthly Rent");
                    // A LocalDate must be an ISO string, not the [2026,8,8] array a bare
                    // ObjectMapper writes - the app parses it with DateTime.parse.
                    assertThat(json).contains("\"dueDate\":\"" + LocalDate.now() + "\"");
                });
    }
}
