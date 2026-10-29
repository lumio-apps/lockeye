import 'package:flutter/material.dart';

import '../widgets/pin_pad.dart';

enum _FlowStage { verify, create, confirm }

/// Choose a new PIN: optionally checks the current PIN first, asks for the new
/// PIN twice and calls [onComplete] with it.
class PinFlow extends StatefulWidget {
  const PinFlow({
    super.key,
    required this.title,
    required this.onComplete,
    this.verify,
    this.forbid,
  });

  /// Heading shown while the new PIN is entered.
  final String title;
  final void Function(String pin) onComplete;

  /// When set, the current PIN is asked first and checked with this function.
  final bool Function(String pin)? verify;

  /// Returns an error message when the new PIN is not allowed, else null.
  final String? Function(String pin)? forbid;

  @override
  State<PinFlow> createState() => _PinFlowState();
}

class _PinFlowState extends State<PinFlow> {
  final _pad = GlobalKey<PinPadState>();
  late _FlowStage _stage = widget.verify != null ? _FlowStage.verify : _FlowStage.create;
  String _first = '';
  String? _error;

  String get _heading {
    switch (_stage) {
      case _FlowStage.verify:
        return 'Enter current PIN';
      case _FlowStage.create:
        return widget.title;
      case _FlowStage.confirm:
        return 'Confirm your PIN';
    }
  }

  String get _hint {
    switch (_stage) {
      case _FlowStage.verify:
        return 'To make sure it is you';
      case _FlowStage.create:
        return 'Choose a 4-digit PIN';
      case _FlowStage.confirm:
        return 'Enter the same PIN again';
    }
  }

  void _onCompleted(String pin) {
    switch (_stage) {
      case _FlowStage.verify:
        if (widget.verify!(pin)) {
          _next(_FlowStage.create);
        } else {
          _fail('Wrong PIN. Try again.');
        }
      case _FlowStage.create:
        final problem = widget.forbid?.call(pin);
        if (problem != null) {
          _fail(problem);
        } else {
          _first = pin;
          _next(_FlowStage.confirm);
        }
      case _FlowStage.confirm:
        if (pin == _first) {
          widget.onComplete(pin);
        } else {
          _first = '';
          _stage = _FlowStage.create;
          _fail('The PINs did not match. Start again.');
        }
    }
  }

  void _next(_FlowStage stage) {
    _pad.currentState?.clear();
    setState(() {
      _stage = stage;
      _error = null;
    });
  }

  void _fail(String message) {
    final pad = _pad.currentState;
    setState(() => _error = message);
    if (pad == null) return;
    pad.shake().then((_) {
      if (pad.mounted) pad.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Text(
                        _heading,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? _hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: _error != null ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PinPad(
                    key: _pad,
                    onCompleted: _onCompleted,
                    onFirstDigit: () {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full page around [PinFlow], used from Settings. Pops with true when the
/// PIN was saved.
class PinFlowPage extends StatelessWidget {
  const PinFlowPage({
    super.key,
    required this.title,
    required this.onSave,
    this.verify,
    this.forbid,
  });

  final String title;
  final Future<void> Function(String pin) onSave;
  final bool Function(String pin)? verify;
  final String? Function(String pin)? forbid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: PinFlow(
          title: title,
          verify: verify,
          forbid: forbid,
          onComplete: (pin) async {
            final navigator = Navigator.of(context);
            await onSave(pin);
            navigator.pop(true);
          },
        ),
      ),
    );
  }
}
