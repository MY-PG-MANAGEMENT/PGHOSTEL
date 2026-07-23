import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'src/app_state.dart';
import 'src/screens/auth/login_screen.dart';
import 'src/screens/account_screens.dart';
import 'src/screens/billing_screen.dart';
import 'src/screens/expenses_screen.dart';
import 'src/screens/staff_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/property_screen.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/tenant_screen.dart';
import 'src/screens/tenant/tenant_app.dart';
import 'src/screens/responsive_modules.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/tenant_theme.dart';
import 'src/widgets/app_toast.dart';

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
            navigatorKey: AppToast.navigatorKey,
            refreshListenable: state,
            initialLocation: '/',
            redirect: (context, routeState) {
              final loc = routeState.matchedLocation;
              final authRoutes = loc == '/login' || loc == '/forgot-password';
              final isSuper = state.roleTypeId == 'SUPER_ADMIN';
              final isTenant = state.roleTypeId == 'TENANT';
              // Tenant portal lives under /tenant (careful: owner route is /tenants, plural).
              final onTenantRoute = loc == '/tenant' || loc.startsWith('/tenant/');
              String home() => isSuper ? '/admin' : isTenant ? '/tenant' : '/dashboard';

              if (!state.initialized) return loc == '/' ? null : '/';
              if (loc == '/') return state.isLoggedIn ? home() : '/login';
              if (!state.isLoggedIn && !authRoutes) return '/login';
              if (state.isLoggedIn && authRoutes) return home();

              if (state.isLoggedIn && isTenant) {
                if (!onTenantRoute) return '/tenant';
                // Force the temporary-password change before anything else.
                if (state.mustChangePassword && loc != '/tenant/change-password') return '/tenant/change-password';
                return null;
              }
              // Non-tenants must never land on tenant routes.
              if (state.isLoggedIn && !isTenant && onTenantRoute) return home();

              if (state.isLoggedIn && isSuper && loc != '/admin') return '/admin';
              // Non-super-admins must never land on the admin console (every call 403s).
              if (state.isLoggedIn && !isSuper && loc == '/admin') return '/dashboard';
              return null;
            },
            routes: [
              GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
              GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
              GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
              GoRoute(path: '/dashboard', builder: (_, __) => const PgDashboardScreen()),
              GoRoute(path: '/dashboard/analytics', builder: (_, __) => const AnalyticsScreen()),
              GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
              GoRoute(path: '/properties', builder: (_, __) => const PropertyScreen()),
              GoRoute(path: '/tenants', builder: (_, __) => const TenantScreen()),
              GoRoute(path: '/tenants/manage', redirect: (_, __) => '/tenants'),
              GoRoute(path: '/billing', builder: (_, __) => const BillingScreen()),
              GoRoute(path: '/expenses', builder: (_, __) => const ExpensesScreen()),
              GoRoute(path: '/staff', builder: (_, __) => const StaffScreen()),
              GoRoute(path: '/billing/manage', redirect: (_, __) => '/billing'),
              GoRoute(path: '/payments', redirect: (_, __) => '/billing'),
              GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
              GoRoute(path: '/notifications/settings', builder: (_, __) => const NotificationSettingsScreen()),
              GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
              GoRoute(path: '/settings/profile', builder: (_, __) => const ProfileScreen()),
              GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen()),
              GoRoute(path: '/admin', builder: (_, __) => const SuperAdminScreen()),
              // ─── Tenant portal (Purple/White theme, Quick-Action nav) ───
              GoRoute(path: '/tenant', builder: (_, __) => _tenant(const TenantDashboardScreen())),
              GoRoute(path: '/tenant/change-password', builder: (_, __) => _tenant(const TenantChangePasswordScreen())),
              GoRoute(path: '/tenant/profile', builder: (_, __) => _tenant(const TenantProfileScreen())),
              GoRoute(path: '/tenant/payments', builder: (_, __) => _tenant(const TenantPaymentsScreen())),
              GoRoute(
                path: '/tenant/payments/history',
                builder: (_, s) => _tenant(TenantPaymentHistoryScreen(
                    history: ((s.extra as List?) ?? const []).cast<Map<String, dynamic>>())),
              ),
              GoRoute(path: '/tenant/complaints', builder: (_, __) => _tenant(const TenantComplaintsScreen())),
              GoRoute(path: '/tenant/complaints/new', builder: (_, __) => _tenant(const TenantRaiseComplaintScreen())),
              GoRoute(
                path: '/tenant/complaints/:id',
                builder: (_, s) => _tenant(TenantComplaintDetailScreen(complaintId: s.pathParameters['id']!)),
              ),
              GoRoute(path: '/tenant/notices', builder: (_, __) => _tenant(const TenantNoticesScreen())),
              GoRoute(
                path: '/tenant/notices/:id',
                builder: (_, s) => _tenant(TenantNoticeDetailScreen(noticeId: s.pathParameters['id']!)),
              ),
              GoRoute(path: '/tenant/notifications', builder: (_, __) => _tenant(const TenantNotificationsScreen())),
            ],
          );
          return MaterialApp.router(
            title: 'UrbanNest',
            theme: buildAppTheme(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}

/// Wraps a tenant screen in the Purple/White Material 3 theme so the tenant
/// experience is visually distinct from the owner/admin app.
Widget _tenant(Widget child) => Theme(data: buildTenantTheme(), child: child);
