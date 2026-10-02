import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'client_context.dart';

/// A failed call to the backend, with a message that can be shown as is.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  /// `null` when the server was never reached (offline, timeout, wrong URL).
  final int? statusCode;

  final String message;

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The one way the app talks to the SENECApp backend.
///
/// Every request carries the student's bearer token and the [ClientContext]
/// headers. JSON in, JSON out: repositories turn the decoded maps into models.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required AuthService auth,
    required ClientContext context,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _auth = auth,
       _context = context,
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final AuthService _auth;
  final ClientContext _context;
  final http.Client _http;
  final Duration timeout;

  /// Called when the backend still answers 401 after a fresh token: the
  /// session is gone and the student has to sign in again.
  VoidCallback? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) => _send('POST', path, query: query, body: body);

  Future<dynamic> put(
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) => _send('PUT', path, query: query, body: body);

  Future<dynamic> patch(
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) => _send('PATCH', path, query: query, body: body);

  Future<dynamic> delete(String path, {Map<String, Object?>? query}) =>
      _send('DELETE', path, query: query);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) async {
    var response = await _attempt(method, path, query, body);

    // Tokens last an hour. One expired mid-request gets a single retry with a
    // freshly minted token before the session is treated as lost.
    if (response.statusCode == 401) {
      response = await _attempt(method, path, query, body, refreshToken: true);
      if (response.statusCode == 401) onUnauthorized?.call();
    }

    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    throw ApiException(response.statusCode, _errorMessage(response, text));
  }

  Future<http.Response> _attempt(
    String method,
    String path,
    Map<String, Object?>? query,
    Object? body, {
    bool refreshToken = false,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(_context.headers)
      ..headers['Accept'] = 'application/json';

    final token = await _auth.idToken(forceRefresh: refreshToken);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(null, 'The server took too long to answer.');
    } on http.ClientException {
      throw const ApiException(
        null,
        "Can't reach SENECApp. Check your connection.",
      );
    }
  }

  /// Joins [path] to the base URL. Null query values are dropped, lists become
  /// repeated keys (`?interest_id=1&interest_id=2`).
  Uri _uri(String path, Map<String, Object?>? query) {
    final uri = Uri.parse('$_baseUrl$path');
    final params = <String, dynamic>{
      for (final MapEntry(:key, :value) in (query ?? const {}).entries)
        if (value != null)
          key: value is Iterable ? [for (final v in value) '$v'] : '$value',
    };
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  /// FastAPI puts the reason in `detail`: a string for errors the API raises,
  /// a list of field problems for invalid input.
  static String _errorMessage(http.Response response, String text) {
    try {
      final detail = (jsonDecode(text) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'];
      }
    } on Object {
      // Not JSON (a proxy error page, for example).
    }
    return 'Request failed (${response.statusCode}).';
  }
}
