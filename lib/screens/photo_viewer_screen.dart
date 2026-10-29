import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Full screen photos you can swipe through and pinch to zoom.
/// Pass [onDelete] to show a delete button.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.paths,
    this.initial = 0,
    this.onDelete,
  });

  final List<String> paths;
  final int initial;
  final Future<void> Function(String path)? onDelete;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete photo?',
      message: 'This photo will be removed from the vault.',
    );
    if (!ok || !mounted) return;
    await onDelete(widget.paths[_index]);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${widget.paths.length}'),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.paths.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(widget.paths[i]),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
