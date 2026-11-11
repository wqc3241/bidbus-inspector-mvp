// Sign in with the scheduler account (docs/12-scheduler-sync.md): the email on the team list, then the emailed code.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/api.dart';
import '../services/team.dart';
import '../widgets/ui.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController(), code = TextEditingController();
  bool sent = false, busy = false;
  String? error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (e) {
      error = apiError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _send() => _run(() async {
    await team.sendCode(email.text);
    sent = true;
  });

  Future<void> _verify() => _run(() => team.verify(email.text, code.text));

  Widget _f(
    String l,
    TextEditingController c, {
    TextInputType? kb,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          keyboardType: kb,
          enabled: enabled,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final okEmail = RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim()),
        okCode = RegExp(r'^\d{6,10}$').hasMatch(code.text.trim());
    return Scaffold(
      appBar: TitleBar(
        'Sign in',
        back: false,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _f('Email', email, kb: TextInputType.emailAddress, enabled: !sent),
          if (sent) ...[
            _f('Code', code, kb: TextInputType.number),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        sent = false;
                        code.clear();
                        error = null;
                      }),
                child: const Text('Change email'),
              ),
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: const TextStyle(color: red, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      // above the keyboard (the code keyboard has no key to close it)
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: BottomBar(
          sent
              ? PBtn('Sign in', busy || !okCode ? null : _verify)
              : PBtn('Send code', busy || !okEmail ? null : _send),
        ),
      ),
    );
  }
}
