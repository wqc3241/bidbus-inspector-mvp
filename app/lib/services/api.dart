// Server calls (docs/06-backend.md, docs/12-scheduler-sync.md). Every /api call carries the app passcode, or the
// inspector's scheduler sign-in when the server has it set up.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class Api {
  final String base, passcode; // passcode: the app passcode, or the sign-in's access token
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

  // scheduler sign-in and appointments
  Future<void> sendCode(String email) => dio.post('/api/auth/code', data: {'email': email});
  Future<Map<String, dynamic>> verifyCode(String email, String code) async => (await dio.post('/api/auth/verify', data: {'email': email, 'code': code})).data;
  Future<Map<String, dynamic>> refresh(String token) async => (await dio.post('/api/auth/refresh', data: {'refresh_token': token})).data;
  Future<Map<String, dynamic>> appointments() async => (await dio.get('/api/appointments')).data;
  Future<Map<String, dynamic>> brief(String slot) async => (await dio.get('/api/appointments/$slot/brief')).data;
  Future<Uint8List> document(String slot, String doc) async =>
      Uint8List.fromList((await dio.get<List<int>>('/api/appointments/$slot/documents/$doc', options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)))).data!);
}

// the server's message for a refused call (FastAPI's detail), else a plain one
String apiError(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['detail'] is String) return d['detail'];
    if (e.response == null) return 'Server not reached';
  }
  return 'Something went wrong. Try again.';
}
