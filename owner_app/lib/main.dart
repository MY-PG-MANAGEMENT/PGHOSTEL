import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'src/app_state.dart';
import 'src/screens/auth/login_screen.dart';
import 'src/screens/auth/register_screen.dart';
import 'src/screens/account_screens.dart';
import 'src/screens/facility_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/occupancy_screen.dart';
import 'src/screens/payment_screen.dart';
import 'src/screens/rent_screen.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/tenant_screen.dart';
import 'src/screens/responsive_modules.dart';
import 'src/theme/app_theme.dart';

void main() {
  runApp(const PgManagerOwnerApp());
}

class PgManagerOwnerApp extends StatelessWidget {
  const PgManagerOwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..restoreSession(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final router = GoRouter(
            refreshListenable: state,
            initialLocation: '/',
            redirect: (context, routeState) {
              final authRoutes = routeState.matchedLocation == '/login' || routeState.matchedLocation == '/register' || routeState.matchedLocation == '/forgot-password';
              if (!state.initialized) return routeState.matchedLocation == '/' ? null : '/';
              if (routeState.matchedLocation == '/') return state.isLoggedIn ? (state.roleTypeId == 'SUPER_ADMIN' ? '/admin' : '/dashboard') : '/login';
              if (!state.isLoggedIn && !authRoutes) return '/login';
              if (state.isLoggedIn && authRoutes) return state.roleTypeId == 'SUPER_ADMIN' ? '/admin' : '/dashboard';
              if (state.isLoggedIn && state.roleTypeId == 'SUPER_ADMIN' && routeState.matchedLocation != '/admin') return '/admin';
              return null;
            },
            routes: [
              GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
              GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
              GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
              GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
              GoRoute(path: '/dashboard', builder: (_, __) => const PgDashboardScreen()),
              GoRoute(path: '/dashboard/analytics', builder: (_, __) => const AnalyticsScreen()),
              GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
              GoRoute(path: '/properties', builder: (_, __) => const ModuleOverviewScreen(
                title: 'Properties', endpoint: '/owner/properties', features: [
                  ModuleFeature('Property List', 'Search and review all properties', Icons.apartment_outlined),
                  ModuleFeature('Add Property', 'Create a property and its address', Icons.add_business, path: '/properties/manage'),
                  ModuleFeature('Floors', 'Maintain the property hierarchy', Icons.layers_outlined, path: '/properties/manage'),
                  ModuleFeature('Amenities', 'Configure available services', Icons.wifi_outlined),
                  ModuleFeature('Property Photos', 'Future media capability', Icons.photo_library_outlined, disabled: true),
                ],
              )),
              GoRoute(path: '/properties/manage', builder: (_, __) => const FacilityScreen()),
              GoRoute(path: '/facilities', redirect: (_, __) => '/properties'),
              GoRoute(path: '/rooms', builder: (_, __) => const ModuleOverviewScreen(
                title: 'Room Management', endpoint: '/facilities/tree', features: [
                  ModuleFeature('Room List', 'Filter occupied and vacant rooms', Icons.meeting_room_outlined, path: '/properties/manage'),
                  ModuleFeature('Room Details', 'Pricing, capacity and occupancy', Icons.bedroom_parent_outlined),
                  ModuleFeature('Bed Details', 'Review bed assignments', Icons.bed_outlined, path: '/occupancy'),
                  ModuleFeature('Assign Tenant', 'Assign an available bed', Icons.person_add_alt, path: '/occupancy'),
                  ModuleFeature('Room Photos', 'Future media capability', Icons.photo_library_outlined, disabled: true),
                ],
              )),
              GoRoute(path: '/tenants', builder: (_, __) => const ModuleOverviewScreen(
                title: 'Tenant Management', endpoint: '/tenants', features: [
                  ModuleFeature('Tenant List', 'Search active and inactive tenants', Icons.people_outline, path: '/tenants/manage'),
                  ModuleFeature('Personal Details', 'Maintain tenant identity information', Icons.badge_outlined, path: '/tenants/manage'),
                  ModuleFeature('ID Documents', 'Metadata only until storage is enabled', Icons.perm_identity, disabled: true),
                  ModuleFeature('Emergency Contact', 'Primary and secondary contacts', Icons.contact_emergency_outlined),
                  ModuleFeature('Job Information', 'Employment and income profile', Icons.work_outline),
                  ModuleFeature('New Admission', 'Room, rent, documents and review', Icons.how_to_reg_outlined, path: '/occupancy'),
                  ModuleFeature('Agreement', 'Terms and signing lifecycle', Icons.description_outlined),
                  ModuleFeature('Checkout', 'Close occupancy and calculate dues', Icons.exit_to_app),
                  ModuleFeature('Deposit Settlement', 'Record cash refund settlement', Icons.account_balance_wallet_outlined),
                ],
              )),
              GoRoute(path: '/tenants/manage', builder: (_, __) => const TenantScreen()),
              GoRoute(path: '/occupancy', builder: (_, __) => const OccupancyScreen()),
              GoRoute(path: '/rents', builder: (_, __) => const RentScreen()),
              GoRoute(path: '/billing', builder: (_, __) => const ModuleOverviewScreen(
                title: 'Payment Management', endpoint: '/billing/dashboard', features: [
                  ModuleFeature('Payment Dashboard', 'Collections and outstanding balances', Icons.dashboard_outlined),
                  ModuleFeature('Payment Details', 'Invoice charge breakdown', Icons.receipt_long_outlined),
                  ModuleFeature('Collect Cash', 'Record an idempotent cash payment', Icons.currency_rupee, path: '/billing/manage'),
                  ModuleFeature('Payment Methods', 'Cash enabled; gateways future-ready', Icons.payments_outlined),
                  ModuleFeature('Payment History', 'Payments, refunds and receipts', Icons.history),
                  ModuleFeature('Pending Dues', 'Outstanding and overdue invoices', Icons.warning_amber),
                  ModuleFeature('Receipt', 'Server-generated receipt data', Icons.receipt_outlined),
                  ModuleFeature('Advance Payment', 'Maintain tenant advance balance', Icons.savings_outlined),
                ],
              )),
              GoRoute(path: '/billing/manage', builder: (_, __) => const PaymentScreen()),
              GoRoute(path: '/payments', redirect: (_, __) => '/billing'),
              GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
              GoRoute(path: '/notifications/settings', builder: (_, __) => const NotificationSettingsScreen()),
              GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
              GoRoute(path: '/settings/profile', builder: (_, __) => const ProfileScreen()),
              GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen()),
              GoRoute(path: '/admin', builder: (_, __) => const SuperAdminScreen()),
            ],
          );
          return MaterialApp.router(
            title: 'PG Manager',
            theme: buildAppTheme(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
