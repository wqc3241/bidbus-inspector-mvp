// Check ID: the license and registration come from the camera only; the family proof may also come from the library;
// a camera with access turned off says so instead of doing nothing.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/check_id.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

class _Cam extends CameraPlatform with MockPlatformInterfaceMixin {
  @override
  Future<List<CameraDescription>> availableCameras() async => const [CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90)];
}

class _Pick extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  final asked = <ImageSource>[];
  bool deny = false;
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    asked.add(source);
    if (deny) throw PlatformException(code: 'camera_access_denied');
    return null; // the inspector closes the camera without a photo
  }
}

void main() {
  final pick = _Pick();
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
    CameraPlatform.instance = _Cam();
    ImagePickerPlatform.instance = pick;
  });

  testWidgets('license and registration: camera only; family proof: camera or library; access off says so', (t) async {
    store.ins['c'] = newInspection(id: 'c', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: CheckIdScreen('c'))));

    await t.tap(find.text("Driver's license"));
    await t.pumpAndSettle();
    expect(find.text('Pick from library'), findsNothing);
    await t.tap(find.text('Registration card'));
    await t.pumpAndSettle();
    expect(find.text('Pick from library'), findsNothing);
    expect(pick.asked, [ImageSource.camera, ImageSource.camera]);

    takeDoc(t.element(find.byType(CheckIdScreen)), 'c', 'ph_family');
    await t.pumpAndSettle();
    await t.tap(find.text('Pick from library'));
    await t.pumpAndSettle();
    expect(pick.asked.last, ImageSource.gallery);

    pick.deny = true;
    await t.tap(find.text("Driver's license"));
    await t.pumpAndSettle();
    expect(find.text('Camera access is off. Allow it in Settings.'), findsOneWidget);
  });
}
