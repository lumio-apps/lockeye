import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../services/phone_lock_service.dart';
import '../widgets/common.dart';

/// Guided setup for "photo when the phone's own lock screen gets a wrong
/// PIN, pattern or password".
class PhoneLockScreen extends StatefulWidget {
  const PhoneLockScreen({super.key, required this.state});

  final AppState state;

  @override
  State<PhoneLockScreen> createState() => _PhoneLockScreenState();
}

class _PhoneLockScreenState extends State<PhoneLockScreen> with WidgetsBindingObserver {
  PhoneLockStatus _status = const PhoneLockStatus();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await PhoneLockService.status();
    if (!mounted) return;
    setState(() => _status = status);
    // Admin was removed in Android settings: the feature cannot work any more.
    if (!status.ready && widget.state.phoneLockEnabled) {
      await widget.state.setPhoneLockEnabled(false);
    }
  }

  Future<void> _open(Future<void> Function() request) async {
    widget.state.holdLockUntilResume();
    await request();
    // The status refreshes when the person comes back to the app.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) await _refresh();
  }

  Future<void> _turnOffAndRemove() async {
    final ok = await confirmDialog(
      context,
      title: 'Turn off?',
      message: 'Lockeye will stop watching the phone lock screen and give up its device admin access. '
          'You can set it up again later.',
      confirmLabel: 'Turn off',
    );
    if (!ok) return;
    await widget.state.setPhoneLockEnabled(false);
    await PhoneLockService.removeAdmin();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) await _refresh();
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    await PhoneLockService.configure(enabled: widget.state.phoneLockEnabled);
    final started = await PhoneLockService.testCapture();
    var added = 0;
    if (started) {
      for (var i = 0; i < 14 && added == 0; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        added = await widget.state.importPhoneShots();
      }
    }
    if (!mounted) return;
    setState(() => _testing = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? 'Test photo saved. See the Intruders tab.'
              : 'No photo. Check the camera permission, or see "Good to know" below.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, child) {
        final enabled = widget.state.phoneLockEnabled;
        return Scaffold(
        appBar: AppBar(title: const Text('Phone lock screen')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(
                'When someone types a wrong PIN, pattern or password on your phone\'s own lock screen, '
                'Lockeye takes a front camera photo and adds it to the Intruder log.',
                style: TextStyle(fontSize: 15, height: 1.4, color: scheme.onSurfaceVariant),
              ),
              const SectionLabel('Set up (one time)'),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _StepRow(
                      done: _status.admin,
                      title: '1. Device admin',
                      subtitle: 'Lets Lockeye hear that an unlock attempt failed. '
                          'It cannot read or change your PIN, and cannot lock or wipe the phone.',
                      button: 'Allow',
                      onPressed: () => _open(PhoneLockService.requestAdmin),
                    ),
                    const Divider(height: 1),
                    _StepRow(
                      done: _status.overlay,
                      title: '2. Show over other apps',
                      subtitle: 'Android only allows the camera to run on the lock screen '
                          'while the app shows something. Lockeye shows a 1 pixel invisible dot.',
                      button: 'Open',
                      onPressed: () => _open(PhoneLockService.requestOverlay),
                    ),
                    const Divider(height: 1),
                    _StepRow(
                      done: _status.camera && _status.notifications,
                      title: '3. Camera and notifications',
                      subtitle: 'Camera takes the photo. The notification is the small '
                          '"checking" notice Android requires while the camera works.',
                      button: 'Allow',
                      onPressed: () => _open(PhoneLockService.requestPermissions),
                    ),
                    const Divider(height: 1),
                    _StepRow(
                      done: null,
                      title: '4. Keep Lockeye awake (recommended)',
                      subtitle: 'Set Lockeye to "Unrestricted" or "No restrictions". On Xiaomi, Oppo, '
                          'Vivo and Realme also allow Autostart in the app info page.',
                      button: 'Open',
                      onPressed: () => _open(PhoneLockService.openBatterySettings),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Turn on'),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Photo on phone lock screen',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _status.ready
                                      ? 'Photos stay on this phone'
                                      : 'Finish steps 1 to 3 first',
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: enabled && _status.ready,
                            onChanged: _status.ready ? widget.state.setPhoneLockEnabled : null,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _status.ready && !_testing ? _test : null,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_outlined),
                          label: Text(_testing ? 'Taking photo...' : 'Take a test photo'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Good to know'),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in const [
                      'The real test: lock the phone, type a wrong PIN once, unlock, then open Lockeye.',
                      'Only wrong PIN, pattern or password counts. Wrong fingerprint or face is not reported by Android.',
                      'Some phones (mostly Xiaomi, Oppo, Vivo, Realme) block camera use on the lock screen, even with every step done. '
                          'Then the attempt is still logged, but without a photo.',
                      'To uninstall Lockeye, turn this off first. Android does not allow removing an app that is a device admin.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7, right: 10),
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_status.admin) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                    onPressed: _turnOffAndRemove,
                    child: const Text('Turn off and remove device admin'),
                  ),
                ),
              ],
            ],
          ),
        ),
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.done,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onPressed,
  });

  /// true = finished, false = still to do, null = optional (no check mark).
  final bool? done;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (done == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.check_circle, size: 18, color: scheme.primary),
                      ),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (done == true)
            const SizedBox(width: 64)
          else
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: onPressed,
              child: Text(button),
            ),
        ],
      ),
    );
  }
}
