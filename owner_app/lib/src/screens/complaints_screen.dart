import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/skeleton.dart';

/// Owner/manager view of tenant complaints, scoped to a single property.
/// Backed by `GET /api/complaints?propertyId=&status=`, `GET /api/complaints/{id}`,
/// and `PATCH /api/complaints/{id}/status`. Reached from the property workspace
/// Quick Actions grid.
class ComplaintsScreen extends StatefulWidget {
  final int? propertyId;
  final String? propertyName;
  const ComplaintsScreen({super.key, this.propertyId, this.propertyName});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

const _statusMeta = {
  'OPEN': ('Open', Color(0xFF2563EB)),
  'IN_PROGRESS': ('In Progress', Color(0xFFD97706)),
  'RESOLVED': ('Resolved', Color(0xFF16A34A)),
  'CLOSED': ('Closed', Color(0xFF6B7280)),
};

const _priorityMeta = {
  'HIGH': ('High', Color(0xFFDC2626)),
  'MEDIUM': ('Medium', Color(0xFFD97706)),
  'LOW': ('Low', Color(0xFF16A34A)),
};

String _pretty(String s) => s
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Builds a "Floor · Room · Bed" line from the complaint payload, tolerating
/// snake_case (list) or camelCase (detail) keys. Returns null when unassigned.
String? _location(Map<String, dynamic> m) {
  final floor = m['floor_name'] ?? m['floorName'];
  final room = m['room_name'] ?? m['roomName'];
  final bed = m['bed_name'] ?? m['bedName'];
  final parts = <String>[
    if (floor != null && '$floor'.isNotEmpty) 'Floor $floor',
    if (room != null && '$room'.isNotEmpty) 'Room $room',
    if (bed != null && '$bed'.isNotEmpty) 'Bed $bed',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse('$iso');
  if (d == null) return '$iso';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  late Future<Map<String, dynamic>> _future;
  String _filter = 'ALL';

  static const _filters = ['ALL', 'OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'];

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() {
    final params = <String>[];
    if (widget.propertyId != null) params.add('propertyId=${widget.propertyId}');
    if (_filter != 'ALL') params.add('status=$_filter');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    return context.read<AppState>().apiClient.get('/complaints$qs');
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _openDetail(Map<String, dynamic> complaint) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _ComplaintDetailScreen(complaintId: '${complaint['complaint_id']}'),
      ),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: PgColors.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Complaints', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            if (widget.propertyName != null)
              Text('${widget.propertyName}',
                  style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12, color: PgColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _reload),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: PgColors.hairline),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final selected = _filter == f;
                  final label = f == 'ALL' ? 'All' : _statusMeta[f]?.$1 ?? _pretty(f);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: selected,
                      selectedColor: PgColors.lavender,
                      checkmarkColor: PgColors.primary,
                      labelStyle: TextStyle(
                          color: selected ? PgColors.primary : null,
                          fontWeight: selected ? FontWeight.w700 : null),
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _reload();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1, color: PgColors.hairline),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SkeletonList(showLeading: false);
                }
                if (snap.hasError) {
                  return ErrorRetryView(error: snap.error!, onRetry: _reload);
                }
                final items = (snap.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
                if (items.isEmpty) {
                  return _empty();
                }
                return RefreshIndicator(
                  color: PgColors.primary,
                  onRefresh: () async => _reload(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ComplaintCard(
                      complaint: items[i],
                      onTap: () => _openDetail(items[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(42)),
            child: const Icon(Icons.support_agent_rounded, size: 38, color: PgColors.primary),
          ),
          const SizedBox(height: 16),
          Text(_filter == 'ALL' ? 'No complaints yet' : 'No ${_statusMeta[_filter]?.$1.toLowerCase() ?? ''} complaints',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PgColors.ink)),
          const SizedBox(height: 6),
          const Text('Complaints raised by tenants of this property will appear here.',
              textAlign: TextAlign.center, style: TextStyle(color: PgColors.textSecondary, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta[status] ?? (_pretty(status), PgColors.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: meta.$2.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: meta.$2.withValues(alpha: 0.25)),
      ),
      child: Text(meta.$1, style: TextStyle(color: meta.$2, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint, required this.onTap});
  final Map<String, dynamic> complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priority = '${complaint['priority'] ?? 'MEDIUM'}';
    final pMeta = _priorityMeta[priority] ?? ('—', PgColors.textSecondary);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: PgColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${complaint['title']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PgColors.ink)),
              ),
              _StatusChip('${complaint['status']}'),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.person_outline, size: 15, color: PgColors.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    '${complaint['tenant_name'] ?? 'Tenant'}${complaint['tenant_mobile'] != null ? ' • ${complaint['tenant_mobile']}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: PgColors.textSecondary)),
              ),
            ]),
            if (_location(complaint) != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.meeting_room_outlined, size: 15, color: PgColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_location(complaint)!,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: PgColors.textSecondary)),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Row(children: [
              _pill(_pretty('${complaint['category']}'), PgColors.textSecondary, const Color(0xFFF3F4F6)),
              const SizedBox(width: 8),
              _pill('${pMeta.$1} priority', pMeta.$2, pMeta.$2.withValues(alpha: 0.10)),
              const Spacer(),
              Text(_fmtDate(complaint['created_at']),
                  style: const TextStyle(fontSize: 11.5, color: PgColors.textTertiary)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );
}

// ─── Detail + status update ──────────────────────────────────────────────────

class _ComplaintDetailScreen extends StatefulWidget {
  const _ComplaintDetailScreen({required this.complaintId});
  final String complaintId;

  @override
  State<_ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<_ComplaintDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() =>
      context.read<AppState>().apiClient.get('/complaints/${widget.complaintId}');

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _updateStatus(String current) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StatusUpdateSheet(current: current),
    );
    if (result == null || !mounted) return;
    final (status, note) = result;
    try {
      await context.read<AppState>().apiClient.patch('/complaints/${widget.complaintId}/status', {
        'status': status,
        if (note.isNotEmpty) 'note': note,
      });
      _changed = true;
      if (mounted) {
        AppToast.success(context, 'Status updated to ${_statusMeta[status]?.$1 ?? status}');
        _reload();
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: PgColors.textPrimary,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, _changed)),
          title: const Text('Complaint', style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: PgColors.hairline),
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ErrorRetryView(error: snap.error!, onRetry: _reload);
            }
            final c = snap.data ?? {};
            final status = '${c['status'] ?? 'OPEN'}';
            final priority = '${c['priority'] ?? 'MEDIUM'}';
            final pMeta = _priorityMeta[priority] ?? ('—', PgColors.textSecondary);
            final history = (c['history'] as List? ?? []).cast<Map<String, dynamic>>();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${c['title']}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: PgColors.ink)),
                  ),
                  _StatusChip(status),
                ]),
                const SizedBox(height: 8),
                Text('${_pretty('${c['category']}')} • ${pMeta.$1} priority',
                    style: const TextStyle(color: PgColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                _card(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.person_outline, size: 18, color: PgColors.textTertiary),
                      const SizedBox(width: 8),
                      Text('${c['tenantName'] ?? 'Tenant'}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ]),
                    if (_location(c) != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.meeting_room_outlined, size: 18, color: PgColors.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_location(c)!,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: PgColors.ink)),
                        ),
                      ]),
                    ],
                    const Divider(height: 20),
                    Text('${c['description']}', style: const TextStyle(fontSize: 14, height: 1.4)),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text('Status Timeline',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: PgColors.ink)),
                const SizedBox(height: 12),
                ...history.asMap().entries.map((e) => _TimelineRow(entry: e.value, isLast: e.key == history.length - 1)),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                final status = '${snap.data?['status'] ?? 'OPEN'}';
                final closed = status == 'CLOSED';
                return FilledButton.icon(
                  onPressed: closed ? null : () => _updateStatus(status),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(closed ? 'Complaint closed' : 'Update status'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PgColors.primary,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PgColors.border),
        ),
        child: child,
      );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});
  final Map<String, dynamic> entry;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final to = '${entry['toStatus']}';
    final color = _statusMeta[to]?.$2 ?? PgColors.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          if (!isLast) Expanded(child: Container(width: 2, color: PgColors.border)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_statusMeta[to]?.$1 ?? _pretty(to),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: PgColors.ink)),
              const SizedBox(height: 2),
              Text(_fmtDate(entry['createdAt']), style: const TextStyle(color: PgColors.textTertiary, fontSize: 12)),
              if (entry['note'] != null && '${entry['note']}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${entry['note']}', style: const TextStyle(color: PgColors.textSecondary, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _StatusUpdateSheet extends StatefulWidget {
  const _StatusUpdateSheet({required this.current});
  final String current;
  @override
  State<_StatusUpdateSheet> createState() => _StatusUpdateSheetState();
}

class _StatusUpdateSheetState extends State<_StatusUpdateSheet> {
  late String _status;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.current;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: PgColors.ink)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _statusMeta.entries.map((e) {
            final selected = _status == e.key;
            return ChoiceChip(
              label: Text(e.value.$1),
              selected: selected,
              selectedColor: e.value.$2.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                  color: selected ? e.value.$2 : PgColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              onSelected: (_) => setState(() => _status = e.key),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add a note (optional)',
            filled: true,
            fillColor: const Color(0xFFF9F9FD),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: PgColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: PgColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: PgColors.primary)),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_status, _note.text.trim())),
          style: FilledButton.styleFrom(
            backgroundColor: PgColors.primary,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
