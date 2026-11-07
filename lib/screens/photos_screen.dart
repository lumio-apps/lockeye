// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../services/vault_service.dart';
import '../widgets/import_flow.dart';
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
    await importIntoVault(context, widget.state, widget.space, VaultKind.photos);
    if (!mounted) return;
    await _load();
  }

  Future<void> _open(List<VaultItem> items, int index) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          paths: items.map((e) => e.path).toList(),
          initial: index,
          loader: (path) => VaultService.photoBytes(widget.space, path),
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
                'Photos you add are encrypted into the vault. Lockeye can also delete the originals from your gallery.',
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
            child: _Thumb(
              key: ValueKey(items[i].path),
              space: widget.space,
              path: items[i].path,
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

/// One decrypted photo in the grid.
class _Thumb extends StatefulWidget {
  const _Thumb({super.key, required this.space, required this.path});

  final VaultSpace space;
  final String path;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<Uint8List?> _future = VaultService.photoBytes(widget.space, widget.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, color: scheme.outline),
    );
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => box,
          );
        }
        if (snapshot.connectionState == ConnectionState.done) return box;
        return Container(color: scheme.surfaceContainerHighest);
      },
    );
  }
}
