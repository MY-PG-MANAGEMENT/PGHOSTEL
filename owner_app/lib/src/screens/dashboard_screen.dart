import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> summary;

  @override
  void initState() {
    super.initState();
    summary = context.read<AppState>().apiClient.get('/owner/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Owner Dashboard',
      child: FutureBuilder<Map<String, dynamic>>(
        future: summary,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};
          return ListView(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  stat('Total Beds', data['totalBeds']),
                  stat('Occupied', data['occupiedBeds']),
                  stat('Vacant', data['vacantBeds']),
                  stat('Tenants', data['totalTenants']),
                  stat('Pending Rent', data['pendingRent']),
                  stat('Revenue', data['revenue']),
                ],
              ),
              const SizedBox(height: 24),
              nav(context, 'Onboarding Wizard', '/onboarding', Icons.tune),
              nav(context, 'Facilities', '/facilities', Icons.meeting_room_outlined),
              nav(context, 'Tenants', '/tenants', Icons.people_outline),
              nav(context, 'Occupancy', '/occupancy', Icons.bed_outlined),
              nav(context, 'Rents', '/rents', Icons.receipt_long_outlined),
              nav(context, 'Payments', '/payments', Icons.payments_outlined),
            ],
          );
        },
      ),
    );
  }

  Widget stat(String label, Object? value) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label),
            const SizedBox(height: 8),
            Text('${value ?? '-'}', style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
      ),
    );
  }

  Widget nav(BuildContext context, String label, String route, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(route),
    );
  }
}
