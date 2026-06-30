import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/async_action_button.dart';
import 'auth_brand_header.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullName = TextEditingController();
  final _mobile = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _orgName = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _fullName.dispose();
    _mobile.dispose();
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _orgName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF3730A3),
                  Color(0xFF7C3AED),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Column(
        children: [
          AuthBrandHeader(
            subtitle: 'Set up your owner account',
            onBack: () => context.go('/login'),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: PgColors.scaffold,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Form(
                key: _formKey,
                child: FadeSlideIn(
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  children: [
                    Text(
                      'Create account',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: PgColors.ink,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your properties, tenants, and payments — all in one place.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: PgColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    _field(
                      _fullName,
                      'Full Name',
                      prefixIcon: Icons.person_outline,
                      textInputAction: TextInputAction.next,
                      validator: _validateName,
                    ),
                    _field(
                      _mobile,
                      'Mobile Number',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      textInputAction: TextInputAction.next,
                      validator: _validateMobile,
                    ),
                    _field(
                      _username,
                      'Username',
                      prefixIcon: Icons.alternate_email,
                      textInputAction: TextInputAction.next,
                      validator: _validateUsername,
                    ),
                    _passwordField(
                      _password,
                      'Password',
                      obscure: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      textInputAction: TextInputAction.next,
                      validator: _validatePassword,
                    ),
                    _passwordField(
                      _confirmPassword,
                      'Confirm Password',
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v != _password.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    _field(
                      _orgName,
                      'Organization Name',
                      prefixIcon: Icons.business_outlined,
                      textInputAction: TextInputAction.done,
                      validator: _validateRequired,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: AsyncActionButton(
                        label: 'Create Account',
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          try {
                            await context.read<AppState>().registerOwner(
                                  fullName: _fullName.text.trim(),
                                  mobileNumber: _mobile.text.trim(),
                                  username: _username.text.trim(),
                                  password: _password.text,
                                  organizationName: _orgName.text.trim(),
                                );
                            if (context.mounted) context.go('/onboarding');
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      e.toString().replaceFirst('Exception: ', '')),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account?',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: PgColors.textSecondary,
                              ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ],
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

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData? prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        ),
        validator: validator,
      ),
    );
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    required bool obscure,
    required VoidCallback onToggle,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: onToggle,
          ),
        ),
        validator: validator,
      ),
    );
  }

  String? _validateRequired(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (v.trim().length < 2) return 'Must be at least 2 characters';
    return null;
  }

  String? _validateMobile(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!RegExp(r'^[0-9]{10}$').hasMatch(v.trim()))
      return 'Enter a valid 10-digit mobile number';
    return null;
  }

  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (v.trim().length < 4) return 'Must be at least 4 characters';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
      return 'Only letters, digits, and underscores';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    if (v.length < 8) return 'Must be at least 8 characters';
    return null;
  }
}
