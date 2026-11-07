import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../services/vault_service.dart';
import 'common.dart';

/// Picks items, encrypts them into the vault and, for gallery photos, offers to
/// delete the originals from the gallery. Returns how many items were added.
Future<int> importIntoVault(
  BuildContext context,
  AppState state,
  VaultSpace space,
  VaultKind kind,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await VaultService.pickAndImport(state, space, kind);
  if (result.added == 0) return 0;

  final noun = kind == VaultKind.photos ? 'photo' : 'file';
  messenger.showSnackBar(
    SnackBar(content: Text('Added ${result.added} $noun${result.added == 1 ? '' : 's'}')),
  );

  if (kind == VaultKind.photos && result.deletable > 0 && context.mounted) {
    final delete = await confirmDialog(
      context,
      title: 'Delete the originals?',
      message: 'The copies in your gallery are not encrypted and stay visible to every app '
          'that can read photos. Android will ask you once more before it deletes '
          '${result.deletable == 1 ? 'the photo' : '${result.deletable} photos'}.',
      confirmLabel: 'Delete originals',
    );
    if (delete) {
      final done = await VaultService.deleteOriginals(state);
      if (!done) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('The originals were not deleted. You can remove them from your gallery.'),
          ),
        );
      }
    }
  } else if (kind == VaultKind.photos) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Delete the originals from your gallery so they are not left unprotected.')),
    );
  }
  return result.added;
}
