# PG Manager — Telugu Voice-Over & Shot Script

Product demo video, 14 scenes. The voice-over is **Telugu**; the screens recorded are the real
owner app. Estimated runtime **4:40 – 5:10** at a medium speaking pace with the pauses marked.

This file is the recording brief: for each scene it carries the Telugu narration verbatim, the exact
screen to record, what to tap while the line is read, and where to pause. The narration text is the
approved script — **read it as written**. Where a line and the app do not line up, that is called out
in [Accuracy notes](#accuracy-notes) rather than silently reworded.

---

## Voice direction

| | |
|---|---|
| Voice | Professional Telugu male |
| Tone | Confident, friendly, clear — a PG business representative explaining software to an owner |
| Pace | Medium. Not a news reader |
| Register | Everyday professional Telugu. **Not** literary/formal Telugu |
| Pauses | Brief pause after each feature and after every number |

English product terms stay in English and are spoken the way a Telugu speaker naturally says them —
not translated, and not over-anglicised:

| Term | Delivery note |
|---|---|
| PG Manager | "PG Manager" — the product name, never translated |
| Dashboard | natural Telugu-English, not "డాష్‌బోర్డ్" read letter-by-letter |
| Tenant / Tenants | "టెనెంట్" — keep the plural "s" audible |
| Room / Rooms, Bed / Beds | "రూమ్స్", "బెడ్స్" |
| Rent, Payment, Invoice | plain, unstressed |
| WhatsApp | as everyone says it — "వాట్సాప్" |
| Reports, Property, Staff | plain |
| Overdue, Due Today, Due Tomorrow | keep in English; these are on-screen labels |

---

## Before recording

Set up demo data first — several scenes only work if the data is in the right state.

1. **One org, 2 properties**, so Scene 3's "multiple PG properties" is true on screen.
2. A property with **floors → rooms → beds**, some occupied and **at least 2 vacant beds** (Scene 4).
3. **8–10 tenants** with real-looking Telugu names and mobile numbers.
4. Invoices covering **all four states** — this is what Scene 7 and Scene 9 show:
   - one **OVERDUE** (due date in the past, unpaid)
   - one **due today**
   - one **due tomorrow**
   - one **PAID**, one **PARTIAL**
5. Record Scene 9 on a **real Android device or an emulator with WhatsApp installed**. The
   WhatsApp button hands off to the WhatsApp app; on desktop or web the launch fails and you will
   record an error toast.
6. Use a **clean status bar** (full battery, no notifications) and the same device for every scene.

---

## Scene 1 — Introduction

**Screen:** App launch → splash → `/dashboard` settling. Or a slow pan over the Dashboard.
**Duration:** ~20 s

> ఒక PG నిర్వహించడం అంటే కేవలం రూమ్స్, బెడ్స్ చూసుకోవడం మాత్రమే కాదు.
>
> టెనెంట్స్ వివరాలు, రెంట్, పేమెంట్స్, పెండింగ్ అమౌంట్స్, రూమ్ availability... ఇవన్నీ ప్రతిరోజూ manage చేయాలి.
>
> ఈ పనులన్నింటినీ ఒకే చోట సులభంగా manage చేయడానికి రూపొందించిందే PG Manager.

**Delivery:** Let the list in line 2 breathe — a short beat after each item. Land firmly on
"PG Manager"; hold ~1 s of silence after it before Scene 2.

---

## Scene 2 — Dashboard

**Screen:** `/dashboard` (owner home).
**Actions:** Hold on the stat row — **Properties · Total Beds · Occupied · Monthly** — then scroll
gently to the property cards. Cut to **Billing → Dashboard** tab for the collection/pending line.
**Duration:** ~26 s

> PG Manager Dashboard ఓపెన్ చేయగానే మీ PG యొక్క complete overview మీకు కనిపిస్తుంది.
>
> ఎన్ని beds ఉన్నాయి, ఎన్ని occupied గా ఉన్నాయి, ఎన్ని available గా ఉన్నాయి, ఈ నెల collection ఎంత వచ్చింది, ఇంకా ఎంత rent pending లో ఉంది — అన్నీ ఒకే screen లో చూడవచ్చు.
>
> దీంతో మీ PG పరిస్థితి ఎలా ఉందో వెంటనే తెలుసుకోవచ్చు.

**Delivery:** The middle line is the longest in the script. Pause after each of the five items so it
reads as a list, not one breath. Time the cut to Billing so "collection" and "pending" land on
**Total Collected** and **Outstanding Today**.

> ⚠️ See [Accuracy note 1](#1--scene-2-one-screen-spans-two-screens) — the Dashboard alone does not
> show vacant beds or pending rent.

---

## Scene 3 — Property Management

**Screen:** `/properties` list (two property cards) → tap one → **Property Workspace → Overview**.
**Actions:** From Overview tap **Floors & Rooms** and let the floor → room tree render.
**Duration:** ~21 s

> మీ దగ్గర ఒక PG ఉన్నా, multiple PG properties ఉన్నా, అన్నింటినీ ఒకే application నుంచి manage చేయవచ్చు.
>
> Property ను floors గా, floors ను rooms గా, rooms ను individual beds గా organize చేసుకోవచ్చు.
>
> దీంతో ఏ tenant ఏ room లో, ఏ bed లో ఉన్నారో చాలా సులభంగా తెలుసుకోవచ్చు.

**Delivery:** Line 2 is the hierarchy — step down through it, a small beat at each "గా".
Property → floors → rooms → beds should be audible as four levels.

---

## Scene 4 — Room & Bed Management

**Screen:** **Floors & Rooms** screen; then open a room card showing its bed grid.
**Actions:** Point at the occupied (grey) vs vacant (green) beds. Then open **Vacant Beds** from the
Overview and tap **Assign** on a free bed — stop at the assign sheet, do not complete it.
**Duration:** ~15 s

> ప్రతి room లో ఎన్ని beds ఉన్నాయి, ఎన్ని occupied గా ఉన్నాయి, ఇంకా ఎన్ని beds available గా ఉన్నాయి అనేది వెంటనే కనిపిస్తుంది.
>
> కొత్త tenant వచ్చినప్పుడు available bed ను సులభంగా assign చేయవచ్చు.

**Delivery:** Keep it brisk — this is the shortest scene. "assign చేయవచ్చు" lands as the sheet opens.

---

## Scene 5 — Tenant Management

**Screen:** `/tenants` (or Property Workspace → **Tenants** tab).
**Actions:** Hold on the list with the **ALL / ACTIVE / INACTIVE** chips visible, then tap a tenant →
**Profile** tab → swipe to **Payments** tab.
**Duration:** ~19 s

> Tenant Management ద్వారా మీ tenants అందరి information ఒకే చోట ఉంటుంది.
>
> Tenant పేరు, phone number, room, bed, monthly rent, due date, payment status వంటి వివరాలను వెంటనే చూడవచ్చు.
>
> ఒక tenant profile ఓపెన్ చేస్తే వారి rent మరియు payment history కూడా చూడవచ్చు.

**Delivery:** Line 2 is a seven-item list — pace it evenly and do not rush the tail. The tenant card
should be on screen for the whole line.

---

## Scene 6 — Add New Tenant

**Screen:** Tenants → **+ Add Tenant** form.
**Actions:** Fill name and mobile, then the property → floor → room → bed pickers, then rent and
joining date. Tap **Save** and let the success state land.
**Duration:** ~18 s

> కొత్త tenant ను add చేయడం కూడా చాలా simple.
>
> Tenant details enter చేసి, property, floor, room మరియు available bed select చేసి, monthly rent మరియు joining date enter చేస్తే సరిపోతుంది.
>
> Save చేసిన వెంటనే tenant మీ PG records లో add అవుతారు.

**Delivery:** Line 2 must run in step with the taps — do not read ahead of the form. Land "Save
చేసిన వెంటనే" exactly on the Save tap.

---

## Scene 7 — Rent & Invoice

**Screen:** `/billing` → **Invoices** tab.
**Actions:** Show the filter chips **ALL / PENDING / PAID / PARTIAL / CANCELLED**. Tap **PENDING**.
Scroll so the OVERDUE card, the due-today card and the due-tomorrow card are all seen. Point at the
due dates for "today" and "tomorrow".
**Duration:** ~22 s

> ప్రతి నెల rent ను track చేయడం ఇప్పుడు చాలా easy.
>
> ఎవరికి rent paid అయింది, ఎవరి rent ఈరోజు due ఉంది, ఎవరి rent రేపు due అవుతుంది, ఇంకా ఎవరి rent overdue అయింది అనేది ఒకే screen లో తెలుసుకోవచ్చు.
>
> దీంతో payment follow-up చేయాల్సిన tenants ను వెంటనే గుర్తించవచ్చు.

**Delivery:** Four states in line 2 — one beat each. "overdue" gets the most weight; it is the one
that costs the owner money.

> ⚠️ See [Accuracy note 2](#2--scene-7-there-is-no-due-tomorrow-filter).

---

## Scene 8 — Payment

**Screen:** Invoices → tap an invoice card → **Invoice detail sheet**.
**Actions:** Let the sheet's header, the Charge Details card and the Paid / Balance pair be seen.
Tap **Collect Payment**, enter the amount, choose a payment mode, save. Return to the list and show
the card now reading **PAID**.
**Duration:** ~15 s

> Tenant payment చేసినప్పుడు, ఆ payment ను invoice కి record చేయవచ్చు.
>
> Payment save చేసిన వెంటనే status update అవుతుంది.
>
> దీంతో మీ collection మరియు pending amounts ఎప్పుడూ accurate గా ఉంటాయి.

**Delivery:** "status update అవుతుంది" must land on the moment the badge flips to PAID. Hold a beat
on the changed badge before line 3.

---

## Scene 9 — WhatsApp Reminder

**Screen:** Invoices → **PENDING** → an **overdue** invoice → invoice detail sheet.
**Actions:** Hold on the three labelled actions — **WhatsApp · Edit · Delete**. Tap **WhatsApp**.
WhatsApp opens on the tenant's chat with the reminder already typed in the compose box. **Hold on
the composed message long enough to read it — then stop. Do not tap Send.** That is the point of the
scene: the owner sends it.
**Duration:** ~33 s — the longest scene

> Rent reminder పంపడం కూడా చాలా సులభం.
>
> Overdue అయిన tenant దగ్గర WhatsApp option ను click చేస్తే predefined reminder message సిద్ధంగా ఉంటుంది.
>
> Tenant పేరు, rent amount, due date మరియు overdue status message లో automatically వస్తాయి.
>
> Owner message ను చూసి, WhatsApp ద్వారా tenant కి manually send చేయవచ్చు.
>
> Due Today, Due Tomorrow మరియు Overdue కోసం different reminder messages కూడా ఉపయోగించవచ్చు.
>
> దీంతో ప్రతి tenant కి message ను manually type చేయాల్సిన అవసరం ఉండదు.

**Delivery:** Line 3 should be read while the composed message is on screen, so the viewer can match
each item to the line they are hearing:

```
Hi Ravi Kumar 👋

Your Monthly Rent at Sri Lakshmi PG is overdue.

🧾 Payment: Monthly Rent
📅 Due date: 05-Aug-2026
⏳ Status: 3 days overdue
💰 Amount due: ₹8,500

Please clear the pending amount at your earliest convenience. 🙏

Sri Lakshmi PG · PG Manager
```

Put a deliberate stress on **manually** in line 4 — the app never sends on the owner's behalf, and
that is a trust point, not a limitation. For line 5, cut back and repeat the tap on a **due today**
and a **due tomorrow** invoice so all three message variants are actually seen.

---

## Scene 10 — Payment History

**Screen:** `/billing` → **Payments** tab. Then a tenant's own **Payments** tab for the per-tenant view.
**Actions:** Scroll the receipt list slowly. Show amount, date and payment mode on the rows.
**Duration:** ~16 s

> Payment History ద్వారా గతంలో వచ్చిన payments అన్నింటినీ చూడవచ్చు.
>
> ఏ tenant ఎంత amount చెల్లించారు, ఎప్పుడు చెల్లించారు, ఏ payment method ఉపయోగించారు అనే details కూడా easily track చేయవచ్చు.

**Delivery:** Three questions in line 2 — ఎంత / ఎప్పుడు / ఏ method. A small beat after each, with
the scroll timed so the matching column is visible.

---

## Scene 11 — Reports

**Screen:** Property Workspace → **Reports** tab (four cards: Rent Collection, Outstanding Due,
Expense, Profit & Loss). Then cut to `/dashboard/analytics` for the charts.
**Actions:** Set the month on **Rent Collection Report** and tap **Download PDF**; let the PDF open
in the viewer and show a page. Then cut to Analytics for the occupancy and collection charts.
**Duration:** ~19 s

> Reports ద్వారా మీ PG business performance ను ఒకే చోట అర్థం చేసుకోవచ్చు.
>
> Occupancy ఎంత ఉంది, ఈ నెల collection ఎంత వచ్చింది, ఎంత amount pending లో ఉంది, ఎంత overdue ఉంది — ఇవన్నీ simple reports మరియు charts ద్వారా చూడవచ్చు.

**Delivery:** Time "reports" to the PDF and "charts" to the Analytics cut, so both halves of the
claim are on screen as they are spoken.

> ⚠️ See [Accuracy note 3](#3--scene-11-the-reports-screen-has-no-charts).

---

## Scene 12 — Owner & Staff

**Screen:** **Settings → Team → Managers** (`managers_screen.dart`).
**Actions:** Show the manager list with each login's assigned properties. Open **Add Manager**, or
open the ⋮ → **Edit properties** to show the property assignment. Then cut briefly to the owner's
own Dashboard to contrast full access.
**Duration:** ~14 s

> మీ PG ను manage చేయడానికి staff ఉన్నట్లయితే, వారికి అవసరమైన access ను ఇవ్వవచ్చు.
>
> Owner కి complete access ఉండగా, staff కి అవసరమైన management features మాత్రమే అందించవచ్చు.

**Delivery:** Contrast the two halves of line 2 clearly — "Owner కి complete access" against "staff
కి ... మాత్రమే". The word మాత్రమే carries the whole scene.

> ⚠️ **Important — see [Accuracy note 4](#4--scene-12-record-managers-not-the-staff-screen).** Do not
> record the **Staff** screen for this scene. That screen is payroll; staff there have no logins.

---

## Scene 13 — Complete Workflow

**Screen:** Fast montage, ~2 s per shot, in the order the lines name them.
**Actions:** Property setup → Floors & Rooms → Add Tenant → Invoices → Collect Payment → WhatsApp
reminder → Reports. Reuse the cleanest take from each earlier scene.
**Duration:** ~20 s

> Property setup చేయడం నుంచి rooms మరియు beds manage చేయడం వరకు...
>
> Tenants add చేయడం నుంచి monthly rent track చేయడం వరకు...
>
> Payments record చేయడం, WhatsApp reminders పంపించడం, reports చూడడం వరకు...
>
> PG Manager లో మొత్తం process ఒకే connected workflow గా ఉంటుంది.

**Delivery:** The three "వరకు" lines build — lift the pace and the energy slightly on each, then
drop back to a settled, confident tone for the last line. The cuts land on each "వరకు".

---

## Scene 14 — Final Message

**Screen:** Dashboard, then the PG Manager logo on a clean brand background.
**Actions:** The four short lines can carry one quick shot each — PG / tenant list / an invoice /
the payments list — before resolving on the logo.
**Duration:** ~18 s

> PG నిర్వహణలో రోజువారీ manual work ను తగ్గించి, మీ business పై మరింత focus చేయడానికి PG Manager మీకు సహాయపడుతుంది.
>
> మీ PG...
>
> మీ Tenants...
>
> మీ Rent...
>
> మీ Payments...
>
> అన్నీ ఒకే చోట.
>
> PG Manager — మీ PG, All in One Place.

**Delivery:** The four "మీ ..." lines are deliberately spaced — a clear beat between each, one shot
each. Then a longer pause before "అన్నీ ఒకే చోట." The closing line is the tagline: slower, warmer,
and let the silence sit for ~1.5 s before the video ends.

---

## Accuracy notes

Four places where the narration and the current app do not line up. None needs a code change; each
needs the right screen recorded, or a one-line script tweak. Flagged rather than silently reworded —
the script is the approved copy.

### 1 — Scene 2: "one screen" spans two screens

The owner Dashboard's stat row is **Properties · Total Beds · Occupied · Monthly**. It carries no
vacant-bed count and no pending-rent figure. Those live elsewhere: **Vacant Beds** on the Property
Workspace Overview, and **Total Collected / Received Today / Outstanding Today** on the Billing
Dashboard tab. So "అన్నీ ఒకే screen లో చూడవచ్చు" is not literally true of any single screen.

**Options:** (a) keep the line and cut Dashboard → Billing mid-sentence — most viewers will read it
as "one place", not "one screen"; or (b) change "ఒకే screen లో" to **"ఒకే చోట"**, which is true and
is the phrasing Scene 1 and Scene 14 already use. (b) is the cleaner fix.

### 2 — Scene 7: there is no "due tomorrow" filter

The Invoices tab chips are **ALL / PENDING / PAID / PARTIAL / CANCELLED**. "Due today" and "due
tomorrow" are not filters — they are due dates on the invoice cards, and they are reminder statuses
inside the WhatsApp message. Show them by pointing at the due date on two specific cards. Do not
reach for a filter chip that does not exist while the line is read.

### 3 — Scene 11: the Reports screen has no charts

The Reports tab is **download-only** — four cards, each producing a PDF. Charts are on the Dashboard
and on `/dashboard/analytics`. Recording Reports alone while saying "reports మరియు charts" would show
only half the claim, which is why the shot list cuts to Analytics for the second half. The line
itself needs no change.

### 5 — Scene 6: the Add Tenant form has no room/bed picker

Found while recording. The line says the owner enters details then selects "property, floor, room
మరియు available bed". The actual **Add Tenant** form is personal details only (name, mobile, gender,
email, Aadhaar, DOB, address, vehicle) ending at *Register Tenant*. Bed assignment is a **separate**
step — Vacant Beds → **Assign** — which scene 4 already shows.

Either cut scene 6 to cover both steps (register, then assign), or drop that clause from the
narration. Do not record the form alone while the line promises a bed picker.

### 4 — Scene 12: record Managers, not the Staff screen

This is the one that would actually mislead a viewer. There are two different things in the app:

- **Staff** (`/staff`, and the Staff quick action) is **payroll** — staff records and monthly salary
  payments. Staff there have **no logins at all** and no access to anything.
- **Access control** is **Settings → Team → Managers**: `PROPERTY_MANAGER` logins, each scoped to
  the specific properties assigned to them, which is exactly what Scene 12 describes.

The Telugu word "staff" in the script means the second one. Recording the Staff screen would show
payroll while the narration talks about access.

**Optional wording tweak:** if the video should match the on-screen label exactly, "staff కి" →
**"manager కి"** in both sentences, since the screen and the role are both called Manager. Only do
this if the client is happy to drop the more familiar word "staff".

---

## Deliverables checklist

- [ ] Telugu VO recorded, 14 scenes, one file per scene (easier to re-cut than a single take)
- [ ] Screen recordings at a consistent device size and orientation
- [ ] Scene 9 recorded on a device with WhatsApp installed, stopping before Send
- [ ] All four invoice states present in the demo data
- [ ] Accuracy notes 1–4 resolved with the client before the final mix
