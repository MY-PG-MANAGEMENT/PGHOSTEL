import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool multiple = false;
  double properties = 1;
  double floors = 1;
  double rooms = 4;
  double beds = 2;
  String sharingType = 'TWO_SHARING';
  final enabledFeatures = <String>{};

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Onboarding Wizard',
      child: ListView(
        children: [
          SwitchListTile(title: const Text('Multiple PGs'), value: multiple, onChanged: (value) => setState(() => multiple = value)),
          slider('Properties', properties, 1, 10, (value) => setState(() => properties = value)),
          slider('Floors', floors, 1, 10, (value) => setState(() => floors = value)),
          slider('Rooms per floor', rooms, 1, 30, (value) => setState(() => rooms = value)),
          slider('Beds per room', beds, 1, 8, (value) => setState(() => beds = value)),
          DropdownButtonFormField<String>(
            value: sharingType,
            decoration: const InputDecoration(labelText: 'Sharing Type'),
            items: const [
              DropdownMenuItem(value: 'SINGLE', child: Text('Single')),
              DropdownMenuItem(value: 'TWO_SHARING', child: Text('Two Sharing')),
              DropdownMenuItem(value: 'THREE_SHARING', child: Text('Three Sharing')),
              DropdownMenuItem(value: 'FOUR_SHARING', child: Text('Four Sharing')),
            ],
            onChanged: (value) => setState(() => sharingType = value ?? sharingType),
          ),
          const SizedBox(height: 12),
          feature('EXPENSE', 'Expense Module'),
          feature('NOTIFICATION', 'Notification Module'),
          feature('WHATSAPP', 'WhatsApp Module'),
          const SizedBox(height: 16),
          AsyncActionButton(
            label: 'Create Setup',
            onPressed: () async {
              await context.read<AppState>().apiClient.post('/owner/onboarding-wizard', {
                'multipleProperties': multiple,
                'numberOfProperties': properties.round(),
                'numberOfFloors': floors.round(),
                'numberOfRooms': rooms.round(),
                'bedsPerRoom': beds.round(),
                'sharingType': sharingType,
                'enabledFeatureCodes': enabledFeatures.toList(),
              });
              if (context.mounted) context.go('/dashboard');
            },
          ),
        ],
      ),
    );
  }

  Widget slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${value.round()}'),
      Slider(value: value, min: min, max: max, divisions: (max - min).round(), onChanged: onChanged),
    ]);
  }

  Widget feature(String code, String label) {
    return CheckboxListTile(
      title: Text(label),
      value: enabledFeatures.contains(code),
      onChanged: (value) => setState(() => value == true ? enabledFeatures.add(code) : enabledFeatures.remove(code)),
    );
  }
}
