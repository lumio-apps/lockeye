import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'intruders_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';

/// What you see after unlocking. The owner gets Vault, Intruders and Settings;
/// family members get only the Family vault.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, required this.space});

  final AppState state;
  final VaultSpace space;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.space == VaultSpace.family) {
      return Scaffold(body: VaultScreen(state: widget.state, isOwner: false));
    }

    final Widget page;
    switch (_tab) {
      case 1:
        page = IntrudersScreen(key: const ValueKey('intruders'), state: widget.state);
      case 2:
        page = SettingsScreen(key: const ValueKey('settings'), state: widget.state);
      default:
        page = VaultScreen(
          key: const ValueKey('vault'),
          state: widget.state,
          isOwner: true,
          onOpenIntruders: () => setState(() => _tab = 1),
        );
    }

    return Scaffold(
      body: page,
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.state,
        builder: (context, child) {
          final unseen = widget.state.unseenIntruders;
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.lock_outline),
                selectedIcon: Icon(Icons.lock),
                label: 'Vault',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unseen > 0 && _tab != 1,
                  label: Text('$unseen'),
                  child: const Icon(Icons.visibility_outlined),
                ),
                selectedIcon: const Icon(Icons.visibility),
                label: 'Intruders',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune),
                selectedIcon: Icon(Icons.tune),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
