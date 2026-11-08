# 10 Flutter app

Native mobile app for iOS and Android from one Flutter code base in `app/`. iPhone first; every feature must also work on Android.

## Packages

| Need | Package |
|---|---|
| Camera preview, photos, video with sound, zoom, lens list | `camera` |
| Pick from the photo library | `image_picker` |
| Turn photos upright, resize, JPEG | `image` (`bakeOrientation`), or `flutter_image_compress` for speed |
| 36 frames from the walk-around | `video_thumbnail` (frame at a given ms); if it is too slow or inaccurate, a small platform channel (iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`) |
| Video playback on Review | `video_player` |
| Local database | `drift` (SQLite) |
| Files | `path_provider` (app documents folder) |
| Upload queue that survives restarts and runs in the background | `background_downloader` (upload tasks) |
| Network state | `connectivity_plus` |
| GPS | `geolocator` |
| Signature pad | `signature` |
| SVG guide outlines | `flutter_svg` |
| Icons | `lucide_icons_flutter` (same icon set as the mockup) |
| State, routing | `flutter_riverpod`, `go_router` |
| HTTP | `dio` |
| Orientation lock | `SystemChrome.setPreferredOrientations` |

Use current stable versions; pin them in `pubspec.lock`.

## Layout

```
app/
  lib/
    main.dart
    data/            question list loader (assets/question-list.json), issue catalog, models
    db/              drift tables: inspections, answers, media, damages, upload_queue
    camera/          camera screen, shutters, guides, sequence (port of CAPSEQ / capList / MULTI)
    screens/         inspections, new_inspection, check_id, damages, review/, summary, sign, sent, settings
    services/        api.dart, ai_reader.dart, uploader.dart, spin.dart, gps.dart, payload.dart (port of inspectionPayload)
    widgets/         drawer, pickers, car top view, paint diagram, tire tabs, 360 viewer
  assets/            question-list.json, issue-catalog.json, guides/*.svg, car drawings
  test/
```

Copy `data/question-list.json`, `data/issue-catalog.json` and `guides/svg/*` into `app/assets/` with a script (`app/tool/sync_assets.dart` or a Makefile target), never by hand edits.

## Camera screen

- Landscape locked; full screen `CameraPreview` (cover fit) inside a `Stack`; the guide outline, shot name, top bar, shutters and thumbnails sit on top.
- Shutters: Damage (amber, above), main (big), Mod (blue, below). Damage and Mod call `takePicture()` and tag the file; the flow does not move. Disable all shutters until the current `takePicture()` returns (the plugin throws on overlapping captures).
- Zoom chips .5 / 1 / 2 and pinch: `setZoomLevel` between `getMinZoomLevel` and `getMaxZoomLevel`. For .5, switch to the ultra-wide back camera from `availableCameras()` when the phone has one; hide .5 when it does not.
- Videos: `startVideoRecording()` / `stopVideoRecording()` with audio on; a timer stops at the item's max seconds (60 walk-around, 30 engine and exhaust). Damage and Mod are off during video.
- Use `ResolutionPreset.veryHigh` (1080p) for photos and video. Keep the controller alive through the whole pass; dispose when leaving the camera; handle `AppLifecycleState.inactive` / `resumed`.
- Every capture is written to the app documents folder and a drift row at once, before the UI moves on.

## Upright photos

- Lock the capture orientation to the current landscape side at the start of the pass (`lockCaptureOrientation`). After each shot, bake the EXIF orientation into the pixels and save the turn applied as `upright_turn_deg` (0, 90, 180, 270).
- Library picks: bake EXIF orientation; if the file has none, call the AI `upright` reading and rotate by its result.

## 360 view

- After the walk-around is recorded, cut 36 evenly spaced frames on the phone (frame k at `(k - 0.5) / 36 × duration`), JPEG, long side 1600 px, named `spin-01.jpg` to `spin-36.jpg`, uploaded with the other files.
- Frames 1, 5, 10, 14, 19, 23, 28, 32 fill the exterior photo slots (front left, left side, rear left, rear, rear right, right side, front right, front).
- Review Exterior: a 360 tile; tap opens a bottom sheet where a horizontal drag steps through the frames and shows the frame number. Works offline.

## Offline and upload

- Every screen works with no signal. The question list and catalog are bundled assets.
- AI readings queue while offline and run when the network returns; the inspector can fill any value by hand meanwhile.
- After the signature: `PUT /api/inspections/{id}` with the record, then each file as a background upload task, then `POST /complete`. The queue is in drift; on app start it re-enqueues anything not confirmed by the server's missing list.
- Status on the Inspections screen: Saved on phone, Uploading (n of m), Report sent, or the server's validation errors.

## Permissions

- iOS `Info.plist`: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription`. Background upload: enable Background Modes → Background fetch per `background_downloader` docs.
- Android `AndroidManifest.xml`: `CAMERA`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `INTERNET`, plus what `background_downloader` lists. `minSdkVersion` 24.

## Config

- Server URL and passcode are entered in Settings (default server URL from `--dart-define=API_BASE_URL=...`). Stored in secure storage (`flutter_secure_storage`).
- App name: Bidbus Field. Bundle id: your own reverse domain, for example `com.yourname.bidbusfield`; it only needs to be unique on your Apple ID.
