/// @intent 사용자 인증 및 계정 상태(로그인/회원가입/게스트 모드/로그아웃) 중앙 상태 관리자
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  loading,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthStatus _status = AuthStatus.initial;
  String? _userId;
  String? _email;
  String? _displayName;
  bool _isGuestMode = false;
  String? _errorMessage;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService() {
    init();
  }

  AuthStatus get status => _status;
  String? get userId => _userId;
  String? get email => _email;
  String? get displayName => _displayName;
  bool get isGuestMode => _isGuestMode;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;

  /// 앱 기동 시 인증 세션 복원 및 상태 초기화
  Future<void> init() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final user = await _authService.restoreSession();
      if (user != null) {
        _applyUserInfo(user);
        _status = AuthStatus.authenticated;
      } else {
        _resetUserInfo();
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      debugPrint('[AuthProvider] init 세션 복원 실패: $e');
      _resetUserInfo();
      _status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  /// 이메일 / 비밀번호 로그인
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final user = await _authService.signIn(
        email: email,
        password: password,
      );
      _applyUserInfo(user);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = _parseErrorMessage(e);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// 새 계정 회원가입
  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      _applyUserInfo(user);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = _parseErrorMessage(e);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// 게스트 모드로 계속 진행 (오프라인 모드)
  Future<void> continueAsGuest() async {
    _errorMessage = null;
    final guest = await _authService.setGuestMode();
    _applyUserInfo(guest);
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  /// 로그아웃
  Future<void> signOut() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('[AuthProvider] signOut 에러: $e');
    }

    _resetUserInfo();
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// 에러 메시지 초기화
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _applyUserInfo(AuthUserInfo user) {
    _userId = user.id;
    _email = user.email;
    _displayName = user.displayName;
    _isGuestMode = user.isGuest;
  }

  void _resetUserInfo() {
    _userId = null;
    _email = null;
    _displayName = null;
    _isGuestMode = false;
  }

  String _parseErrorMessage(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return '이메일 또는 비밀번호가 일치하지 않습니다.';
    } else if (msg.contains('already registered') ||
        msg.contains('user_already_exists')) {
      return '이미 가입된 이메일 주소입니다.';
    } else if (msg.contains('weak password') ||
        msg.contains('password should be at least')) {
      return '비밀번호는 최소 6자 이상이어야 합니다.';
    } else if (msg.contains('network') || msg.contains('socketexception')) {
      return '네트워크 연결을 확인해주세요.';
    }
    return '인증 처리 중 오류가 발생했습니다. 다시 시도해주세요.';
  }
}
