import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../services/vault_service.dart';
import '../widgets/logo.dart';
import 'files_screen.dart';
import 'notes_screen.dart';
import 'photos_screen.dart';

/// Home of the vault: Photos, Files and Notes for one space.
/// The owner can switch between Mine and Family; family members see only Family.
class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.state,
    required this.isOwner,
    this.onOpenIntruders,
  });

  final AppState state;
  final bool isOwner;
  final VoidCallback? onOpenIntruders;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late VaultSpace _view = widget.isOwner ? VaultSpace.mine : VaultSpace.family;
  int _photos = 0;
  int _files = 0;
  int _notes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await VaultService.count(_view, VaultKind.photos);
    final files = await VaultService.count(_view, VaultKind.files);
    final notes = (await VaultService.notes(_view)).length;
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _files = files;
      _notes = notes;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  Future<void> _import(VaultKind kind) async {
    final added = await VaultService.pickAndImport(widget.state, _view, kind);
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $added item${added == 1 ? '' : 's'}')),
      );
    }
    await _load();
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Add photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _import(VaultKind.photos);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Add files'),
              onTap: () {
                Navigator.pop(sheetContext);
                _import(VaultKind.files);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('New note'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(NoteEditorScreen(space: _view));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, child) {
          final canSwitch = widget.isOwner && widget.state.familyEnabled;
          final unseen = widget.isOwner ? widget.state.unseenList : const <IntruderEntry>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _view == VaultSpace.mine ? 'My Vault' : 'Family Vault',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lock now',
                    icon: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
                    onPressed: widget.state.lock,
                  ),
                  const SizedBox(width: 4),
                  const LockeyeLogo(size: 40),
                ],
              ),
              if (canSwitch) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<VaultSpace>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: VaultSpace.mine, label: Text('Mine')),
                      ButtonSegment(value: VaultSpace.family, label: Text('Family')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) {
                      setState(() => _view = selection.first);
                      _load();
                    },
                  ),
                ),
              ],
              if (unseen.isNotEmpty) ...[
                const SizedBox(height: 20),
                _AlertCard(entries: unseen, onView: widget.onOpenIntruders),
              ],
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.3,
                children: [
                  _Tile(
                    icon: Icons.photo_outlined,
                    title: 'Photos',
                    subtitle: '$_photos item${_photos == 1 ? '' : 's'}',
                    onTap: () => _open(PhotosScreen(state: widget.state, space: _view)),
                  ),
                  _Tile(
                    icon: Icons.insert_drive_file_outlined,
                    title: 'Files',
                    subtitle: '$_files item${_files == 1 ? '' : 's'}',
                    onTap: () => _open(FilesScreen(state: widget.state, space: _view)),
                  ),
                  _Tile(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'Notes',
                    subtitle: '$_notes item${_notes == 1 ? '' : 's'}',
                    onTap: () => _open(NotesScreen(space: _view)),
                  ),
                  _Tile(
                    icon: Icons.add,
                    title: 'Add to vault',
                    subtitle: 'Photos, files, notes',
                    onTap: _showAddSheet,
                    outlined: true,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.entries, required this.onView});

  final List<IntruderEntry> entries;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = entries.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kAlert,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: kInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$n wrong attempt${n == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    Text(
                      'Last one: ${formatWhen(entries.first.time)}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
              onPressed: onView,
              child: const Text('View photos'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: outlined ? Colors.transparent : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outlined ? scheme.outline : scheme.outlineVariant),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 30, color: outlined ? scheme.onSurfaceVariant : scheme.primary),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
