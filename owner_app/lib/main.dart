import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'src/app_state.dart';
import 'src/screens/auth/login_screen.dart';
import 'src/screens/account_screens.dart';
import 'src/screens/billing_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/property_screen.dart';
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
              final authRoutes = routeState.matchedLocation == '/login' || routeState.matchedLocation == '/forgot-password';
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
              GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
              GoRoute(path: '/dashboard', builder: (_, __) => const PgDashboardScreen()),
              GoRoute(path: '/dashboard/analytics', builder: (_, __) => const AnalyticsScreen()),
              GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
              GoRoute(path: '/properties', builder: (_, __) => const PropertyScreen()),
              GoRoute(path: '/tenants', builder: (_, __) => const TenantScreen()),
              GoRoute(path: '/tenants/manage', redirect: (_, __) => '/tenants'),
              GoRoute(path: '/billing', builder: (_, __) => const BillingScreen()),
              GoRoute(path: '/billing/manage', redirect: (_, __) => '/billing'),
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
            title: 'UrbanNest',
            theme: buildAppTheme(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
