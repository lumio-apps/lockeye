import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'screens/setup_screen.dart';

class LockeyeApp extends StatefulWidget {
  const LockeyeApp({super.key, required this.state});

  final AppState state;

  @override
  State<LockeyeApp> createState() => _LockeyeAppState();
}

class _LockeyeAppState extends State<LockeyeApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_closeScreensWhenLocked);
  }

  @override
  void dispose() {
    widget.state.removeListener(_closeScreensWhenLocked);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Locking must also close photo viewers, notes and dialogs that were opened
  /// on top of the home screen, so nothing stays visible behind the lock.
  void _closeScreensWhenLocked() {
    if (widget.state.space == null) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused) widget.state.onAppPaused();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, child) => MaterialApp(
        title: 'Lockeye',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        themeMode: widget.state.themeMode,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: _root(),
      ),
    );
  }

  Widget _root() {
    final state = widget.state;
    if (!state.isSetUp) return SetupScreen(state: state);
    final space = state.space;
    if (space == null) return LockScreen(state: state);
    return HomeShell(key: ValueKey(space), state: state, space: space);
  }
}
