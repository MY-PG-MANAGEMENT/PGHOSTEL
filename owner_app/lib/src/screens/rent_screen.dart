import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class RentScreen extends StatefulWidget {
  const RentScreen({super.key});

  @override
  State<RentScreen> createState() => _RentScreenState();
}

class _RentScreenState extends State<RentScreen> {
  late Future<Map<String, dynamic>> rents;
  final partyId = TextEditingController();
  final amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    rents = context.read<AppState>().apiClient.get('/rents');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Rents',
      child: ListView(
        children: [
          TextField(controller: partyId, decoration: const InputDecoration(labelText: 'Tenant Party ID')),
          TextField(controller: amount, decoration: const InputDecoration(labelText: 'Monthly Rent')),
          const SizedBox(height: 12),
          AsyncActionButton(
            label: 'Create Rent',
            onPressed: () async {
              final now = DateTime.now();
              await context.read<AppState>().apiClient.post('/rents', {
                'partyId': int.parse(partyId.text),
                'rentMonth': '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
                'monthlyRent': double.parse(amount.text),
                'deposit': 0,
                'advance': 0,
                'discount': 0,
                'penalty': 0,
              });
              setState(refresh);
            },
          ),
          const Divider(height: 32),
          FutureBuilder<Map<String, dynamic>>(
            future: rents,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final items = (snapshot.data?['items'] as List? ?? []);
              return Column(
                children: items.map((item) {
                  final rent = item as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('Rent ID: ${rent['rentId']} | Tenant: ${rent['partyId']}'),
                    subtitle: Text('Due: ${rent['pendingAmount']} | Status: ${rent['status']}'),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
