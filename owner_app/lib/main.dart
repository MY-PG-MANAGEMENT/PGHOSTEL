import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'src/app_state.dart';
import 'src/screens/auth/login_screen.dart';
import 'src/screens/auth/register_screen.dart';
import 'src/screens/dashboard_screen.dart';
import 'src/screens/facility_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/occupancy_screen.dart';
import 'src/screens/payment_screen.dart';
import 'src/screens/rent_screen.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/tenant_screen.dart';

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
              final authRoutes = routeState.matchedLocation == '/login' || routeState.matchedLocation == '/register';
              if (!state.initialized) return routeState.matchedLocation == '/' ? null : '/';
              if (routeState.matchedLocation == '/') return state.isLoggedIn ? '/dashboard' : '/login';
              if (!state.isLoggedIn && !authRoutes) return '/login';
              if (state.isLoggedIn && authRoutes) return '/dashboard';
              return null;
            },
            routes: [
              GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
              GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
              GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
              GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
              GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
              GoRoute(path: '/facilities', builder: (_, __) => const FacilityScreen()),
              GoRoute(path: '/tenants', builder: (_, __) => const TenantScreen()),
              GoRoute(path: '/occupancy', builder: (_, __) => const OccupancyScreen()),
              GoRoute(path: '/rents', builder: (_, __) => const RentScreen()),
              GoRoute(path: '/payments', builder: (_, __) => const PaymentScreen()),
            ],
          );
          return MaterialApp.router(
            title: 'PG Manager',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
              useMaterial3: true,
            ),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
