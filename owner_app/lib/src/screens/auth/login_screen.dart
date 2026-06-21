import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../widgets/async_action_button.dart';

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

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Text('PG Manager', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Sign in to your account', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      validator: _required,
                    ),
                    const SizedBox(height: 20),
                    AsyncActionButton(
                      label: 'Login',
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        try {
                          await context.read<AppState>().login(
                            _username.text.trim(),
                            _password.text,
                          );
                          if (context.mounted) context.go('/dashboard');
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString().replaceFirst('Exception: ', '')),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () => context.go('/forgot-password'),
                      child: const Text('Forgot password?'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await context.read<AppState>().biometricLogin();
                        if (ok && context.mounted) context.go('/dashboard');
                      },
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with device security'),
                    ),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Create owner account'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
