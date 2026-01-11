import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage{
  final _storage=const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveAccessToken(String token)async{
    await _storage.write(key: 'access_token',value: token);
   final check = await _storage.read(key: 'access_token');
  print("Saved token: $check"); 
  }

  Future<String?> getAccessToken() async{
     final token= await _storage.read(key:'access_token');
     print("Access token saved :$token");
     return token;
  }

  Future <void> saveRefreshToken(String token) async{
    await _storage.write(key: 'refresh_token', value: token);
  }

  Future<String?> getRefreshToken() async{
    return await _storage.read(key: 'refresh_token');
  }

  Future<void> deleteAll() async{
    await _storage.deleteAll();
  }
}