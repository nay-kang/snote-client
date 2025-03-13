import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:snote/util.dart';

class AuthState {
  final bool isAuthenticated;
  final String? accessToken;
  final String? email;

  AuthState(this.isAuthenticated, this.accessToken, this.email);
}

class AuthManager {
  static AuthManager? _instance;
  String? _accessToken;
  String? _refreshToken;
  bool _isAuthenticated = false;
  final String otpEndpoint = '/api/auth/email_otp/';
  final String tokenEndpoint = '/api/auth/token/';
  final String refreshEndpoint = '/api/auth/token/refresh/';
  // Add timeout duration
  static const requestTimeout = Duration(seconds: 5);
  Timer? _refreshTimer;

  final _secureStorage = const FlutterSecureStorage();
  final _authStateController = BehaviorSubject<AuthState>();

  var _baseUrl = "";
  final _baseUrlCompleter = Completer<void>();

  AuthManager._internal() {
    getConfig().then((config) {
      _baseUrl = config['api_host'];
      _baseUrlCompleter.complete();
    });
    _loadTokens(); // This will emit the initial state after checking tokens
  }

  static AuthManager getInstance() {
    _instance ??= AuthManager._internal();
    return _instance!;
  }

  // Add proper singleton destructor
  static void destroy() {
    if (_instance != null) {
      _instance!.dispose();
      _instance = null;
    }
  }

  Future<void> _ensureBaseUrl() async {
    await _baseUrlCompleter.future;
  }

  // Modify HTTP requests to include timeout
  Future<http.Response> _postWithTimeout(String uri,
      {Map<String, dynamic>? body}) async {
    await _ensureBaseUrl();
    return http
        .post(
          Uri.parse('$_baseUrl$uri'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _isAuthenticated;

  Stream<AuthState> get authStateChanges => _authStateController.stream;

  Future<void> _loadTokens() async {
    _accessToken = await _secureStorage.read(key: 'accessToken');
    _refreshToken = await _secureStorage.read(key: 'refreshToken');

    var isAuthenticated = false;
    String? email;

    if (_accessToken != null) {
      final validationResult = await _validateAndRefreshToken(_accessToken!);
      isAuthenticated = validationResult.$1;
      email = validationResult.$2;
    }

    _isAuthenticated = isAuthenticated;
    _updateAuthState(_isAuthenticated, _accessToken, email);
  }

  Future<(bool, String?)> _validateAndRefreshToken(String token) async {
    try {
      final jwt = JWT.decode(token);
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(jwt.payload['exp'] * 1000);

      if (expiry.isAfter(DateTime.now())) {
        return (true, jwt.payload['email'] as String?);
      }

      final refreshSuccess = await refreshTokenPair();
      if (refreshSuccess) {
        return (true, JWT.decode(_accessToken!).payload['email'] as String?);
      }
    } catch (e) {
      final refreshSuccess = await refreshTokenPair();
      if (refreshSuccess) {
        return (true, JWT.decode(_accessToken!).payload['email'] as String?);
      }
    }
    return (false, null);
  }

  void _setupAutoRefresh(String token) {
    _refreshTimer?.cancel();
    try {
      final jwt = JWT.decode(token);
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(jwt.payload['exp'] * 1000);
      final timeUntilRefresh = expiry
          .subtract(const Duration(minutes: 1))
          .difference(DateTime.now());

      if (timeUntilRefresh.isNegative) {
        refreshTokenPair();
      } else {
        _refreshTimer = Timer(timeUntilRefresh, refreshTokenPair);
      }
    } catch (e) {
      debugPrint('Error setting up auto refresh: $e');
    }
  }

  Future<void> _saveTokens() async {
    await _secureStorage.write(key: 'accessToken', value: _accessToken);
    await _secureStorage.write(key: 'refreshToken', value: _refreshToken);
    if (_accessToken != null) {
      _setupAutoRefresh(_accessToken!);
    }
    final email = _accessToken != null
        ? JWT.decode(_accessToken!).payload['email']
        : null;
    _updateAuthState(_isAuthenticated, _accessToken, email);
  }

  Future<bool> requestOtp(String email) async {
    try {
      final response = await _postWithTimeout(
        otpEndpoint,
        body: {'email': email},
      );

      if (response.statusCode == 200) {
        return true;
      }
    } catch (error) {
      logout();
      debugPrint('Login error: $error');
    }
    return false;
  }

  Future<bool> login({required String email, required String otpCode}) async {
    try {
      final response = await _postWithTimeout(
        tokenEndpoint,
        body: {'email': email, 'code': otpCode},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access'];
        _refreshToken = data['refresh'];
        _isAuthenticated = true;
        await _saveTokens();
        return true;
      } else {
        logout();
        debugPrint('Login failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (error) {
      logout();
      debugPrint('Login error: $error');
      return false;
    }
  }

  Future<bool> refreshTokenPair() async {
    if (_refreshToken == null) {
      debugPrint('No refresh token available.');
      logout();
      return false;
    }

    try {
      final response = await _postWithTimeout(
        refreshEndpoint,
        body: {'refresh': _refreshToken},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access'];
        _refreshToken = data['refresh'];
        _isAuthenticated = true;
        await _saveTokens();
        return true;
      } else {
        logout();
        debugPrint(
            'Token refresh failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (error) {
      logout();
      debugPrint('Token refresh error: $error');
      return false;
    }
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    _isAuthenticated = false;
    await _secureStorage.delete(key: 'accessToken');
    await _secureStorage.delete(key: 'refreshToken');
    _updateAuthState(_isAuthenticated, _accessToken, null);
  }

  void _updateAuthState(bool isAuthenticated, String? token, String? email) {
    if (!_authStateController.isClosed) {
      _authStateController.add(AuthState(isAuthenticated, token, email));
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    _authStateController.close();
  }
}
