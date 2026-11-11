// Server URL, app passcode, inspector name, default report email; shows the health check.
// With scheduler sign-in (docs/12-scheduler-sync.md): who is signed in and Sign out, in place of the passcode and name.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../services/store.dart';
import '../services/team.dart';
import '../widgets/ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final url = TextEditingController(text: store.server), pass = TextEditingController(text: store.passcode);
  final name = TextEditingController(text: store.inspector), email = TextEditingController(text: store.defaultEmail);
  String? health;
  bool? ok;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => health = 'Checking');
    await team.checked; // a new server URL has said which sign-in it uses
    try {
      final teamOn = team.on && url.text.trim() == store.server;
      final tok = teamOn ? await team.token() : null;
      var r = await Api(url.text.trim(), teamOn ? tok ?? '' : pass.text.trim()).health();
      // refused: the phone's clock may be off, so the token is renewed once and asked again
      if (teamOn && tok != null && r['auth'] == 'team' && r['ok'] == true && r['signed_in'] != true) {
        final t = await team.token(now: true);
        if (t != null && t != tok) r = await Api(url.text.trim(), t).health();
      }
      if (!mounted) return;
      setState(() {
        if (r['auth'] == 'team') {
          ok = r['ok'] == true && r['signed_in'] == true;
          health = r['ok'] != true
              ? 'Server error'
              : ok!
              ? 'OK'
              : 'Signed out';
          return;
        }
        ok = r['ok'] == true && r['passcode_ok'] == true;
        health = r['ok'] != true ? 'Server error' : r['passcode_ok'] == true ? 'OK' : 'Wrong passcode';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        ok = false;
        health = 'Server not reached';
      });
    }
  }

  Future<void> _save() async {
    await store.saveSettings(server: url.text, passcode: pass.text, inspector: name.text, email: email.text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)));
    await _check();
  }

  Widget _f(String l, TextEditingController c, {bool obscure = false, TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: c, obscureText: obscure, keyboardType: kb, autocorrect: false),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider);
    return Scaffold(
        appBar: const TitleBar('Settings'),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _f('Server URL', url, kb: TextInputType.url),
          if (!team.on) ...[
            _f('App passcode', pass, obscure: true),
            _f('Inspector name', name),
          ],
          _f('Default report email', email, kb: TextInputType.emailAddress),
          if (team.on && team.signedIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(team.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if ((team.member?['email'] ?? '') != team.name) Text('${team.member?['email'] ?? ''}', style: const TextStyle(color: muted)),
                  ]),
                ),
                TextButton(
                  onPressed: () async {
                    await team.signOut();
                    if (context.mounted) context.go('/signin');
                  },
                  child: const Text('Sign out', style: TextStyle(color: red, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          Row(children: [
            Icon(ok == true ? Icons.check_circle : Icons.error_outline, color: ok == true ? bid : ok == false ? red : muted, size: 20),
            const SizedBox(width: 8),
            Text('Server: ${health ?? ''}', style: TextStyle(fontWeight: FontWeight.w600, color: ok == true ? bid : ok == false ? red : muted)),
          ]),
        ]),
        bottomNavigationBar: BottomBar(PBtn('Save', _save)),
      );
  }
}
