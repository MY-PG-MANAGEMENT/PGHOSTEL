package com.pgmanager.notification;

import jakarta.mail.internet.MimeMessage;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

/**
 * Sends notifications over email as a branded HTML message (with a plain-text
 * fallback). Enabled only when {@code app.messaging.email.enabled=true} and an
 * SMTP {@link JavaMailSender} is configured (via {@code spring.mail.*}).
 *
 * <p>{@link JavaMailSender} is injected via {@link ObjectProvider} so the app
 * still boots when no SMTP host is configured — the channel simply reports
 * {@link #enabled()} = false and the dispatcher leaves messages queued.
 */
@Component
@RequiredArgsConstructor
public class EmailChannel implements MessageChannel {

    public static final String CHANNEL_ID = "EMAIL";
    private static final Logger log = LoggerFactory.getLogger(EmailChannel.class);

    private final ObjectProvider<JavaMailSender> mailSenderProvider;

    @Value("${app.messaging.email.enabled:false}")
    private boolean emailEnabled;
    @Value("${app.messaging.email.from:no-reply@pgmanager.app}")
    private String fromAddress;
    @Value("${app.messaging.email.from-name:PG Manager}")
    private String fromName;

    @Override
    public String channelId() {
        return CHANNEL_ID;
    }

    @Override
    public boolean enabled() {
        return emailEnabled && mailSenderProvider.getIfAvailable() != null;
    }

    @Override
    public String send(OutboundMessage m) {
        JavaMailSender sender = mailSenderProvider.getIfAvailable();
        if (sender == null) {
            throw new IllegalStateException("Email channel enabled but no JavaMailSender configured (set spring.mail.*)");
        }
        if (m.email() == null || m.email().isBlank()) {
            throw new IllegalArgumentException("Recipient has no email address");
        }
        try {
            MimeMessage mime = sender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(mime, true, "UTF-8");
            // Shared-relay model: the From address is always the platform's verified
            // sender (so SPF/DKIM/DMARC pass on the single relay). The organization's
            // identity is carried by the From display name and the Reply-To, so tenants
            // see the org's name and replies go straight to the org's own inbox.
            String senderName = (m.orgName() != null && !m.orgName().isBlank()) ? m.orgName() : fromName;
            helper.setFrom(fromAddress, senderName);
            if (m.orgEmail() != null && !m.orgEmail().isBlank()) {
                helper.setReplyTo(m.orgEmail());
                // CC the organization on every tenant message so the org keeps a
                // copy in its own inbox alongside the tenant's delivery.
                helper.setCc(m.orgEmail());
            }
            helper.setTo(m.email());
            helper.setSubject(m.subject());
            // text fallback + HTML body
            helper.setText(m.body() == null ? "" : m.body(), buildHtml(m));
            sender.send(mime);
            String id = mime.getMessageID();
            return id != null ? id : "sent";
        } catch (Exception e) {
            throw new RuntimeException("Email send failed: " + e.getMessage(), e);
        }
    }

    // ── HTML rendering ──────────────────────────────────────────────────────────

    private String buildHtml(OutboundMessage m) {
        String brand = (m.orgName() == null || m.orgName().isBlank()) ? "PG Manager" : escape(m.orgName());
        String heading = escape(m.subject());
        String bodyHtml = escape(m.body() == null ? "" : m.body()).replace("\n", "<br/>");
        return "<div style=\"margin:0;padding:24px 12px;background:#f3f4f6;\">"
                + "<div style=\"max-width:600px;margin:0 auto;font-family:Arial,Helvetica,sans-serif;color:#1f2937;\">"
                + "<div style=\"background:#4f46e5;padding:20px 24px;border-radius:12px 12px 0 0;\">"
                + "<div style=\"color:#ffffff;font-size:18px;font-weight:700;letter-spacing:.2px;\">" + brand + "</div>"
                + "</div>"
                + "<div style=\"background:#ffffff;border:1px solid #e5e7eb;border-top:none;border-radius:0 0 12px 12px;padding:24px;\">"
                + "<h2 style=\"margin:0 0 14px;font-size:17px;color:#111827;\">" + heading + "</h2>"
                + "<div style=\"font-size:14px;line-height:1.65;color:#374151;\">" + bodyHtml + "</div>"
                + "</div>"
                + "<div style=\"text-align:center;color:#9ca3af;font-size:12px;padding:16px 8px;\">"
                + "This is an automated message from " + brand + ". Please do not reply to this email."
                + "</div>"
                + "</div></div>";
    }

    private static String escape(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }
}
