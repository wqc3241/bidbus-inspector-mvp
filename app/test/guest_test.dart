// A phone not signed in to the scheduler keeps working with the app passcode (docs/12-scheduler-sync.md, Modes).
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/services/team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed out on a scheduler server: the passcode is sent; signed in: the token', () {
    final was = team.on;
    team.on = true;
    team.session = null;
    store.passcode = 'pc';
    expect(team.use, false);
    expect(store.bearer, 'pc');
    expect(store.canCall, true);
    team.session = {'access_token': 'tok', 'refresh_token': 'r', 'expires_at': 0};
    expect(team.use, true);
    expect(store.bearer, 'tok');
    team.session = null;
    store.passcode = '';
    team.on = was;
  });
}
