/// @intent LoginScreen 로그인 및 게스트 진입 화면 위젯 렌더링 및 인터랙션 테스트
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/providers/auth_provider.dart';
import 'package:travel_app/services/auth_service.dart';
import 'package:travel_app/ui/screens/login_screen.dart';
import 'package:travel_app/ui/screens/register_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService authService;
  late AuthProvider authProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = AuthService();
    authProvider = AuthProvider(authService: authService);
    await authProvider.init();
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  group('LoginScreen 위젯 렌더링 및 폼 인터랙션 테스트', () {
    testWidgets('브랜딩 로고, 타이틀, 입력 폼 및 액션 버튼들이 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // 브랜딩 및 타이틀 확인
      expect(find.text('MyTripLog'), findsOneWidget);
      expect(find.text('v2.0'), findsOneWidget);
      expect(find.text('스마트하고 안전한 올인원 여행 플래너'), findsOneWidget);

      // 폼 필드 확인
      expect(find.text('이메일 계정'), findsOneWidget);
      expect(find.text('비밀번호'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));

      // 버튼 확인
      expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
      expect(find.text('회원가입'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, '로그인 없이 둘러보기 (오프라인 모드)'),
        findsOneWidget,
      );
    });

    testWidgets('회원가입 텍스트 버튼 탭 시 RegisterScreen으로 이동한다', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final registerButton = find.text('회원가입');
      expect(registerButton, findsOneWidget);

      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('새 여행 계정 만들기'), findsOneWidget);
    });

    testWidgets('로그인 없이 둘러보기 버튼 탭 시 AuthProvider가 게스트 모드로 전환된다', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(authProvider.isGuestMode, isFalse);

      final guestButton =
          find.widgetWithText(OutlinedButton, '로그인 없이 둘러보기 (오프라인 모드)');
      await tester.ensureVisible(guestButton);
      await tester.tap(guestButton);
      await tester.pumpAndSettle();

      expect(authProvider.isGuestMode, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.displayName, '게스트 여행자');
    });

    testWidgets('유효하지 않은 이메일 및 짧은 비밀번호 입력 시 폼 유효성 에러 메시지가 표시된다',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // 빈 필드 상태에서 로그인 버튼 탭
      final loginButton = find.widgetWithText(ElevatedButton, '로그인');
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      expect(find.text('이메일을 입력해주세요.'), findsOneWidget);
      expect(find.text('비밀번호를 입력해주세요.'), findsOneWidget);

      // 형식에 맞지 않는 값 입력
      final emailField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;

      await tester.enterText(emailField, 'invalid-email');
      await tester.enterText(passwordField, '123');
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      expect(find.text('올바른 이메일 형식이 아닙니다.'), findsOneWidget);
      expect(find.text('비밀번호는 최소 6자 이상이어야 합니다.'), findsOneWidget);
    });
  });
}
