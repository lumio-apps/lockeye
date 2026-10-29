import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_state.dart';
import '../services/update_service.dart';
import '../widgets/common.dart';
import 'pin_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  Future<void> _changeMinePin(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PinFlowPage(
          title: 'Choose a new PIN',
          verify: state.matchesMine,
          forbid: (pin) => state.matchesFamily(pin) ? 'This PIN is used for the Family space.' : null,
          onSave: state.setMinePin,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN changed')));
    }
  }

  Future<void> _setFamilyPin(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PinFlowPage(
          title: 'Choose the family PIN',
          forbid: (pin) => state.matchesMine(pin) ? 'Pick a PIN different from yours.' : null,
          onSave: state.setFamilyPin,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family PIN saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListenableBuilder(
        listenable: state,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Text(
              'Settings',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: scheme.onSurface),
            ),
            const SectionLabel('Spaces'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingRow(
                    title: 'My PIN',
                    subtitle: 'Opens everything, including intruder photos',
                    trailing: OutlinedButton(
                      onPressed: () => _changeMinePin(context),
                      child: const Text('Change'),
                    ),
                  ),
                  const Divider(),
                  _SettingRow(
                    title: 'Family PIN',
                    subtitle: state.hasFamilyPin
                        ? 'Opens only the Family space'
                        : 'Not set. Add one so family can use the Family space.',
                    trailing: OutlinedButton(
                      onPressed: () => _setFamilyPin(context),
                      child: Text(state.hasFamilyPin ? 'Change' : 'Set'),
                    ),
                  ),
                  const Divider(),
                  _SettingRow(
                    title: 'Family space',
                    subtitle: 'Turn off to disable the Family PIN',
                    trailing: Switch(
                      value: state.familyEnabled,
                      onChanged: state.hasFamilyPin ? state.setFamilyEnabled : null,
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Intruder photos'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: _SettingRow(
                title: 'Photo on wrong PIN',
                subtitle: 'Same rule for every space. Photos never leave this phone.',
                trailing: Switch(
                  value: state.photoOnWrong,
                  onChanged: state.setPhotoOnWrong,
                ),
              ),
            ),
            const SectionLabel('App'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: ThemeMode.system, label: Text('System')),
                              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                            ],
                            selected: {state.themeMode},
                            onSelectionChanged: (selection) => state.setThemeMode(selection.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (kSelfUpdate) ...[
                    const Divider(),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) => _SettingRow(
                        title: 'Updates',
                        subtitle: 'Version ${snapshot.data?.version ?? ''}',
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                          onPressed: () => UpdateService.checkForUpdates(context),
                          child: const Text('Check'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Open source · Offline · No ads · No data collected',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.subtitle, required this.trailing});

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
