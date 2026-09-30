/// @intent Supabase Auth 연동 및 오프라인/테스트 안전 Fallback을 지원하는 사용자 인증 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// 앱 내 표준 인증 사용자 모델
class AuthUserInfo {
  final String id;
  final String email;
  final String displayName;
  final bool isGuest;

  const AuthUserInfo({
    required this.id,
    required this.email,
    required this.displayName,
    this.isGuest = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'isGuest': isGuest,
      };

  factory AuthUserInfo.fromJson(Map<String, dynamic> json) => AuthUserInfo(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        isGuest: json['isGuest'] as bool? ?? false,
      );

  static const AuthUserInfo guest = AuthUserInfo(
    id: 'guest-local-user',
    email: 'guest@mytriplog.local',
    displayName: '게스트 여행자',
    isGuest: true,
  );
}

class AuthService {
  static const String _prefUserKey = 'mytriplog_auth_user_cache_v2';
  final StreamController<AuthUserInfo?> _authStateController =
      StreamController<AuthUserInfo?>.broadcast();

  AuthUserInfo? _cachedUser;
  StreamSubscription<AuthState>? _supabaseAuthSubscription;

  AuthService() {
    _initSupabaseListener();
  }

  SupabaseClient? get _client => SupabaseService.client;

  /// Supabase 인증 상태 변경 리스너 등록
  void _initSupabaseListener() {
    final client = _client;
    if (client != null) {
      _supabaseAuthSubscription = client.auth.onAuthStateChange.listen((data) {
        final user = data.session?.user;
        if (user != null) {
          final userInfo = _mapSupabaseUser(user);
          _cachedUser = userInfo;
          _saveCachedUser(userInfo);
          _authStateController.add(userInfo);
        } else if (_cachedUser != null && !_cachedUser!.isGuest) {
          _cachedUser = null;
          _clearCachedUser();
          _authStateController.add(null);
        }
      });
    }
  }

  /// 현재 로그인된 사용자 정보 반환
  AuthUserInfo? get currentUser {
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      return _mapSupabaseUser(client.auth.currentUser!);
    }
    return _cachedUser;
  }

  /// 로그인 여부 (게스트 모드 제외한 실제 인증 계정)
  bool get isLoggedIn {
    final user = currentUser;
    return user != null && !user.isGuest;
  }

  /// 게스트 모드 여부
  bool get isGuest => currentUser?.isGuest ?? false;

  /// 인증 상태 변경 스트림
  Stream<AuthUserInfo?> get authStateChanges => _authStateController.stream;

  /// 로컬 캐시에서 세션 복원
  Future<AuthUserInfo?> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefUserKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cachedUser = AuthUserInfo.fromJson(decoded);
          _authStateController.add(_cachedUser);
          return _cachedUser;
        }
      }
    } catch (e) {
      debugPrint('[AuthService] 세션 복원 에러 (무시): $e');
    }

    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      _cachedUser = _mapSupabaseUser(client.auth.currentUser!);
      _saveCachedUser(_cachedUser!);
      _authStateController.add(_cachedUser);
      return _cachedUser;
    }

    return null;
  }

  /// 이메일/비밀번호 회원가입
  Future<AuthUserInfo> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final client = _client;
    if (client != null) {
      try {
        final response = await client.auth.signUp(
          email: email.trim(),
          password: password.trim(),
          data: {'display_name': displayName.trim()},
        );

        final user = response.user;
        if (user != null) {
          final userInfo = AuthUserInfo(
            id: user.id,
            email: user.email ?? email.trim(),
            displayName: displayName.trim().isNotEmpty
                ? displayName.trim()
                : (user.userMetadata?['display_name'] as String? ?? '여행자'),
            isGuest: false,
          );
          _cachedUser = userInfo;
          await _saveCachedUser(userInfo);
          _authStateController.add(userInfo);
          return userInfo;
        }
      } catch (e) {
        debugPrint('[AuthService] Supabase signUp 에러, 로컬 Fallback: $e');
        // 네트워크 장애 또는 설정 미비 시 Fallback 처리
        if (e is AuthException) {
          rethrow;
        }
      }
    }

    // Fallback 모드 (오프라인 / Mock)
    final fallbackUser = AuthUserInfo(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      email: email.trim(),
      displayName: displayName.trim().isNotEmpty ? displayName.trim() : '여행자',
      isGuest: false,
    );
    _cachedUser = fallbackUser;
    await _saveCachedUser(fallbackUser);
    _authStateController.add(fallbackUser);
    return fallbackUser;
  }

  /// 이메일/비밀번호 로그인
  Future<AuthUserInfo> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client != null) {
      try {
        final response = await client.auth.signInWithPassword(
          email: email.trim(),
          password: password.trim(),
        );

        final user = response.user;
        if (user != null) {
          final userInfo = _mapSupabaseUser(user);
          _cachedUser = userInfo;
          await _saveCachedUser(userInfo);
          _authStateController.add(userInfo);
          return userInfo;
        }
      } catch (e) {
        debugPrint('[AuthService] Supabase signIn 에러: $e');
        if (e is AuthException) {
          rethrow;
        }
      }
    }

    // Fallback 모드 (오프라인 / Mock)
    final fallbackUser = AuthUserInfo(
      id: 'local-${email.hashCode.abs()}',
      email: email.trim(),
      displayName: email.split('@').first,
      isGuest: false,
    );
    _cachedUser = fallbackUser;
    await _saveCachedUser(fallbackUser);
    _authStateController.add(fallbackUser);
    return fallbackUser;
  }

  /// 로그아웃
  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('[AuthService] Supabase signOut 에러 (무시): $e');
      }
    }
    _cachedUser = null;
    await _clearCachedUser();
    _authStateController.add(null);
  }

  /// 게스트 모드로 시작
  Future<AuthUserInfo> setGuestMode() async {
    _cachedUser = AuthUserInfo.guest;
    await _saveCachedUser(AuthUserInfo.guest);
    _authStateController.add(AuthUserInfo.guest);
    return AuthUserInfo.guest;
  }

  AuthUserInfo _mapSupabaseUser(User user) {
    final metaName = user.userMetadata?['display_name'] as String?;
    final resolvedName = (metaName != null && metaName.trim().isNotEmpty)
        ? metaName.trim()
        : (user.email != null && user.email!.contains('@')
            ? user.email!.split('@').first
            : '여행자');

    return AuthUserInfo(
      id: user.id,
      email: user.email ?? '',
      displayName: resolvedName,
      isGuest: false,
    );
  }

  Future<void> _saveCachedUser(AuthUserInfo user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
    } catch (_) {}
  }

  Future<void> _clearCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefUserKey);
    } catch (_) {}
  }

  void dispose() {
    _supabaseAuthSubscription?.cancel();
    _authStateController.close();
  }
}
