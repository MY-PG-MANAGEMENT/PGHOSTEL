import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

class FacilityScreen extends StatefulWidget {
  const FacilityScreen({super.key});

  @override
  State<FacilityScreen> createState() => _FacilityScreenState();
}

class _FacilityScreenState extends State<FacilityScreen> {
  late Future<Map<String, dynamic>> tree;
  final parentId = TextEditingController();
  final name = TextEditingController();
  String type = 'ROOM';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    tree = context.read<AppState>().apiClient.get('/facilities/tree');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Facilities',
      child: ListView(
        children: [
          Text('Add Facility', style: Theme.of(context).textTheme.titleMedium),
          TextField(controller: parentId, decoration: const InputDecoration(labelText: 'Parent Facility ID')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Facility Name')),
          DropdownButtonFormField<String>(
            value: type,
            items: const [
              DropdownMenuItem(value: 'PROPERTY', child: Text('Property')),
              DropdownMenuItem(value: 'FLOOR', child: Text('Floor')),
              DropdownMenuItem(value: 'ROOM', child: Text('Room')),
              DropdownMenuItem(value: 'BED', child: Text('Bed')),
            ],
            onChanged: (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 12),
          AsyncActionButton(
            label: 'Create Facility',
            onPressed: () async {
              await context.read<AppState>().apiClient.post('/facilities', {
                'parentFacilityId': int.parse(parentId.text),
                'facilityTypeId': type,
                'facilityName': name.text,
              });
              setState(refresh);
            },
          ),
          const Divider(height: 32),
          FutureBuilder<Map<String, dynamic>>(
            future: tree,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return facilityTile(snapshot.data!);
            },
          ),
        ],
      ),
    );
  }

  Widget facilityTile(Map<String, dynamic> item) {
    final children = (item['children'] as List? ?? []).cast<Map<String, dynamic>>();
    return ExpansionTile(
      initiallyExpanded: item['facilityTypeId'] == 'ORGANIZATION',
      title: Text('${item['facilityName']}'),
      subtitle: Text('${item['facilityTypeId']} | ID: ${item['facilityId']}'),
      children: children.map(facilityTile).toList(),
    );
  }
}
