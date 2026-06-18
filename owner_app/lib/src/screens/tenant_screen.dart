import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class TenantScreen extends StatefulWidget {
  const TenantScreen({super.key});

  @override
  State<TenantScreen> createState() => _TenantScreenState();
}

class _TenantScreenState extends State<TenantScreen> {
  late Future<Map<String, dynamic>> tenants;
  final name = TextEditingController();
  final mobile = TextEditingController();
  final guardian = TextEditingController();
  final guardianMobile = TextEditingController();
  final address = TextEditingController();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    tenants = context.read<AppState>().apiClient.get('/tenants');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Tenants',
      child: ListView(
        children: [
          Text('Add Tenant', style: Theme.of(context).textTheme.titleMedium),
          field(name, 'Full Name'),
          field(mobile, 'Mobile Number'),
          field(guardian, 'Guardian Name'),
          field(guardianMobile, 'Guardian Mobile'),
          field(address, 'Address'),
          AsyncActionButton(
            label: 'Create Tenant',
            onPressed: () async {
              await context.read<AppState>().apiClient.post('/tenants', {
                'fullName': name.text,
                'mobileNumber': mobile.text,
                'guardianName': guardian.text,
                'guardianMobileNumber': guardianMobile.text,
                'address': address.text,
              });
              name.clear();
              mobile.clear();
              setState(refresh);
            },
          ),
          const Divider(height: 32),
          FutureBuilder<Map<String, dynamic>>(
            future: tenants,
            builder: (context, snapshot) {
              final items = (snapshot.data?['items'] as List? ?? []);
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return Column(
                children: items.map((item) {
                  final tenant = item as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('${tenant['fullName']}'),
                    subtitle: Text('ID: ${tenant['partyId']} | ${tenant['mobileNumber']}'),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(controller: controller, decoration: InputDecoration(labelText: label)),
    );
  }
}
