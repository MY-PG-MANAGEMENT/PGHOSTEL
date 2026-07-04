package com.pgmanager.selfcheckin;

import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.tenant.TenantService;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Optional;

/**
 * Public (no-auth) tenant self check-in. The owner shows a QR that opens
 * {@code GET /{orgId}/{propertyId}/{sig}} on the tenant's phone; the tenant fills the form
 * and {@code POST}s it, creating a tenant in that organization (and property, when
 * {@code propertyId != 0}). The signature ties the link to one org/property so the ids
 * cannot be swapped.
 */
@RestController
@RequestMapping("/api/public/self-checkin")
@RequiredArgsConstructor
public class PublicSelfCheckinController {

    private final SelfCheckinTokenService tokenService;
    private final TenantService tenantService;
    private final FacilityRepository facilityRepository;

    private record Target(Facility org, Facility property) {}

    @GetMapping(value = "/{orgId}/{propertyId}/{sig}", produces = MediaType.TEXT_HTML_VALUE)
    ResponseEntity<String> form(@PathVariable Long orgId, @PathVariable Long propertyId,
                                @PathVariable String sig) {
        Optional<Target> target = resolve(orgId, propertyId, sig);
        if (target.isEmpty()) {
            return ResponseEntity.status(404).contentType(MediaType.TEXT_HTML).body(page(
                    "Invalid link", "<p class='muted'>This check-in link is invalid or expired. "
                            + "Please ask the property owner for a new QR code.</p>"));
        }
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML)
                .body(formPage(orgId, propertyId, sig, headline(target.get()), null));
    }

    @PostMapping(value = "/{orgId}/{propertyId}/{sig}", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE,
            produces = MediaType.TEXT_HTML_VALUE)
    ResponseEntity<String> submit(
            @PathVariable Long orgId,
            @PathVariable Long propertyId,
            @PathVariable String sig,
            @RequestParam(defaultValue = "") String fullName,
            @RequestParam(defaultValue = "") String mobileNumber,
            @RequestParam(defaultValue = "") String email,
            @RequestParam(defaultValue = "") String gender,
            @RequestParam(defaultValue = "") String dateOfBirth,
            @RequestParam(defaultValue = "") String aadhaarNumber,
            @RequestParam(defaultValue = "") String occupation,
            @RequestParam(defaultValue = "") String permanentAddress,
            @RequestParam(defaultValue = "") String emergencyContactName,
            @RequestParam(defaultValue = "") String emergencyContactMobile,
            @RequestParam(defaultValue = "") String emergencyContactRelation,
            @RequestParam(defaultValue = "") String hasVehicle) {

        Optional<Target> target = resolve(orgId, propertyId, sig);
        if (target.isEmpty()) {
            return ResponseEntity.status(404).contentType(MediaType.TEXT_HTML).body(page(
                    "Invalid link", "<p class='muted'>This check-in link is invalid or expired.</p>"));
        }
        String head = headline(target.get());

        String name = fullName.trim();
        String mobile = mobileNumber.trim();
        if (name.length() < 2) {
            return ResponseEntity.badRequest().contentType(MediaType.TEXT_HTML)
                    .body(formPage(orgId, propertyId, sig, head, "Please enter your full name."));
        }
        if (!mobile.matches("^[0-9]{10}$")) {
            return ResponseEntity.badRequest().contentType(MediaType.TEXT_HTML)
                    .body(formPage(orgId, propertyId, sig, head, "Enter a valid 10-digit mobile number."));
        }
        String aadhaar = aadhaarNumber.replaceAll("\\s", "");
        if (!aadhaar.isEmpty() && !aadhaar.matches("^[0-9]{12}$")) {
            return ResponseEntity.badRequest().contentType(MediaType.TEXT_HTML)
                    .body(formPage(orgId, propertyId, sig, head, "Aadhaar must be 12 digits (or left blank)."));
        }

        boolean vehicle = hasVehicle.equalsIgnoreCase("yes")
                || hasVehicle.equalsIgnoreCase("true") || hasVehicle.equalsIgnoreCase("on");
        Long propertyScope = propertyId != null && propertyId != 0 ? propertyId : null;

        TenantCreateRequest req = new TenantCreateRequest(
                name, mobile,
                blankToNull(email), blankToNull(gender), parseDate(dateOfBirth),
                blankToNull(aadhaar), blankToNull(occupation), blankToNull(permanentAddress),
                blankToNull(emergencyContactName), blankToNull(emergencyContactMobile),
                blankToNull(emergencyContactRelation),
                null, null, null,
                vehicle,
                propertyScope);

        try {
            tenantService.create(orgId, null, req);
        } catch (Exception e) {
            return ResponseEntity.status(400).contentType(MediaType.TEXT_HTML)
                    .body(formPage(orgId, propertyId, sig, head,
                            "Could not submit: " + escape(e.getMessage())));
        }

        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(page(
                "You're all set!",
                "<div class='ok'>&#10003;</div>"
                        + "<h2>Thanks, " + escape(name) + "!</h2>"
                        + "<p class='muted'>Your details have been sent to " + escape(head)
                        + ". The property team will assign your bed and confirm shortly.</p>"));
    }

    /** Verifies the signature and that the org (and property, when scoped) exist and match. */
    private Optional<Target> resolve(Long orgId, Long propertyId, String sig) {
        if (orgId == null || propertyId == null || !tokenService.verify(orgId, propertyId, sig)) {
            return Optional.empty();
        }
        Optional<Facility> org = facilityRepository.findById(orgId)
                .filter(f -> FacilityType.ORGANIZATION.equals(f.getFacilityTypeId()));
        if (org.isEmpty()) return Optional.empty();
        if (propertyId == 0) return Optional.of(new Target(org.get(), null));
        Optional<Facility> property = facilityRepository.findById(propertyId)
                .filter(f -> FacilityType.PROPERTY.equals(f.getFacilityTypeId())
                        && orgId.equals(f.getOrganizationId()));
        return property.map(p -> new Target(org.get(), p));
    }

    private static String headline(Target t) {
        return t.property() != null
                ? t.org().getFacilityName() + " — " + t.property().getFacilityName()
                : t.org().getFacilityName();
    }

    private static String blankToNull(String s) {
        if (s == null) return null;
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }

    private static LocalDate parseDate(String s) {
        try { return blankToNull(s) == null ? null : LocalDate.parse(s.trim()); }
        catch (DateTimeParseException e) { return null; }
    }

    private static String escape(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&#39;");
    }

    // ─── HTML ──────────────────────────────────────────────────────────────────

    private String formPage(Long orgId, Long propertyId, String sig, String head, String error) {
        String action = "/api/public/self-checkin/" + orgId + "/" + propertyId + "/" + sig;
        String err = error == null ? "" : "<div class='err'>" + escape(error) + "</div>";
        String body = """
                <p class='muted'>Registering with <b>%s</b>. Fill in your details below.</p>
                %s
                <form method='post' action='%s'>
                  <label>Full Name *<input name='fullName' required autocomplete='name' minlength='2'></label>
                  <label>Mobile Number *<input name='mobileNumber' required inputmode='numeric' pattern='[0-9]{10}' maxlength='10' placeholder='10-digit number'></label>
                  <label>Email<input name='email' type='email' autocomplete='email'></label>
                  <label>Gender
                    <select name='gender'>
                      <option value=''>Select</option>
                      <option value='MALE'>Male</option>
                      <option value='FEMALE'>Female</option>
                      <option value='OTHER'>Other</option>
                    </select>
                  </label>
                  <label>Date of Birth<input name='dateOfBirth' type='date'></label>
                  <label>Aadhaar Number<input name='aadhaarNumber' inputmode='numeric' maxlength='12' placeholder='12 digits'></label>
                  <label>Occupation<input name='occupation'></label>
                  <label>Permanent Address<textarea name='permanentAddress' rows='2'></textarea></label>
                  <label class='inline'><input type='checkbox' name='hasVehicle' value='yes'> I have a vehicle</label>
                  <div class='section'>Emergency Contact</div>
                  <label>Name<input name='emergencyContactName'></label>
                  <label>Mobile<input name='emergencyContactMobile' inputmode='numeric' maxlength='10'></label>
                  <label>Relation<input name='emergencyContactRelation' placeholder='e.g. Father'></label>
                  <button type='submit'>Submit</button>
                </form>
                """.formatted(escape(head), err, action);
        return page("Tenant Check-in", body);
    }

    private String page(String title, String body) {
        return """
                <!doctype html>
                <html lang='en'><head>
                <meta charset='utf-8'>
                <meta name='viewport' content='width=device-width, initial-scale=1'>
                <title>%s</title>
                <style>
                  * { box-sizing: border-box; }
                  body { margin:0; font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
                         background:#F5F6FA; color:#111827; }
                  .wrap { max-width:480px; margin:0 auto; padding:20px 16px 48px; }
                  .card { background:#fff; border-radius:16px; padding:22px 18px;
                          box-shadow:0 4px 18px rgba(0,0,0,.06); }
                  h1 { font-size:20px; margin:0 0 4px; }
                  h2 { font-size:20px; margin:8px 0 6px; text-align:center; }
                  .brand { display:flex; align-items:center; gap:10px; margin-bottom:14px; }
                  .brand .dot { width:38px; height:38px; border-radius:11px;
                                background:linear-gradient(135deg,#4F2DE4,#7C5CF6); }
                  .brand b { font-size:16px; }
                  .muted { color:#6B7280; font-size:14px; line-height:1.5; }
                  label { display:block; font-size:13px; font-weight:600; color:#374151; margin:14px 0 0; }
                  label.inline { display:flex; align-items:center; gap:8px; font-weight:500; }
                  input, select, textarea { width:100%%; margin-top:6px; padding:11px 12px; font-size:15px;
                          border:1px solid #D1D5DB; border-radius:10px; background:#fff; }
                  label.inline input { width:auto; margin-top:0; }
                  .section { margin:20px 0 2px; font-weight:700; font-size:14px; color:#111827; }
                  button { width:100%%; margin-top:22px; padding:14px; font-size:16px; font-weight:700;
                          color:#fff; background:#4F2DE4; border:0; border-radius:12px; }
                  .err { margin-top:12px; padding:10px 12px; background:#FEF2F2; color:#B91C1C;
                         border-radius:10px; font-size:13px; }
                  .ok { width:64px; height:64px; margin:6px auto 0; border-radius:50%%; background:#DCFCE7;
                        color:#16A34A; font-size:34px; line-height:64px; text-align:center; }
                </style></head>
                <body><div class='wrap'>
                  <div class='brand'><span class='dot'></span><b>PG Manager</b></div>
                  <div class='card'>
                    <h1>%s</h1>
                    %s
                  </div>
                </div></body></html>
                """.formatted(escape(title), escape(title), body);
    }
}
