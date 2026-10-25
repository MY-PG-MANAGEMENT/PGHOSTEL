# WhatsApp Invoice Reminders — Phase 1 (Deep Link)

The WhatsApp icon on the Invoice Detail sheet. The owner taps it, WhatsApp opens on the tenant's
chat with the payment reminder already typed, and **the owner presses Send themselves**.

**There is no Meta Cloud API integration in this phase** — no access token, no phone-number id, no
business account id, no approved templates, no webhooks, no delivery or read status. Phase 1 is
`https://wa.me/<phone>?text=<encoded-message>` and nothing more. §"Phase 2" below records exactly
what a future Cloud API integration has to change, and what it must leave alone.

Backend: `backend/src/main/java/com/pgmanager/whatsapp/`.
Flutter: `owner_app/lib/src/utils/whatsapp_link.dart` and the icon in `billing_screen.dart`.

---

## 1. Flow

```
Owner opens an invoice
        │
        ▼
GET /api/billing/invoices/{id}          ← the sheet already fetches this for the charge breakdown
        │                                 (now also carries the `reminder` block)
        ▼
Sheet renders. WhatsApp icon enabled iff reminder.canRemind
        │
        ▼
Owner taps the icon                     ← ONE tap. No confirmation dialog.
        │
        ▼
whatsAppChatUri(reminder.whatsappNumber, reminder.message)
        │
        ▼
launchUrl(..., LaunchMode.externalApplication)
        │
        ▼
WhatsApp opens on the tenant's chat, message pre-filled
        │
        ▼
Owner presses SEND                      ← the app is not involved and cannot observe this
```

**No new endpoint.** The reminder is attached to the existing invoice-detail response rather than
given an API of its own: the Flutter sheet already fetches that payload, so the icon costs no extra
round trip, there is no duplicate API to keep in step, and tapping needs no loading state.

**No confirmation sheet.** WhatsApp's own compose screen *is* the confirmation — nothing is sent
until the owner taps Send there, so an extra in-app dialog would only add a tap.

---

## 2. What changed in the existing code

`BillingController.invoice()` (`GET /api/billing/invoices/{id}`):

- The SELECT gained **`p.mobile_number`** (the `person` join was already there, so this is free) and
  a **property-name** correlated subquery.
- The response gained a **`reminder`** block.
- It now calls **`PropertyAccessGuard.assertTenantInScope`**. That endpoint was previously
  `organization_id`-scoped only, so a property-scoped manager could read any invoice in the
  organization by id. The gap mattered less when the payload was amounts and dates; it now returns a
  tenant's phone number. Owners are unaffected — the guard returns immediately when unrestricted.

Nothing else in billing, payments or invoicing was touched. No new table, no migration.

### The `reminder` block

```json
"reminder": {
  "status": "DUE",
  "canRemind": true,
  "blockedReason": null,
  "tenantName": "Ravi Kumar",
  "propertyName": "Sri Lakshmi PG",
  "paymentType": "Monthly Rent",
  "dueAmount": 8500.00,
  "dueDate": "2026-08-08",
  "whatsappNumber": "919876543210",
  "message": "Hi Ravi Kumar 👋\n\nA gentle reminder that your Monthly Rent at Sri Lakshmi PG is due today.\n\n🧾 Payment: Monthly Rent\n📅 Due date: 08-Aug-2026\n⏳ Status: Due today\n💰 Amount due: ₹8,500\n\nPaying today keeps your account clear. ✅\n\nSri Lakshmi PG · PG Manager"
}
```

`message` and `whatsappNumber` are **null** whenever `canRemind` is false, so the app cannot
pre-fill a reminder for an invoice that should not be chased.

---

## 3. Reminder type

`InvoiceReminderStatus.derive(dueDate, total, paid, invoiceStatus, today)` — a pure function, no
database, no clock injection needed at the call site.

| Condition | Status | Reminder? |
|---|---|---|
| `invoiceStatus` is `CANCELLED` / `WRITTEN_OFF` | `CLOSED` | no |
| `total - paid <= 0`, or `invoiceStatus` is `PAID` | `SETTLED` | no |
| `dueDate < today` | `OVERDUE` | **yes** |
| `dueDate == today` | `DUE` | **yes** |
| `dueDate == today + 1` | `TOMORROW` | **yes** |
| anything else, incl. a null due date | `NOT_DUE` | no |

