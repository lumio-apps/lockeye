import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'photo_viewer_screen.dart';

/// Every wrong PIN attempt, newest first, with the photo that was taken.
class IntrudersScreen extends StatefulWidget {
  const IntrudersScreen({super.key, required this.state});

  final AppState state;

  @override
  State<IntrudersScreen> createState() => _IntrudersScreenState();
}

class _IntrudersScreenState extends State<IntrudersScreen> {
  late final Set<String> _newIds;

  @override
  void initState() {
    super.initState();
    _newIds = widget.state.unseenList.map((e) => e.id).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.markIntrudersSeen();
    });
  }

  Future<void> _clearAll() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete all?',
      message: 'All intruder photos and the log will be removed.',
      confirmLabel: 'Delete all',
    );
    if (ok) await widget.state.clearIntruders();
  }

  Future<void> _delete(IntruderEntry entry) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this photo?',
      message: 'This attempt will be removed from the log.',
    );
    if (ok) await widget.state.removeIntruder(entry.id);
  }

  void _open(IntruderEntry entry) {
    final path = entry.path;
    if (path == null) return;
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PhotoViewerScreen(paths: [path])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, child) {
          final entries = widget.state.intruders;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Intruder log',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ),
                  if (entries.isNotEmpty)
                    IconButton(
                      tooltip: 'Delete all',
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _clearAll,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${entries.length} wrong attempt${entries.length == 1 ? '' : 's'} · photos stay on this phone',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 56, color: scheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'No wrong attempts',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'When someone types a wrong PIN, their photo appears here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EntryCard(
                      entry: entry,
                      isNew: _newIds.contains(entry.id),
                      onOpen: () => _open(entry),
                      onDelete: () => _delete(entry),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.isNew,
    required this.onOpen,
    required this.onDelete,
  });

  final IntruderEntry entry;
  final bool isNew;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = entry.path;

    final placeholder = Container(
      width: 76,
      height: 76,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.bottomCenter,
      child: Icon(Icons.person, size: 60, color: scheme.outline),
    );

    final Widget thumb = path == null
        ? placeholder
        : Image.file(
            File(path),
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            cacheWidth: 228,
            errorBuilder: (context, error, stack) => placeholder,
          );

    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      borderColor: isNew ? scheme.error.withValues(alpha: 0.5) : null,
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpen,
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: thumb),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isNew)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                      ),
                    Flexible(
                      child: Text(
                        formatWhen(entry.time),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Wrong PIN · Attempt ${entry.attempt}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                if (path == null)
                  Text(
                    'No photo (camera off or not allowed)',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
