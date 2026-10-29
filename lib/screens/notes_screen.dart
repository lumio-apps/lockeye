import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../services/vault_service.dart';
import '../widgets/common.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.space});

  final VaultSpace space;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<VaultNote>? _notes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await VaultService.notes(widget.space);
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _edit(VaultNote? note) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(space: widget.space, note: note)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (notes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (notes.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'No notes yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: notes.length,
        separatorBuilder: (context, i) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final note = notes[i];
          final title = note.title.isEmpty ? 'Untitled' : note.title;
          return SurfaceCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                note.body.isEmpty ? formatWhen(note.updated) : '${note.body}\n${formatWhen(note.updated)}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: note.body.isNotEmpty,
              onTap: () => _edit(note),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.edit_note),
        label: const Text('New note'),
      ),
    );
  }
}

/// Write or edit one note. It is saved when you go back; an empty note is dropped.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.space, this.note});

  final VaultSpace space;
  final VaultNote? note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title = TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body = TextEditingController(text: widget.note?.body ?? '');
  late final String _id = widget.note?.id ?? '${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      await VaultService.deleteNote(widget.space, _id);
      return;
    }
    final unchanged = widget.note != null && widget.note!.title == title && widget.note!.body == body;
    if (unchanged) return;
    await VaultService.saveNote(
      widget.space,
      VaultNote(
        id: _id,
        title: title,
        body: body,
        updatedMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete note?',
      message: 'This note will be removed from the vault.',
    );
    if (!ok) return;
    await VaultService.deleteNote(widget.space, _id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _save();
        navigator.pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (widget.note != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
                ),
                Expanded(
                  child: TextField(
                    controller: _body,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 16, height: 1.4, color: scheme.onSurface),
                    decoration: const InputDecoration(hintText: 'Write something...', border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
