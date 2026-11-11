// The Sign in button stays above the keyboard (the code keyboard has no key to close it).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bidbus_field/screens/signin.dart';

void main() {
  testWidgets('the button sits above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    final r = tester.getRect(find.text('Send code'));
    expect(r.bottom, lessThanOrEqualTo(844 - 300));
  });
}
