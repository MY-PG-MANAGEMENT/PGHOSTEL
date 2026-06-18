import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Future<Map<String, dynamic>> payments;
  final rentId = TextEditingController();
  final partyId = TextEditingController();
  final amount = TextEditingController();
  String mode = 'CASH';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    payments = context.read<AppState>().apiClient.get('/payments');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Payments',
      child: ListView(
        children: [
          TextField(controller: rentId, decoration: const InputDecoration(labelText: 'Rent ID')),
          TextField(controller: partyId, decoration: const InputDecoration(labelText: 'Tenant Party ID')),
          TextField(controller: amount, decoration: const InputDecoration(labelText: 'Amount')),
          DropdownButtonFormField<String>(
            value: mode,
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('Cash')),
              DropdownMenuItem(value: 'UPI', child: Text('UPI')),
              DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank Transfer')),
              DropdownMenuItem(value: 'CARD', child: Text('Card')),
            ],
            onChanged: (value) => setState(() => mode = value ?? mode),
          ),
          const SizedBox(height: 12),
          AsyncActionButton(
            label: 'Record Payment',
            onPressed: () async {
              await context.read<AppState>().apiClient.post('/payments', {
                'rentId': int.parse(rentId.text),
                'partyId': int.parse(partyId.text),
                'amount': double.parse(amount.text),
                'paymentMode': mode,
              });
              setState(refresh);
            },
          ),
          const Divider(height: 32),
          FutureBuilder<Map<String, dynamic>>(
            future: payments,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final items = (snapshot.data?['items'] as List? ?? []);
              return Column(
                children: items.map((item) {
                  final payment = item as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text('Payment ID: ${payment['paymentId']} | ${payment['amount']}'),
                    subtitle: Text('${payment['paymentMode']} | Tenant: ${payment['partyId']}'),
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
