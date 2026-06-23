import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_exception.dart';

class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isNetwork = isNetworkError(error);
    final isServer = error is ServerException;

    final icon = isNetwork
        ? Icons.wifi_off_rounded
        : isServer
            ? Icons.cloud_off_rounded
            : Icons.error_outline_rounded;

    final title = isNetwork
        ? 'No Internet Connection'
        : isServer
            ? 'Server Unavailable'
            : 'Something went wrong';

    final subtitle = isNetwork
        ? 'Check your connection and try again.'
        : isServer
            ? 'The server is temporarily down.\nPlease try again in a moment.'
            : error.toString().replaceFirst('Exception: ', '');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[350]),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                  color: Colors.grey[500], fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: PgColors.primary,
                minimumSize: const Size(140, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
