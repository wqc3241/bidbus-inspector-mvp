// Server calls (docs/06-backend.md). Every /api call carries the app passcode.
import 'dart:io';

import 'package:dio/dio.dart';

class Api {
  final String base, passcode;
  late final Dio dio;
  Api(this.base, this.passcode) {
    dio = Dio(BaseOptions(
      baseUrl: base.replaceAll(RegExp(r'/+$'), ''),
      headers: {'Authorization': 'Bearer $passcode'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  Future<Map<String, dynamic>> health() async => (await dio.get('/api/health')).data;
  Future<Map<String, dynamic>> vin(String vin) async => (await dio.get('/api/vin/$vin')).data;

  Future<Map<String, dynamic>> read(String kind, File image, {String? section, String? fuel, String? hint}) async {
    final form = FormData.fromMap({
      'kind': kind, 'image': await MultipartFile.fromFile(image.path, filename: 'photo.jpg'),
      'section': ?section, 'fuel': ?fuel, 'hint': ?hint,
    });
    return (await dio.post('/api/ai/read', data: form, options: Options(receiveTimeout: const Duration(seconds: 40)))).data;
  }

  Future<Map<String, dynamic>> putInspection(String id, Map<String, dynamic> body) async => (await dio.put('/api/inspections/$id', data: body)).data;
  Future<Map<String, dynamic>> status(String id) async => (await dio.get('/api/inspections/$id')).data;
  Future<Response> complete(String id) => dio.post('/api/inspections/$id/complete', options: Options(validateStatus: (s) => s != null && s < 500));
  Future<void> resend(String id) => dio.post('/api/inspections/$id/resend-email');
}
