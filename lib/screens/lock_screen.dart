import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../services/intruder_service.dart';
import '../widgets/logo.dart';
import '../widgets/pin_pad.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final _pad = GlobalKey<PinPadState>();
  final _camera = IntruderService();
  Future<void>? _pendingPhoto;
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  String? _error;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remaining = _state.lockRemaining;
    if (_remaining > Duration.zero) _startTicker();
    if (_state.photoOnWrong) _camera.prepare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    // Let a photo that is still being saved finish before the camera closes.
    final pending = _pendingPhoto ?? Future<void>.value();
    pending.whenComplete(_camera.release);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused) {
      _camera.release();
    } else if (lifecycle == AppLifecycleState.resumed && _state.photoOnWrong) {
      _camera.prepare();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = _state.lockRemaining;
      if (!mounted) return;
      setState(() => _remaining = left);
      if (left <= Duration.zero) {
        timer.cancel();
        setState(() => _error = null);
      }
    });
  }

  void _onCompleted(String pin) {
    final result = _state.unlock(pin);
    switch (result) {
      case UnlockResult.mine:
      case UnlockResult.family:
        _pad.currentState?.clear();
      case UnlockResult.lockedOut:
        _pad.currentState?.clear();
        setState(() => _remaining = _state.lockRemaining);
        _startTicker();
      case UnlockResult.wrong:
        _onWrong();
    }
  }

  void _onWrong() {
    final attempt = _state.failCount;
    final when = DateTime.now();
    final pad = _pad.currentState;

    setState(() {
      _error = 'Wrong PIN. Try again.';
      _remaining = _state.lockRemaining;
    });
    if (_remaining > Duration.zero) _startTicker();

    final shaking = pad?.shake();
    shaking?.then((_) {
      if (pad != null && pad.mounted) pad.clear();
    });

    _pendingPhoto = _logAttempt(attempt, when);
  }

  Future<void> _logAttempt(int attempt, DateTime when) async {
    String? path;
    if (_state.photoOnWrong) {
      path = await _camera.capture('${when.microsecondsSinceEpoch}');
    }
    await _state.addIntruder(path: path, attempt: attempt, time: when);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = _remaining > Duration.zero;

    final String message;
    final Color messageColor;
    if (locked) {
      message = 'Too many wrong tries. Wait ${_remaining.inSeconds + 1} s.';
      messageColor = scheme.error;
    } else if (_error != null) {
      message = _error!;
      messageColor = scheme.error;
    } else {
      message = 'Enter your PIN to open Lockeye';
      messageColor = scheme.onSurfaceVariant;
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const LockeyeLogo(size: 64),
                          const SizedBox(height: 14),
                          Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: messageColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      PinPad(
                        key: _pad,
                        enabled: !locked,
                        onFirstDigit: () {
                          if (_error != null) setState(() => _error = null);
                        },
                        onCompleted: _onCompleted,
                      ),
                      const SizedBox(height: 24),
                      if (_state.photoOnWrong)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_outlined, size: 18, color: scheme.primary),
                              const SizedBox(width: 10),
                              Text(
                                'Wrong PIN? Lockeye takes a photo.',
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
