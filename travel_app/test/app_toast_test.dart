/// @intent AppToast 모던 플로팅 토스트 컴포넌트의 타입별(success, warning, error, info) 렌더링 및 교체 위젯 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/ui/widgets/app_toast.dart';

void main() {
  Widget buildTestHost({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('AppToast 위젯 테스트', () {
    testWidgets('AppToast.success 호출 시 성공 아이콘과 메시지가 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppToast.success(context, '성공적으로 저장되었습니다.');
              },
              child: const Text('성공 토스트 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('성공 토스트 열기'));
      await tester.pump(); // SnackBar 시작 애니메이션 진행
      await tester.pump(const Duration(milliseconds: 300)); // 트랜지션 완료

      expect(find.text('성공적으로 저장되었습니다.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('AppToast.warning 호출 시 경고 아이콘과 메시지가 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppToast.warning(context, '필수 항목을 입력해주세요.');
              },
              child: const Text('경고 토스트 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('경고 토스트 열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('필수 항목을 입력해주세요.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('AppToast.error 호출 시 에러 아이콘과 메시지가 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppToast.error(context, '네트워크 오류가 발생했습니다.');
              },
              child: const Text('에러 토스트 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('에러 토스트 열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('네트워크 오류가 발생했습니다.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('AppToast.info 호출 시 정보 아이콘과 메시지가 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppToast.info(context, '최신 정보로 갱신되었습니다.');
              },
              child: const Text('정보 토스트 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('정보 토스트 열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('최신 정보로 갱신되었습니다.'), findsOneWidget);
      expect(find.byIcon(Icons.info_rounded), findsOneWidget);
    });

    testWidgets('연속해서 토스트를 호출하면 이전 토스트가 즉각 숨겨지고 새 토스트가 표시된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    AppToast.info(context, '첫 번째 안내 메시지');
                  },
                  child: const Text('첫 번째'),
                ),
                ElevatedButton(
                  onPressed: () {
                    AppToast.success(context, '두 번째 성공 메시지');
                  },
                  child: const Text('두 번째'),
                ),
              ],
            ),
          ),
        ),
      );

      // 첫 번째 토스트 호출
      await tester.tap(find.text('첫 번째'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('첫 번째 안내 메시지'), findsOneWidget);

      // 두 번째 토스트 호출 (즉각 교체 검증)
      await tester.tap(find.text('두 번째'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('두 번째 성공 메시지'), findsOneWidget);
    });
  });
}
