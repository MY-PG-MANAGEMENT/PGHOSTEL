import '../services/api_client.dart';

/// Whether Tenant Login is enabled for the signed-in user's organization.
///
/// Tenant Login is an opt-in `organization_feature` toggled only by a super admin
/// (Admin Console → Messaging → the org's sheet), so every owner-side affordance
/// that only makes sense once tenants can sign in has to ask the server rather
/// than assume. `GET /tenants/login-feature` reads the same `TenantLoginPolicy`
/// the portal itself is gated on, so the app and the API cannot disagree.
///
/// Fails **closed**: a probe that throws returns false and the caller hides its
/// affordance. Showing an entry point that leads to a feature the org has not
/// been given is worse than briefly hiding one it has, and this matches the
/// long-standing behaviour of the Settings → Tenant Portal group.
Future<bool> fetchTenantLoginEnabled(ApiClient api) async {
  try {
    final data = await api.get('/tenants/login-feature');
    return data['enabled'] == true;
  } catch (_) {
    return false;
  }
}
