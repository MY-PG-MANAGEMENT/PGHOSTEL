import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class OccupancyScreen extends StatefulWidget {
  const OccupancyScreen({super.key});

  @override
  State<OccupancyScreen> createState() => _OccupancyScreenState();
}

class _OccupancyScreenState extends State<OccupancyScreen> {
  final partyId = TextEditingController();
  final bedId = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Occupancy',
      child: ListView(
        children: [
          TextField(controller: partyId, decoration: const InputDecoration(labelText: 'Tenant Party ID')),
          TextField(controller: bedId, decoration: const InputDecoration(labelText: 'Bed Facility ID')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AsyncActionButton(
                label: 'Assign Bed',
                onPressed: () async {
                  await context.read<AppState>().apiClient.post('/occupancy/assign-bed', {
                    'partyId': int.parse(partyId.text),
                    'bedFacilityId': int.parse(bedId.text),
                  });
                },
              ),
              AsyncActionButton(
                label: 'Transfer Bed',
                onPressed: () async {
                  await context.read<AppState>().apiClient.post('/occupancy/transfer-bed', {
                    'partyId': int.parse(partyId.text),
                    'newBedFacilityId': int.parse(bedId.text),
                  });
                },
              ),
              AsyncActionButton(
                label: 'Checkout',
                onPressed: () async {
                  await context.read<AppState>().apiClient.post('/occupancy/checkout', {
                    'partyId': int.parse(partyId.text),
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
