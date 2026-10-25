package com.pgmanager.whatsapp;

import com.pgmanager.common.exception.BadRequestException;

/**
 * Turns a stored mobile number into the digits-only E.164 form a {@code wa.me} link needs.
 *
 * <p>Tenants are captured through several paths — the Add Tenant form, the CSV bulk upload
 * and the public self check-in page — so {@code person.mobile_number} is a free-text
 * VARCHAR(20) in practice: {@code 9876543210}, {@code +91 98765 43210},
 * {@code 091-9876543210} and {@code 0919876543210} all occur. {@code wa.me} wants a country code
 * and nothing else — no {@code +}, no spaces, no punctuation — and it does not validate for us: a
 * malformed number opens WhatsApp on an "invalid number" screen or on a stranger's chat. So this
 * normalises up front and <b>refuses</b> what it cannot make sense of.
 *
 * <p>Unchanged by the Phase 1/Phase 2 split: the Cloud API's {@code to} field takes the same form.
 */
public final class PhoneNumberNormalizer {

    /**
     * Shortest and longest an E.164 subscriber number can be, country code included.
     * ITU-T E.164 caps the total at 15 digits; the floor guards against a truncated entry
     * being padded with a country code and looking plausible.
     */
    private static final int MIN_E164_DIGITS = 10;
    private static final int MAX_E164_DIGITS = 15;

    /** A bare Indian-style national number: 10 digits, first digit 6-9. */
    private static final int NATIONAL_DIGITS = 10;

    /**
     * The two messages an owner may see. Kept as constants because the invoice sheet shows them
     * verbatim as the reason the WhatsApp action is unavailable, so they are part of the contract
     * rather than incidental error text. Deliberately only two: "no number on file" is something the
     * owner can fix by editing the tenant, while every flavour of unparseable number is one problem
     * as far as they are concerned, and enumerating them would only invite guessing at the format.
     */
    public static final String MISSING = "WhatsApp number is not available for this tenant.";
    public static final String INVALID = "Invalid WhatsApp number.";

    private PhoneNumberNormalizer() {
    }

    /**
     * @param raw                the number as stored on {@code person.mobile_number}
     * @param defaultCountryCode digits-only calling code applied when {@code raw} carries none
     * @return digits only, country code first, ready to be sent as Meta's {@code to} field
     * @throws BadRequestException with a message safe to show the owner
     */
    public static String toE164Digits(String raw, String defaultCountryCode) {
        if (raw == null || raw.isBlank()) {
            throw new BadRequestException(MISSING);
        }

        boolean explicitlyInternational = raw.trim().startsWith("+");
        String digits = digitsOnly(raw);
        if (digits.isEmpty()) {
            throw new BadRequestException(INVALID);
        }

        String countryCode = digitsOnly(defaultCountryCode);

        if (!explicitlyInternational) {
            // A single leading 0 is the Indian domestic trunk prefix, and 00 is an
            // international dialling prefix. Both are dialling instructions, not part of the
            // number, and neither belongs in E.164.
            if (digits.startsWith("00")) {
                digits = digits.substring(2);
                explicitlyInternational = true;
            } else if (digits.startsWith("0")) {
                digits = digits.replaceFirst("^0+", "");
            }
        }

        if (digits.length() == NATIONAL_DIGITS && !explicitlyInternational) {
            // The common case: a bare 10-digit mobile. Prefix the configured country code.
            if (countryCode.isEmpty()) {
                throw new BadRequestException(INVALID);
            }
            digits = countryCode + digits;
        }

        if (digits.length() < MIN_E164_DIGITS || digits.length() > MAX_E164_DIGITS) {
            throw new BadRequestException(INVALID);
        }
        // A leading zero here means we were handed something like "+0..." — no country code
        // starts with 0, so this cannot be dialled however it is padded.
        if (digits.startsWith("0")) {
            throw new BadRequestException(INVALID);
        }
        return digits;
    }

    private static String digitsOnly(String value) {
        if (value == null) return "";
        StringBuilder out = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c >= '0' && c <= '9') out.append(c);
        }
        return out.toString();
    }
}
