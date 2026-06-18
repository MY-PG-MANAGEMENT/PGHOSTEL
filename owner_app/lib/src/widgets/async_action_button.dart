import 'package:flutter/material.dart';

class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton({required this.label, required this.onPressed, super.key});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading
          ? null
          : () async {
              setState(() => loading = true);
              try {
                await widget.onPressed();
              } finally {
                if (mounted) setState(() => loading = false);
              }
            },
      child: loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.label),
    );
  }
}
