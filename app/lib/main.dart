import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'camera/camera_screen.dart';
import 'data/ql.dart';
import 'screens/home.dart';
import 'screens/inspection.dart';
import 'screens/new_inspection.dart';
import 'screens/settings.dart';
import 'services/store.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await loadQl();
  await store.init();
  runApp(const ProviderScope(child: App()));
}

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
  GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
  GoRoute(path: '/new', builder: (c, s) => const NewInspectionScreen()),
  GoRoute(path: '/i/:id', builder: (c, s) => InspectionScreen(s.pathParameters['id']!)),
  GoRoute(path: '/i/:id/cam', builder: (c, s) => CameraScreen(s.pathParameters['id']!, args: s.extra as CamArgs? ?? const CamArgs())),
]);

class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(storeProvider.select((s) => s.online));
    return MaterialApp.router(
      title: 'Bidbus Field',
      debugShowCheckedModeBanner: false,
      theme: theme(),
      routerConfig: router,
      builder: (c, child) => Column(children: [if (!online) const NoSignal(), Expanded(child: child!)]),
    );
  }
}
