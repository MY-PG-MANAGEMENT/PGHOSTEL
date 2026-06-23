import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.title, required this.child, this.actions = const [], super.key});

  final String title;
  final Widget child;
  final List<Widget> actions;

  static const destinations = <_Destination>[
    _Destination('Dashboard', '/dashboard', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('Properties', '/properties', Icons.apartment_outlined, Icons.apartment),
    _Destination('Tenants', '/tenants', Icons.people_outline, Icons.people),
    _Destination('Payments', '/billing', Icons.currency_rupee_outlined, Icons.currency_rupee),
    _Destination('Notifications', '/notifications', Icons.notifications_outlined, Icons.notifications),
    _Destination('Settings', '/settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final isAdmin = context.watch<AppState>().roleTypeId == 'SUPER_ADMIN';
    final items = isAdmin
        ? const [_Destination('Admin', '/admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings)]
        : destinations;
    final selected = _selectedIndex(path, items);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = Column(
      children: [
        Container(
          height: 72,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            if (!wide) Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer())),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            ...actions,
            IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: Padding(padding: EdgeInsets.all(wide ? 24 : 14), child: child)),
      ],
    );

    return Scaffold(
      drawer: wide ? null : Drawer(child: SafeArea(child: _DrawerNavigation(items: items, selected: selected))),
      body: SafeArea(
        child: Row(children: [
          if (wide) _Sidebar(items: items, selected: selected),
          Expanded(child: content),
        ]),
      ),
      bottomNavigationBar: wide || isAdmin
          ? null
          : NavigationBar(
              selectedIndex: selected.clamp(0, 4),
              onDestinationSelected: (index) => context.go(items[index].path),
              destinations: items.take(5).map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)).toList(),
            ),
    );
  }

  int _selectedIndex(String path, List<_Destination> items) {
    final index = items.indexWhere((d) => path == d.path || path.startsWith('${d.path}/'));
    return index < 0 ? 0 : index;
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.selected});
  final List<_Destination> items;
  final int selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 236,
        color: Colors.white,
        child: Column(children: [
          const SizedBox(height: 28),
          const ListTile(
            leading: CircleAvatar(backgroundColor: PgColors.primary, child: Icon(Icons.shield_outlined, color: Colors.white)),
            title: Text('PG Manager', style: TextStyle(fontWeight: FontWeight.w800, color: PgColors.primaryDark)),
          ),
          const SizedBox(height: 18),
          ...items.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: ListTile(
                  selected: entry.key == selected,
                  selectedTileColor: PgColors.lavender,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(entry.key == selected ? entry.value.selectedIcon : entry.value.icon),
                  title: Text(entry.value.label),
                  onTap: () => context.go(entry.value.path),
                ),
              )),
          const Spacer(),
          ListTile(leading: const Icon(Icons.logout, color: PgColors.danger), title: const Text('Logout'), onTap: () async {
            await context.read<AppState>().logout();
            if (context.mounted) context.go('/login');
          }),
          const SizedBox(height: 16),
        ]),
      );
}

class _DrawerNavigation extends StatelessWidget {
  const _DrawerNavigation({required this.items, required this.selected});
  final List<_Destination> items;
  final int selected;

  @override
  Widget build(BuildContext context) => ListView(children: [
        const ListTile(title: Text('PG Manager', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PgColors.primary))),
        ...items.asMap().entries.map((entry) => ListTile(
              selected: entry.key == selected,
              leading: Icon(entry.value.icon),
              title: Text(entry.value.label),
              onTap: () { Navigator.pop(context); context.go(entry.value.path); },
            )),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: () async {
          await context.read<AppState>().logout();
          if (context.mounted) context.go('/login');
        }),
      ]);
}

class _Destination {
  const _Destination(this.label, this.path, this.icon, this.selectedIcon);
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}
