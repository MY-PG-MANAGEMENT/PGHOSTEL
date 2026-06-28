import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Standard centered loading indicator with an optional label.
///
/// Use this instead of bare `Center(child: CircularProgressIndicator())` so
/// loading states look consistent across every screen.
class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: PgColors.primary),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(
              label!,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
