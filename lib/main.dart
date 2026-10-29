import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = await AppState.load();
  runApp(LockeyeApp(state: state));
}
