import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'resources/esim.dart';
import 'resources/plans.dart';

/// Client for the Wiiline eSIM API.
///
/// **Server-side Dart** (a backend you control): pass your [apiKey].
///
/// ```dart
/// final client = WiilineClient(apiKey: Platform.environment['WIILINE_API_KEY']);
/// ```
///
/// **Inside a Flutter app: never embed the API key.** Anything shipped in an
/// app can be extracted, and the key spends your account balance. Route the
/// app through your own backend instead, which holds the key and forwards the
/// same paths to Wiiline:
///
/// ```dart
/// final client = WiilineClient(
///   baseUrl: 'https://api.your-company.com/wiiline', // your backend
///   headers: {'Authorization': 'Bearer $yourUserSessionToken'},
/// );
/// ```
class WiilineClient {
  WiilineClient({
    String? apiKey,
    String baseUrl = defaultBaseUrl,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _timeout = timeout,
        _headers = Map.unmodifiable(headers ?? const {}),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null {
    if ((apiKey == null || apiKey.isEmpty) &&
        !_headers.keys.any((k) => k.toLowerCase() == 'authorization') &&
        baseUrl == defaultBaseUrl) {
      throw ArgumentError(
        'WiilineClient: pass an apiKey (server-side), or a baseUrl pointing at '
        'your own backend (in an app).',
      );
    }
    plans = PlansResource(this);
    esim = EsimResource(this);
  }

  /// The public Wiiline API.
  static const String defaultBaseUrl = 'https://wiiesim.me';

  final String? _apiKey;
  final String _baseUrl;
  final Duration _timeout;
  final Map<String, String> _headers;
  final http.Client _http;
  final bool _ownsHttp;

  /// Plan catalogue.
  late final PlansResource plans;

  /// eSIM ordering and management.
  late final EsimResource esim;

  /// Closes the underlying HTTP client (only if this client created it).
  void close() {
    if (_ownsHttp) _http.close();
  }

  Uri _buildUri(String path, Map<String, Object?>? query) {
    final params = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) params[k] = '$v';
    });
    final uri = Uri.parse('$_baseUrl$path');
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  /// Sends a request and returns the decoded JSON body.
  ///
  /// Used by the resource classes; exposed for endpoints the SDK doesn't wrap
  /// yet. Throws [WiilineApiException] for any unsuccessful call.
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (_apiKey != null && _apiKey!.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      if (body != null) 'Content-Type': 'application/json',
      ..._headers,
    };

    http.Response response;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw WiilineApiException(
        'Request timed out after ${_timeout.inSeconds}s',
        status: 0,
        code: 'timeout',
      );
    } catch (e) {
      throw WiilineApiException('Network error calling $path: $e', status: 0, code: 'network_error');
    }

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // Non-JSON body (e.g. a proxy error page).
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok || json == null || json['success'] == false) {
      final retryHeader = response.headers['retry-after'];
      final retryAfter = json?['retryAfter'] is num
          ? (json!['retryAfter'] as num).toInt()
          : (retryHeader != null ? int.tryParse(retryHeader) : null);
      throw WiilineApiException(
        (json?['message'] ?? json?['error'] ?? 'Request to $path failed with status ${response.statusCode}').toString(),
        status: response.statusCode,
        code: (json?['error'] ?? 'api_error').toString(),
        details: json?['details'],
        retryAfter: retryAfter,
        body: json,
      );
    }
    return json;
  }
}
