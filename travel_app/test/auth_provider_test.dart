/// @intent AuthProvider 인증 상태 관리자 단위 테스트 (상태 전이, 게스트 모드, 로그인/회원가입/로그아웃)
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/providers/auth_provider.dart';
import 'package:travel_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthProvider 상태 전이 및 계정 관리 단위 테스트', () {
    late AuthService authService;
    late AuthProvider authProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
      authProvider = AuthProvider(authService: authService);
      await authProvider.init();
    });

    test('세션이 없는 초기 상태에서 unauthenticated 상태여야 한다', () {
      expect(authProvider.status, AuthStatus.unauthenticated);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.isGuestMode, isFalse);
      expect(authProvider.userId, isNull);
    });

    test('continueAsGuest 호출 시 authenticated 상태가 되고 게스트 모드로 설정된다', () async {
      await authProvider.continueAsGuest();

      expect(authProvider.status, AuthStatus.authenticated);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isGuestMode, isTrue);
      expect(authProvider.displayName, '게스트 여행자');
      expect(authProvider.userId, isNotNull);
    });

    test('signIn 호출 시 인증이 완료되고 사용자 정보가 설정된다', () async {
      final success = await authProvider.signIn(
        email: 'traveler@mytriplog.com',
        password: 'password123',
      );

      expect(success, isTrue);
      expect(authProvider.status, AuthStatus.authenticated);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isGuestMode, isFalse);
      expect(authProvider.email, 'traveler@mytriplog.com');
      expect(authProvider.displayName, 'traveler');
    });

    test('signUp 호출 시 새 계정으로 가입 및 즉시 로그인된다', () async {
      final success = await authProvider.signUp(
        email: 'newbie@mytriplog.com',
        password: 'securePassword!',
        displayName: '행복한탐험가',
      );

      expect(success, isTrue);
      expect(authProvider.status, AuthStatus.authenticated);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isGuestMode, isFalse);
      expect(authProvider.email, 'newbie@mytriplog.com');
      expect(authProvider.displayName, '행복한탐험가');
    });

    test('로그인 상태에서 signOut 호출 시 unauthenticated 상태로 초기화된다', () async {
      await authProvider.signIn(
        email: 'user@mytriplog.com',
        password: 'password123',
      );
      expect(authProvider.isAuthenticated, isTrue);

      await authProvider.signOut();

      expect(authProvider.status, AuthStatus.unauthenticated);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.userId, isNull);
      expect(authProvider.email, isNull);
      expect(authProvider.displayName, isNull);
      expect(authProvider.isGuestMode, isFalse);
    });
  });
}
