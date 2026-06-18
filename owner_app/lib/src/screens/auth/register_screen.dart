import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../widgets/async_action_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final fullName = TextEditingController();
  final mobile = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final orgName = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Owner Registration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Form(
              key: formKey,
              child: Column(
                children: [
                  field(fullName, 'Full Name'),
                  field(mobile, 'Mobile Number'),
                  field(username, 'Username'),
                  field(password, 'Password', obscure: true),
                  field(orgName, 'Organization Name'),
                  const SizedBox(height: 16),
                  AsyncActionButton(
                    label: 'Register',
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      await context.read<AppState>().registerOwner(
                            fullName: fullName.text.trim(),
                            mobileNumber: mobile.text.trim(),
                            username: username.text.trim(),
                            password: password.text,
                            organizationName: orgName.text.trim(),
                          );
                      if (context.mounted) context.go('/onboarding');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget field(TextEditingController controller, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
        validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
      ),
    );
  }
}
