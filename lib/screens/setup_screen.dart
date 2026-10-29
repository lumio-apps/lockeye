import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../services/intruder_service.dart';
import '../widgets/logo.dart';
import 'pin_flow.dart';

enum _SetupStage { welcome, minePin, askFamily, familyPin }

/// First run: explains the app, creates the owner's PIN and, if wanted,
/// a separate family PIN.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  _SetupStage _stage = _SetupStage.welcome;
  String _minePin = '';
  bool _finishing = false;

  Future<void> _finish({String? familyPin}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    // Opening the camera once triggers Android's camera permission prompt.
    final camera = IntruderService();
    await camera.prepare();
    await camera.release();
    await widget.state.completeSetup(_minePin, familyPin: familyPin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _stage == _SetupStage.welcome || _stage == _SetupStage.askFamily
          ? null
          : AppBar(
              leading: BackButton(
                onPressed: () => setState(() {
                  _stage = _stage == _SetupStage.familyPin
                      ? _SetupStage.askFamily
                      : _SetupStage.welcome;
                }),
              ),
            ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    switch (_stage) {
      case _SetupStage.welcome:
        return _welcome(context);
      case _SetupStage.minePin:
        return PinFlow(
          key: const ValueKey('mine'),
          title: 'Create your PIN',
          onComplete: (pin) => setState(() {
            _minePin = pin;
            _stage = _SetupStage.askFamily;
          }),
        );
      case _SetupStage.askFamily:
        return _askFamily(context);
      case _SetupStage.familyPin:
        return PinFlow(
          key: const ValueKey('family'),
          title: 'Create the family PIN',
          forbid: (pin) => pin == _minePin ? 'Pick a PIN different from yours.' : null,
          onComplete: (pin) => _finish(familyPin: pin),
        );
    }
  }

  Widget _welcome(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 15, height: 1.35, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LockeyeLogo(size: 72),
          const SizedBox(height: 24),
          Text(
            'Welcome to Lockeye',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'A private vault that catches whoever guesses wrong.',
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          point(Icons.lock_outline, 'Your PIN opens your vault. A separate family PIN opens only the family space.'),
          point(Icons.photo_camera_outlined, 'On a wrong PIN the front camera takes a photo. Lockeye will ask for camera access next.'),
          point(Icons.phone_android, 'Everything stays on this phone. No accounts, no ads, no tracking.'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _stage = _SetupStage.minePin),
              child: const Text('Get started'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _askFamily(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.family_restroom, size: 48, color: scheme.primary),
          const SizedBox(height: 20),
          Text(
            'Add a family PIN?',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            'Family members who use this PIN see only the Family space, never your vault, '
            'the intruder photos or the settings. A wrong guess by anyone, family included, '
            'still gets a photo. You can add or change it later in Settings.',
            style: TextStyle(fontSize: 15, height: 1.4, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (_finishing)
            const Center(child: CircularProgressIndicator())
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => setState(() => _stage = _SetupStage.familyPin),
                child: const Text('Set family PIN'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _finish,
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
