import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class RelayClient {
  final String baseUrl; // e.g. "http://10.71.0.1:8086"
  final http.Client _http;
  RelayClient(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  // GET /providers — returns list of authenticated cloud accounts
  Future<List<Map<String, dynamic>>> getProviders() async {
    final resp = await _http.get(Uri.parse('$baseUrl/providers'));
    if (resp.statusCode != 200) throw Exception('GET /providers: ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['providers'] ?? []);
  }

  // GET /files — returns list of uploaded FileMaps
  Future<List<Map<String, dynamic>>> listFiles() async {
    final resp = await _http.get(Uri.parse('$baseUrl/files'));
    if (resp.statusCode != 200) throw Exception('GET /files: ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['files'] ?? []);
  }

  // POST /files/upload — multipart form with field "file"
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/files/upload'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception('POST /files/upload: ${streamed.statusCode}: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // GET /files/{id} — download file bytes
  Future<Uint8List> downloadFile(String fileId) async {
    final resp = await _http.get(Uri.parse('$baseUrl/files/$fileId'));
    if (resp.statusCode != 200) throw Exception('GET /files/$fileId: ${resp.statusCode}');
    return resp.bodyBytes;
  }

  // DELETE /files/{id}
  Future<void> deleteFile(String fileId) async {
    final resp = await _http.delete(Uri.parse('$baseUrl/files/$fileId'));
    if (resp.statusCode != 200) throw Exception('DELETE /files/$fileId: ${resp.statusCode}');
  }
}
