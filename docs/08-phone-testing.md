# 08 Testing on the phones

## One-time setup (Mac)

- Flutter stable (`flutter doctor` all green for iOS and Android).
- Xcode from the App Store, then `sudo xcodebuild -runFirstLaunch`; CocoaPods (`brew install cocoapods`).
- Android Studio with an SDK and an emulator; `flutter doctor --android-licenses`.

## iPhone

1. iPhone: Settings → Privacy & Security → Developer Mode → On (restart).
2. Plug the iPhone into the Mac, trust the computer.
3. `open app/ios/Runner.xcworkspace` → Runner target → Signing & Capabilities → Team: your Apple ID (Xcode → Settings → Accounts → add it). Bundle identifier: your own (`docs/10-flutter-app.md`).
4. `cd app && flutter run --release --dart-define=API_BASE_URL=https://{your-app}.up.railway.app`
5. First launch: iPhone Settings → General → VPN & Device Management → your Apple ID → Trust.
6. Allow camera, microphone, location and photos when asked.

A free Apple ID signs the app for 7 days; run step 4 again after that. With a paid Apple Developer account you can also ship builds to the phone through TestFlight (`flutter build ipa`, upload with Xcode Organizer or Transporter).

## Android

- USB debugging on (Settings → About phone → tap Build number 7 times → Developer options → USB debugging), plug in, `flutter run --release --dart-define=API_BASE_URL=...`.
- Or build an APK and send it to the phone: `flutter build apk --release --dart-define=API_BASE_URL=...` → `app/build/app/outputs/flutter-apk/app-release.apk`.

## In the app

Settings: server URL (prefilled), `APP_PASSCODE`, inspector name, default report email. The health check must show OK.

## Test runs

1. **Clean car**: start with YMMT only, take every shot, no damage, accept every OK, sign. Expect the email with two links within 2 minutes; Highlight all green; every row No issues.
2. **Damages**: take 3 Damage shots (one at a paint panel, one at a tire, one inside), 1 Mod shot. Check the AI first guess, relabel one, confirm all. Expect each damage in its section on both reports with its photo.
3. **Airplane mode**: turn it on after New inspection, finish the whole inspection, sign. Status Saved on phone. Force-quit the app. Turn airplane mode off, reopen. Expect Uploading then Report sent with nothing missing.
4. **EV**: fuel Electric (EV). Engine bay, engine sound and exhaust are gone; EV OBDII shots and charging items show; no Engine sound row on the dealer report.
5. **Seller check**: open the seller report and search the page for protection, guarantee, buyback: none.

Run 1 to 4 on the iPhone, then run 1 and 3 on Android.

## Automated checks

- `flutter test`: question list per fuel, `inspectionPayload` port against `samples/inspection-*.json` shape, damage labelling ticks the right checks, Summary gates.
- `integration_test` on the iOS simulator and Android emulator for the screens without the camera (the camera needs a real device; inject a fake camera service in tests).
- Server: `pytest` (`docs/06-backend.md`).
