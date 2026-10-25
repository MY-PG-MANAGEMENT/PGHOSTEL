package com.pgmanager.whatsapp;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * WhatsApp settings, bound from {@code app.messaging.whatsapp.*}.
 *
 * <p><b>Phase 1 needs exactly one value.</b> Deep linking is unprovisioned by design — there is no
 * Meta app, no access token, no phone-number id and no business account id, so there is nothing here
 * to secure and nothing an operator must set up before the feature works. Keeping this class at a
 * single field is the honest reflection of that; Phase 2 is where the Cloud API credentials arrive.
 */
@Component
@ConfigurationProperties(prefix = "app.messaging.whatsapp")
@Getter
@Setter
public class WhatsAppProperties {

    /**
     * Country calling code prefixed onto a bare national number, digits only and no {@code +}.
     *
     * <p>Configuration rather than a constant because tenant mobiles are stored as bare 10-digit
     * numbers ({@code person.mobile_number}) with no country code anywhere in the schema, and this
     * is a multi-tenant product that will eventually be deployed outside India. A number that
     * already carries its own country code is left alone — see {@link PhoneNumberNormalizer}.
     */
    private String defaultCountryCode = "91";
}
