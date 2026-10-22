import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/r2_config.dart';
import 'r2_paths.dart';

/// Cloudflare R2 용 최소 S3 클라이언트 (path-style + SigV4).
class R2Client {
  R2Client({
    Dio? dio,
    String? accessKeyId,
    String? secretAccessKey,
    String? bucket,
    String? host,
    String? region,
  })  : _accessKeyId = accessKeyId ?? R2Config.accessKeyId,
        _secretAccessKey = secretAccessKey ?? R2Config.secretAccessKey,
        _bucket = bucket ?? R2Config.bucket,
        _host = host ?? R2Config.endpointHost,
        _region = region ?? R2Config.region,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 2),
                sendTimeout: const Duration(minutes: 2),
                followRedirects: false,
                validateStatus: (code) => code != null && code < 500,
              ),
            );

  final Dio _dio;
  final String _accessKeyId;
  final String _secretAccessKey;
  final String _bucket;
  final String _host;
  final String _region;

  String get bucket => _bucket;

  Future<Uint8List?> getObject(
    String key, {
    CancelToken? cancelToken,
  }) async {
    final response = await _send(
      method: 'GET',
      key: key,
      cancelToken: cancelToken,
      responseType: ResponseType.bytes,
    );
    if (response.statusCode == 404) return null;
    _throwIfFailed(response, 'GET $key');
    final data = response.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<void> putObject(
    String key,
    List<int> bytes, {
    String? contentType,
    CancelToken? cancelToken,
  }) async {
    final response = await _send(
      method: 'PUT',
      key: key,
      body: bytes,
      contentType: contentType ?? _contentTypeFor(key),
      cancelToken: cancelToken,
    );
    _throwIfFailed(response, 'PUT $key');
  }

  Future<bool> objectExists(String key, {CancelToken? cancelToken}) async {
    final response = await _send(
      method: 'HEAD',
      key: key,
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) return false;
    _throwIfFailed(response, 'HEAD $key');
    return true;
  }

  Future<void> deleteObject(String key, {CancelToken? cancelToken}) async {
    final response = await _send(
      method: 'DELETE',
      key: key,
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) return;
    _throwIfFailed(response, 'DELETE $key');
  }

  Future<List<R2ObjectInfo>> listObjects({
    required String prefix,
    String? delimiter,
    CancelToken? cancelToken,
  }) async {
    final objects = <R2ObjectInfo>[];
    String? token;
    do {
      final query = <String, String>{
        'list-type': '2',
        'prefix': prefix,
        if (delimiter != null && delimiter.isNotEmpty) 'delimiter': delimiter,
        'continuation-token': ?token,
      };
      final response = await _send(
        method: 'GET',
        key: '',
        query: query,
        cancelToken: cancelToken,
        responseType: ResponseType.plain,
      );
      _throwIfFailed(response, 'LIST $prefix');
      final xml = '${response.data ?? ''}';
      objects.addAll(_parseListContents(xml));
      final truncated = _xmlTag(xml, 'IsTruncated')?.toLowerCase() == 'true';
      token = truncated ? _xmlTag(xml, 'NextContinuationToken') : null;
    } while (token != null && token.isNotEmpty);
    return objects;
  }

  Future<List<String>> listCommonPrefixes({
    required String prefix,
    String delimiter = '/',
    CancelToken? cancelToken,
  }) async {
    final prefixes = <String>[];
    String? token;
    do {
      final query = <String, String>{
        'list-type': '2',
        'prefix': prefix,
        'delimiter': delimiter,
        'continuation-token': ?token,
      };
      final response = await _send(
        method: 'GET',
        key: '',
        query: query,
        cancelToken: cancelToken,
        responseType: ResponseType.plain,
      );
      _throwIfFailed(response, 'LIST prefixes $prefix');
      final xml = '${response.data ?? ''}';
      prefixes.addAll(_parseCommonPrefixes(xml));
      final truncated = _xmlTag(xml, 'IsTruncated')?.toLowerCase() == 'true';
      token = truncated ? _xmlTag(xml, 'NextContinuationToken') : null;
    } while (token != null && token.isNotEmpty);
    return prefixes;
  }

  Future<Response<dynamic>> _send({
    required String method,
    required String key,
    Map<String, String>? query,
    List<int>? body,
    String? contentType,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.bytes,
  }) {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = _dateStamp(now);
    final payloadHash = sha256.convert(body ?? const <int>[]).toString();
    final path = key.isEmpty ? '/$_bucket' : '/$_bucket/$key';
    final headers = <String, String>{
      'host': _host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      'content-type': ?contentType,
    };
    final authorization = signV4(
      method: method,
      canonicalUri: awsUriEncode(path, encodeSlash: false),
      query: query ?? const {},
      headers: headers,
      payloadHash: payloadHash,
      amzDate: amzDate,
      dateStamp: dateStamp,
      region: _region,
      accessKeyId: _accessKeyId,
      secretAccessKey: _secretAccessKey,
    );
    headers['authorization'] = authorization;

    return _dio.request<dynamic>(
      'https://$_host$path',
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      options: Options(
        method: method,
        headers: headers,
        responseType: responseType,
        contentType: contentType,
      ),
    );
  }

  void _throwIfFailed(Response<dynamic> response, String action) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    final snippet = _errorSnippet(response.data);
    throw Exception('R2 $action 실패 ($code)${snippet.isEmpty ? '' : ': $snippet'}');
  }

  static String _errorSnippet(dynamic data) {
    if (data == null) return '';
    if (data is List<int>) {
      try {
        return utf8.decode(data, allowMalformed: true).replaceAll('\n', ' ').trim();
      } catch (_) {
        return '';
      }
    }
    return '$data'.replaceAll('\n', ' ').trim();
  }

  static String _contentTypeFor(String key) {
    final lower = key.toLowerCase();
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  static List<R2ObjectInfo> _parseListContents(String xml) {
    final out = <R2ObjectInfo>[];
    final blockRe = RegExp(r'<Contents>([\s\S]*?)</Contents>', caseSensitive: false);
    for (final match in blockRe.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final key = _xmlTag(block, 'Key');
      if (key == null || key.isEmpty) continue;
      final size = int.tryParse(_xmlTag(block, 'Size') ?? '') ?? 0;
      out.add(R2ObjectInfo(key: key, size: size));
    }
    return out;
  }

  static List<String> _parseCommonPrefixes(String xml) {
    final out = <String>[];
    final blockRe = RegExp(
      r'<CommonPrefixes>([\s\S]*?)</CommonPrefixes>',
      caseSensitive: false,
    );
    for (final match in blockRe.allMatches(xml)) {
      final prefix = _xmlTag(match.group(1) ?? '', 'Prefix');
      if (prefix != null && prefix.isNotEmpty) out.add(prefix);
    }
    return out;
  }

  static String? _xmlTag(String xml, String tag) {
    final match = RegExp(
      '<$tag>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1);
  }
}

@visibleForTesting
String awsUriEncode(String input, {bool encodeSlash = true}) {
  final bytes = utf8.encode(input);
  final out = StringBuffer();
  for (final byte in bytes) {
    final ch = String.fromCharCode(byte);
    final unreserved = (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        (byte >= 0x30 && byte <= 0x39) ||
        ch == '-' ||
        ch == '.' ||
        ch == '_' ||
        ch == '~';
    if (unreserved) {
      out.write(ch);
    } else if (ch == '/' && !encodeSlash) {
      out.write('/');
    } else {
      out.write('%');
      out.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

@visibleForTesting
String signV4({
  required String method,
  required String canonicalUri,
  required Map<String, String> query,
  required Map<String, String> headers,
  required String payloadHash,
  required String amzDate,
  required String dateStamp,
  required String region,
  required String accessKeyId,
  required String secretAccessKey,
}) {
  final normalizedHeaders = <String, String>{};
  headers.forEach((key, value) {
    normalizedHeaders[key.toLowerCase()] = value.trim();
  });
  final signedHeaderNames = normalizedHeaders.keys.toList()..sort();
  final canonicalHeaders = signedHeaderNames
      .map((name) => '$name:${normalizedHeaders[name]}\n')
      .join();
  final signedHeaders = signedHeaderNames.join(';');
  final canonicalQuery = canonicalQueryString(query);
  final canonicalRequest = [
    method.toUpperCase(),
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');
  const algorithm = 'AWS4-HMAC-SHA256';
  final credentialScope = '$dateStamp/$region/s3/aws4_request';
  final stringToSign = [
    algorithm,
    amzDate,
    credentialScope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');
  final signingKey = _signingKey(secretAccessKey, dateStamp, region, 's3');
  final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign));
  return '$algorithm Credential=$accessKeyId/$credentialScope, '
      'SignedHeaders=$signedHeaders, Signature=$signature';
}

@visibleForTesting
String canonicalQueryString(Map<String, String> query) {
  if (query.isEmpty) return '';
  final parts = query.entries
      .map(
        (e) => '${awsUriEncode(e.key)}=${awsUriEncode(e.value)}',
      )
      .toList()
    ..sort();
  return parts.join('&');
}

List<int> _hmac(List<int> key, String data) {
  return Hmac(sha256, key).convert(utf8.encode(data)).bytes;
}

List<int> _signingKey(
  String secret,
  String dateStamp,
  String region,
  String service,
) {
  final kDate = _hmac(utf8.encode('AWS4$secret'), dateStamp);
  final kRegion = _hmac(kDate, region);
  final kService = _hmac(kRegion, service);
  return _hmac(kService, 'aws4_request');
}

String _amzDate(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _dateStamp(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}';
}
