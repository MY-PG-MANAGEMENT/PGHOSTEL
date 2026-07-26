import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_exception.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/async_action_button.dart';
import 'auth_brand_header.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AppState>().canUseBiometricUnlock();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Single sign-in field. Tries the standard username login; if that fails and
  /// the entry is a 10-digit mobile number, falls back to tenant login (so
  /// tenants sign in with the same field — no mode selector).
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final id = _username.text.trim();
    final state = context.read<AppState>();
    try {
      await state.login(id, _password.text);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      Object error = e;
      if (RegExp(r'^\d{10}$').hasMatch(id) && error is! AccessDeniedException) {
        try {
          var result = await state.tenantLogin(id, _password.text);
          if (result['needsOrgSelection'] == true) {
            final orgs = ((result['organizations'] as List?) ?? []).cast<Map<String, dynamic>>();
            final chosen = await _pickOrganization(orgs);
            if (chosen == null) return;
            result = await state.tenantLogin(id, _password.text, organizationId: chosen);
            if (result['needsOrgSelection'] == true) return;
          }
          if (mounted) context.go('/tenant');
          return;
        } catch (tenantError) {
          // A tenant mobile always fails the username login with a generic credentials error, so
          // "your organization is deactivated" only ever arrives from the tenant attempt — show it
          // instead of the misleading original. (The owner attempt's own 403 skips this path above.)
          if (tenantError is AccessDeniedException) error = tenantError;
        }
      }
      if (mounted) AppToast.error(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<int?> _pickOrganization(List<Map<String, dynamic>> orgs) {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Select your PG', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ),
          ...orgs.map((o) => ListTile(
                leading: const Icon(Icons.home_work_outlined, color: PgColors.primary),
                title: Text('${o['organizationName'] ?? 'Organization'}'),
                onTap: () => Navigator.pop(ctx, (o['organizationId'] as num?)?.toInt()),
              )),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen dark gradient — matches brand header
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF3730A3), // vibrant indigo
                  Color(0xFF7C3AED), // bright violet
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Column(
            children: [
              const AuthBrandHeader(subtitle: 'Manage. Simplify. Grow.'),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Form(
                      key: _formKey,
                      child: FadeSlideIn(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome back',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F0A2A),
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to manage your properties',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: PgColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 28),
                            // Username field
                            TextFormField(
                              controller: _username,
                              decoration: InputDecoration(
                                hintText: 'Username',
                                prefixIcon: const Icon(Icons.person_outline),
                                prefixIconColor: PgColors.primary,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: PgColors.primary, width: 1.5),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFDC2626)),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: _required,
                            ),
                            const SizedBox(height: 14),
                            // Password field
                            TextFormField(
                              controller: _password,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                prefixIconColor: PgColors.primary,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: PgColors.primary,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: PgColors.primary, width: 1.5),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFDC2626)),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                              ),
                              textInputAction: TextInputAction.done,
                              validator: _required,
                            ),
                            // Forgot password
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.go('/forgot-password'),
                                style: TextButton.styleFrom(
                                  foregroundColor: PgColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                                ),
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Sign in button
                            SizedBox(
                              height: 54,
                              child: AsyncActionButton(
                                label: 'Sign in',
                                onPressed: _signIn,
                              ),
                            ),
                            // Biometric unlock
                            if (_biometricAvailable) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final ok =
                                      await context.read<AppState>().biometricLogin();
                                  if (ok && context.mounted) context.go('/dashboard');
                                },
                                icon: const Pulse(child: Icon(Icons.fingerprint)),
                                label: const Text('Unlock with device security'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ],
                            // Footer
                            const SizedBox(height: 36),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.gpp_good_outlined,
                                  size: 17,
                                  color: PgColors.textTertiary,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Secure. Reliable. Always.',
                                  style: TextStyle(
                                    color: PgColors.textTertiary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
