import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'camera/camera_screen.dart';
import 'data/ql.dart';
import 'data/vehicles.dart';
import 'screens/brief.dart';
import 'screens/home.dart';
import 'screens/inspection.dart';
import 'screens/new_inspection.dart';
import 'screens/settings.dart';
import 'screens/signin.dart';
import 'services/store.dart';
import 'services/team.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await loadQl();
  await loadVehicles();
  store.settle = settleLater;
  await store.init();
  await team.init();
  void sync() => signedOut.value = team.on && !team.signedIn;
  sync();
  team.addListener(sync);
  runApp(const ProviderScope(child: App()));
}

// with scheduler sign-in, signed out: Sign in (and Settings, for the server URL) only. The router is told only when
// that flips (each refresh of the routes would drop the camera's arguments)
final signedOut = ValueNotifier(false);
final router = GoRouter(
  refreshListenable: signedOut,
  redirect: (c, s) {
    final out = team.on && !team.signedIn, at = s.matchedLocation;
    if (out && at != '/signin' && at != '/settings') return '/signin';
    if (!out && at == '/signin') return '/';
    final st = store.ins[s.pathParameters['id']];
    if (st != null && !team.mine(st)) return '/'; // another inspector's
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
    GoRoute(path: '/signin', builder: (c, s) => const SignInScreen()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
    GoRoute(path: '/new', builder: (c, s) => NewInspectionScreen(prefill: s.extra as Map<String, dynamic>?)),
    GoRoute(path: '/a/:slot', builder: (c, s) => BriefScreen(s.pathParameters['slot']!)),
    GoRoute(path: '/i/:id', builder: (c, s) => InspectionScreen(s.pathParameters['id']!)),
    GoRoute(path: '/i/:id/cam', builder: (c, s) => CameraScreen(s.pathParameters['id']!, args: s.extra as CamArgs? ?? const CamArgs())),
  ],
);

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