**The order is load-bearing.** Closed statuses are screened first and money before dates, because
invoice delete is a *soft-cancel* — a cancelled invoice keeps a positive balance on paper, so
without those screens a deleted or already-paid invoice would read as overdue and be chaseable.
`outstanding()` clamps at zero, so an overpayment is never a due.

Outstanding amount is `invoice.total_amount - invoice.paid_amount` — the same figure the invoice list
already returns as `balance`. No payment logic is duplicated.

---

## 4. Messages

`InvoiceReminderMessageBuilder`. All three variants are cut from **one layout** — greeting, a
one-line lead, a labelled detail block, a closing line, a signature — and differ only in tone and
the status line. A tenant who has had one reminder recognises the next at a glance, and a wording
change cannot leave the three looking like messages from three different businesses.

**OVERDUE**
```
Hi {tenant} 👋

Your {paymentType} at {property} is overdue.

🧾 Payment: {paymentType}
📅 Due date: {dueDate}
⏳ Status: {n} days overdue
💰 Amount due: ₹{amount}

Please clear the pending amount at your earliest convenience. 🙏

{property} · PG Manager
```

**DUE (today)**
```
Hi {tenant} 👋

A gentle reminder that your {paymentType} at {property} is due today.

🧾 Payment: {paymentType}
📅 Due date: {dueDate}
⏳ Status: Due today
💰 Amount due: ₹{amount}

Paying today keeps your account clear. ✅

{property} · PG Manager
```

**TOMORROW**
```
Hi {tenant} 👋

Just a heads-up — your {paymentType} at {property} is due tomorrow.

🧾 Payment: {paymentType}
📅 Due date: {dueDate}
⏳ Status: Due in 1 day
💰 Amount due: ₹{amount}

A small reminder so it does not slip by. 🙂

{property} · PG Manager
```

- **Plain text on purpose — no `*bold*`, no `_italic_`, no banner, no rule.** WhatsApp markup renders
  as literal asterisks in a notification preview, in a chat export, and anywhere the message is
  quoted or forwarded. A payment reminder is a business document and has to read cleanly in all of
  those, not only inside the chat bubble. A test asserts that no variant contains `*` or `_`.
- **Emoji stay** as line markers: unlike markup they render as glyphs everywhere the message can end
  up, and they are what makes the detail block scannable.
- **Labels are plain `Label: value`, never space-padded columns.** WhatsApp renders in a proportional
  font, so a padded `Amount   : ...` column that lines up in the editor arrives crooked on the phone.
- **The card is built server-side, so it is not ASCII-constrained** — unlike the report PDFs, whose
  built-in Helvetica cannot render `₹` or an em dash. Emoji and `₹` are safe here and survive
  percent-encoding into the `wa.me` link.
- **`{n} days overdue` needs today's date**, so `build` takes a `today` parameter rather than reading
  the clock. `InvoiceReminderService` reads it **once** and passes the same value to `derive` and to
  `build`, so a call straddling midnight cannot report `DUE` and "1 day overdue" together. One day is
  singular ("1 day ago"); a missing date degrades to a bare "Overdue" rather than "0 days overdue".
- Amount: `#,##0.##` with a `₹` prefix — `8500.00` renders `₹8,500`.
- Date: `dd-MMM-yyyy` — `08-Aug-2026`, matching the style `NotificationService` uses for emails.
- **Payment type is derived, not stored.** There is no such column on `invoice`;
  `paymentTypeLabel` reads the invoice's `invoice_item.item_type_id` values (`TEMP_STAY` →
  "Temporary Stay", else `MONTHLY_RENT` → "Monthly Rent", …). A move-in invoice carries rent + AC +
  deposit, so "Monthly Rent" is the honest summary.
- Missing fields get readable fallbacks (`your PG`, `there`, `rent`) rather than producing
  "Hi ," — a tenant with no property membership is normal in this schema. The **signature drops the
  property entirely** in that case: the lead sentence reads fine as "at your PG", but a sign-off
  reading "your PG · PG Manager" does not.

