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
  final username = TextEditingController();
  final password = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('PG Manager', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username'), validator: required),
                    const SizedBox(height: 12),
                    TextFormField(controller: password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true, validator: required),
                    const SizedBox(height: 20),
                    AsyncActionButton(
                      label: 'Login',
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        await context.read<AppState>().login(username.text.trim(), password.text);
                        if (context.mounted) context.go('/dashboard');
                      },
                    ),
                    TextButton(onPressed: () => context.go('/register'), child: const Text('Create owner account')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
}
