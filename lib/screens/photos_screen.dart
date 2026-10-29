import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../services/vault_service.dart';
import 'photo_viewer_screen.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key, required this.state, required this.space});

  final AppState state;
  final VaultSpace space;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<VaultItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await VaultService.list(widget.space, VaultKind.photos);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add() async {
    final added = await VaultService.pickAndImport(widget.state, widget.space, VaultKind.photos);
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $added photo${added == 1 ? '' : 's'}')),
      );
    }
    await _load();
  }

  Future<void> _open(List<VaultItem> items, int index) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          paths: items.map((e) => e.path).toList(),
          initial: index,
          onDelete: VaultService.delete,
        ),
      ),
    );
    await _load();
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
              Icon(Icons.photo_outlined, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'No photos yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Photos you add are copied into the vault. Delete the originals from your gallery yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => _open(items, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(items[i].path),
              fit: BoxFit.cover,
              cacheWidth: 360,
              errorBuilder: (context, error, stack) => Container(
                color: scheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add photos'),
      ),
    );
  }
}