**The builder is Java, not Dart, deliberately.** Building the text in Flutter would work fine for
deep linking and then have to be rewritten for Phase 2, where the message (and eventually the
approved template parameters) must be assembled server-side. The app receives a finished string.

---

## 5. Phone numbers

`PhoneNumberNormalizer.toE164Digits(raw, defaultCountryCode)` → digits only, country code first, no
`+`, no spaces, no punctuation.

`person.mobile_number` is free text in practice — typed on the Add Tenant form, imported from CSV, or
submitted by a tenant on the public self check-in page:

| Stored | Sent to `wa.me` |
|---|---|
| `9876543210` | `919876543210` |
| `+91 98765 43210` | `919876543210` |
| `98765-43210` | `919876543210` |
| `09876543210` | `919876543210` (leading `0` is the domestic trunk prefix) |
| `00919876543210` | `919876543210` (`00` is an international dialling prefix) |
| `+14155552671` | `14155552671` (own country code kept, not re-prefixed) |

Only **two** messages ever reach the owner, both shown verbatim as the icon's tooltip:

- `WhatsApp number is not available for this tenant.` — nothing on file
- `Invalid WhatsApp number.` — anything unparseable

A malformed number is refused rather than guessed at, because `wa.me` does not validate: a bad number
lands the owner on WhatsApp's "invalid number" screen, or — worse — on a stranger's chat.

### Configuration

Exactly one setting, in `application.yml` / `application-prod.yml` / `deployment/.env`:

| Env var | Default | Purpose |
|---|---|---|
| `WHATSAPP_DEFAULT_COUNTRY_CODE` | `91` | Prefixed onto bare 10-digit mobiles. Digits only, no `+`. |

There is nothing to provision and no secret to manage — deep linking needs neither.

---

## 6. UI behaviour

The icon is in the Invoice Detail sheet's header row, beside Edit and Delete.

| State | Icon |
|---|---|
| Reminder available | **enabled**, WhatsApp green, tooltip "Send payment reminder on WhatsApp" |
| Fully paid / not due yet / bad number | **disabled**, grey, tooltip = the server's `blockedReason` |
| Cancelled invoice | **absent** (not a due at all) |
| Invoice-detail fetch failed, or no `reminder` block | **absent** |

**It is not gated on the per-org `WHATSAPP` channel toggle** in the admin console. That toggle is
opt-in and off by default, and deep linking needs no provisioning, so gating on it would hide the
feature from every organization for no reason. (Phase 2 *should* gate on it — see below.)

Disabled rather than hidden for a settled invoice, so the affordance stays where the owner learned to
look instead of appearing and vanishing between invoices.

### The app must never say "sent"

The toast is **"Opening WhatsApp…"**. Tapping the icon means WhatsApp was opened; it does not mean
the owner pressed Send, and the app has no way to find out. Reporting delivery would let an owner
believe a tenant was chased when they were not.

For the same reason there is **no `whatsapp_message_log` table in Phase 1** — a history of
"reminders sent" built from taps would record intentions as though they were deliveries. Real send
tracking arrives with the Cloud API.

### URL encoding

`whatsAppChatUri` uses **`Uri.encodeComponent`, not `Uri.https(..., queryParameters:)`**. Dart's
`queryParameters` applies form encoding and turns every space into `+`, which `wa.me` does not
reliably read back as a space — the pre-filled message then arrives full of plus signs. Percent
encoding is what Click-to-Chat expects: `%20` for space, `%0A` for the newlines, `%E2%82%B9` for `₹`,
`%26` for `&` (so an ampersand in a property name cannot start a second query parameter).

It returns **null** for a blank number instead of a bare `wa.me` URL — that would open WhatsApp's
contact picker, and the owner could message the wrong person believing it was the tenant.

---

## 7. Multi-tenant security

No new surface: the reminder is part of the invoice-detail response, so it inherits that endpoint's
authorization.

```
JWT → AppUserPrincipal → CurrentUser.organizationId()
        ↓
invoice WHERE organization_id = ?           ← another org's invoice is a 404, not a 403
        ↓
PropertyAccessGuard.assertTenantInScope(party_id)   ← added by this feature
        ↓
reminder built from that row only
```

The client supplies **only the invoice id**. Tenant, property, phone number and amount are all read
from the invoice; none can be passed in. 404 rather than 403 for a foreign invoice is deliberate — a
403 would confirm the id exists in some other organization.

