import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../services/vault_service.dart';
import '../widgets/common.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.state, required this.space});

  final AppState state;
  final VaultSpace space;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<VaultItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await VaultService.list(widget.space, VaultKind.files);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add() async {
    final added = await VaultService.pickAndImport(widget.state, widget.space, VaultKind.files);
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $added file${added == 1 ? '' : 's'}')),
      );
    }
    await _load();
  }

  Future<void> _delete(VaultItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete file?',
      message: '"${item.name}" will be removed from the vault.',
    );
    if (!ok) return;
    await VaultService.delete(item.path);
    await _load();
  }

  Future<void> _open(VaultItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await OpenFilex.open(item.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(content: Text('No app could open this file: ${result.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'No files yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Files you add are copied into the vault. Delete the originals yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: items.length,
        separatorBuilder: (context, i) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return SurfaceCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              leading: Icon(Icons.insert_drive_file_outlined, color: scheme.primary),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatSize(item.size)} · ${formatWhen(item.modified)}'),
              onTap: () => _open(item),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(item),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.upload_file),
        label: const Text('Add files'),
      ),
    );
  }
}
