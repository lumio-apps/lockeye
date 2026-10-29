import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart' show kPinLength;

/// Four dots and a numeric keypad. Calls [onCompleted] when all digits are in;
/// the parent then calls [PinPadState.clear] (or [PinPadState.shake]).
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.onFirstDigit,
    this.enabled = true,
  });

  final void Function(String pin) onCompleted;
  final VoidCallback? onFirstDigit;
  final bool enabled;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void clear() {
    if (mounted) setState(() => _pin = '');
  }

  /// Wiggles the dots and vibrates. Completes when the wiggle is done.
  Future<void> shake() async {
    HapticFeedback.heavyImpact();
    await _shake.forward(from: 0);
  }

  void _tap(String digit) {
    if (!widget.enabled || _pin.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == 1) widget.onFirstDigit?.call();
    if (_pin.length == kPinLength) widget.onCompleted(_pin);
  }

  void _back() {
    if (!widget.enabled || _pin.isEmpty || _pin.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget digit(String d) => _Key(
          onTap: () => _tap(d),
          child: Text(
            d,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: scheme.onSurface),
          ),
        );

    Widget row(List<Widget> keys) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: keys),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final dx = math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Semantics(
            label: '${_pin.length} of $kPinLength digits entered',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < kPinLength; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: _Dot(filled: i < _pin.length),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: 300,
          child: Column(
            children: [
              row([digit('1'), digit('2'), digit('3')]),
              row([digit('4'), digit('5'), digit('6')]),
              row([digit('7'), digit('8'), digit('9')]),
              row([
                const SizedBox(width: 72, height: 72),
                digit('0'),
                _Key(
                  filled: false,
                  label: 'Delete last digit',
                  onTap: _back,
                  child: Icon(Icons.backspace_outlined, size: 26, color: scheme.onSurfaceVariant),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : Colors.transparent,
        border: filled ? null : Border.all(color: scheme.outline, width: 2),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.child, required this.onTap, this.filled = true, this.label});

  final Widget child;
  final VoidCallback onTap;
  final bool filled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: filled ? scheme.surface : Colors.transparent,
        shape: CircleBorder(
          side: filled ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
    if (label == null) return key;
    return Semantics(label: label, button: true, excludeSemantics: true, onTap: onTap, child: key);
  }
}