---

## 8. Where the phase boundary sits

```
                    ┌─────────────────────────────────────────┐
                    │  BUSINESS LOGIC — survives Phase 2      │
                    │                                         │
Invoice ──────────► │  InvoiceReminderStatus.derive           │
                    │  InvoiceReminderStatus.outstanding      │
                    │  InvoiceReminderMessageBuilder          │
                    │  PhoneNumberNormalizer                  │
                    │  InvoiceReminderService                 │
                    └──────────────────┬──────────────────────┘
                                       │  InvoiceReminder { status, message, whatsappNumber, … }
                        ┌──────────────┴──────────────┐
                        ▼                             ▼
             ┌────────────────────┐        ┌──────────────────────┐
             │ PHASE 1 (now)      │        │ PHASE 2 (future)     │
             │ whatsapp_link.dart │        │ Cloud API client     │
             │ wa.me deep link    │        │ + templates          │
             │ owner taps Send    │        │ automatic send       │
             └────────────────────┘        └──────────────────────┘
```

There is no `WhatsAppMessageDelivery` interface, and that is a decision rather than an omission.
In Phase 1 "delivery" happens on the *client* — a backend interface with a single implementation that
lives in another language would be ceremony with nothing behind it. What actually matters for the
migration is that the message builder is separated from the delivery, and it is: the entire Phase 1
delivery mechanism is one Dart function.

### What Phase 2 changes

- **Add** a `WhatsAppCloudApiClient` and config (`access-token`, `phone-number-id`, api version).
- **Add** approved-template handling: `InvoiceReminderMessageBuilder` grows a method returning the
  ordered template parameters alongside the plain text it already returns. Meta requires a
  pre-approved template for a business-initiated message, so the plain text alone will not send.
- **Add** `whatsapp_message_log` (send attempts, provider message id, delivery status via webhook)
  and a duplicate-send guard on top of it.
- **Add** a `POST` endpoint that sends server-side, and gate it on the per-org `WHATSAPP` channel
  toggle plus credentials — at that point provisioning genuinely exists, so gating is correct.
- **Delete** `owner_app/lib/src/utils/whatsapp_link.dart` and change the icon's `onPressed` from
  "launch a URL" to "call the endpoint".

### What Phase 2 must not change

`InvoiceReminderStatus`, `InvoiceReminderMessageBuilder`, `PhoneNumberNormalizer` and the shape of
`InvoiceReminder`. If a Cloud API migration finds itself editing the status derivation or the
wording, the split has been broken — those are business rules, not delivery details.

Also worth keeping: `notification/MessageChannel` + `OutboxDispatcher` already exist for async
channels ("EMAIL now; WHATSAPP later"). An *automated* WhatsApp reminder in Phase 2 belongs there,
behind a `MessageChannel`. The owner-triggered button should stay synchronous — the owner is watching
and needs the outcome.

---

## 9. Tests

| File | Covers |
|---|---|
| `whatsapp/InvoiceReminderStatusTest` | The status matrix, incl. paid-but-overdue and cancelled-with-a-balance |
| `whatsapp/InvoiceReminderServiceTest` | The **exact wording** of all three messages, the part-paid balance, missing/invalid numbers, and row coercion |
| `whatsapp/PhoneNumberNormalizerTest` | Every mobile format the schema actually contains, and the two refusal messages |
| `owner_app/test/invoice_whatsapp_reminder_test.dart` | URL encoding (`%20` not `+`, `₹`, `&`, newlines), icon enabled/disabled/absent states, and that the app never claims a message was sent |

The Flutter test mocks the `plugins.flutter.io/url_launcher` method channel and asserts the exact URL
handed to it, so nothing is actually launched. Two traps worth remembering: `AppToast` needs
`AppToast.navigatorKey` wired into the `MaterialApp` or its toasts are silently dropped, and toast
assertions need short fixed `pump`s — `pumpAndSettle` runs the clock past the auto-dismiss.

Spec case coverage: overdue, due today, due tomorrow, fully paid, missing mobile, message encoding
(spaces / `&` / `+` / `/` / `₹` / newlines), and correct-tenant authorization are each asserted.
