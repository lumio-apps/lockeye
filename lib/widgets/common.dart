import 'package:flutter/material.dart';

/// A rounded card in the surface color, with a thin border (visible in light mode).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Asks "are you sure?". Returns true only when the person confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
