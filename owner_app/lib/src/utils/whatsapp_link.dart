/// WhatsApp Click-to-Chat deep links.
///
/// **This file is the whole of Phase 1's delivery mechanism, and the only part Phase 2
/// deletes.** Everything about *what* a reminder says — the reminder type, the outstanding
/// amount, the wording, the recipient — is decided by the backend and arrives on the
/// invoice-detail payload as `reminder`. All that happens here is turning a number and a
/// message into a `wa.me` URL.
///
/// Keeping it in one small, testable place is what makes the swap cheap later: when the
/// backend starts sending through the Cloud API, the invoice sheet stops calling
/// [whatsAppChatUri] and calls an endpoint instead. No reminder logic moves.
library;

/// The Click-to-Chat URI for [phoneE164Digits] with [message] pre-filled.
///
/// [phoneE164Digits] must already be digits-only with a country code — the backend
/// normalises it (`PhoneNumberNormalizer`), because the same normalisation is needed by
/// Phase 2 and duplicating it in Dart would mean two implementations to keep in step.
///
/// Returns null when the number is missing or empty, so a caller cannot accidentally open
/// WhatsApp's contact picker on a blank number and message the wrong person.
Uri? whatsAppChatUri(String? phoneE164Digits, String? message) {
  final digits = (phoneE164Digits ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  if (message == null || message.isEmpty) {
    return Uri.parse('https://wa.me/$digits');
  }

  // Encoded with `encodeComponent`, NOT via `Uri.https(..., queryParameters: ...)`.
  //
  // Dart's `queryParameters` applies form encoding, which turns every space into `+`. That is
  // valid `application/x-www-form-urlencoded`, but `wa.me` does not reliably read `+` back as a
  // space, so the pre-filled message can arrive full of plus signs. `encodeComponent` percent-
  // encodes instead (`%20` for space, `%0A` for the newlines, `%E2%82%B9` for the ₹), which is
  // what the Click-to-Chat URL expects.
  //
  // `Uri.parse` keeps existing percent-escapes in the query verbatim, so this encodes exactly
  // once — no double-encoding.
  return Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
}
