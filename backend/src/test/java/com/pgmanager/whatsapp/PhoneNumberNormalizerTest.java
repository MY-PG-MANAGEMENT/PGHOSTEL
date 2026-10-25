package com.pgmanager.whatsapp;

import com.pgmanager.common.exception.BadRequestException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code person.mobile_number} is free text in practice — typed on the Add Tenant form, imported
 * from CSV, or submitted by a tenant on the public self check-in page. A malformed number sends the
 * owner to WhatsApp's "invalid number" screen — or, worse, to a stranger's chat — so anything we
 * cannot confidently normalise has to be refused here rather than guessed at.
 */
class PhoneNumberNormalizerTest {

    private static final String IN = "91";

    @ParameterizedTest(name = "\"{0}\" -> {1}")
    @CsvSource({
            // The common case: a bare 10-digit Indian mobile gets the country code.
            "9876543210,919876543210",
            // Formatting owners actually type.
            "'+91 98765 43210',919876543210",
            "'+919876543210',919876543210",
            "'98765-43210',919876543210",
            "'(0) 9876543210',919876543210",
            // Domestic trunk prefix — a dialling instruction, not part of the number.
            "09876543210,919876543210",
            // 00 is an international dialling prefix, so what follows already has a country code.
            "00919876543210,919876543210",
            // Already E.164 with the code included.
            "919876543210,919876543210",
            // A non-Indian number keeps its own country code rather than being re-prefixed.
            "'+14155552671',14155552671",
    })
    void normalisesToE164Digits(String raw, String expected) {
        assertThat(PhoneNumberNormalizer.toE164Digits(raw, IN)).isEqualTo(expected);
    }

    @Test
    void neverReturnsAPlusOrAnySeparator() {
        assertThat(PhoneNumberNormalizer.toE164Digits("+91 98765-43210", IN)).containsOnlyDigits();
    }

    // ── Refusals ────────────────────────────────────────────────────────────────

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void aMissingNumberSaysSoInTheOwnersLanguage(String raw) {
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits(raw, IN))
                .isInstanceOf(BadRequestException.class)
                .hasMessage(PhoneNumberNormalizer.MISSING);
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "12345",          // too short to be anything
            "98765",          // half a mobile
            "not-a-number",   // no digits at all
            "9876543210987654321", // over E.164's 15-digit ceiling
    })
    void anUnusableNumberIsRefusedRatherThanGuessedAt(String raw) {
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits(raw, IN))
                .isInstanceOf(BadRequestException.class);
    }

    /**
     * No country calling code begins with 0, so "+0..." cannot be dialled however it is padded.
     * Worth its own case because the trunk-prefix stripping is skipped for explicit "+" input.
     */
    @Test
    void anExplicitlyInternationalNumberStartingWithZeroIsRefused() {
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits("+0919876543210", IN))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void aBareNationalNumberWithNoConfiguredCountryCodeIsRefused() {
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits("9876543210", ""))
                .isInstanceOf(BadRequestException.class);
    }

    /**
     * Only two messages reach the owner, and both are shown verbatim on the invoice sheet as the
     * reason the WhatsApp action is unavailable — so they are contract, not incidental error text.
     */
    @Test
    void onlyTwoDistinctMessagesAreEverProduced() {
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits(null, IN))
                .hasMessage(PhoneNumberNormalizer.MISSING);
        assertThatThrownBy(() -> PhoneNumberNormalizer.toE164Digits("12345", IN))
                .hasMessage(PhoneNumberNormalizer.INVALID);
    }
}
