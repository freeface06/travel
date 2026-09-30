/// @intent AppDialog 모던 카드 팝업 컴포넌트의 confirm, prompt, alert, showCustom 위젯 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/ui/widgets/app_dialog.dart';

void main() {
  Widget buildTestHost({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('AppDialog.confirm 위젯 테스트', () {
    testWidgets('confirm 팝업 열기 및 확인 버튼 탭 시 true 반환 검증', (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AppDialog.confirm(
                  context,
                  title: '삭제 확인',
                  message: '정말 삭제하시겠습니까?',
                  confirmText: '삭제',
                  type: AppDialogType.danger,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      // 다이얼로그 열기
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // UI 요소 렌더링 확인
      expect(find.text('삭제 확인'), findsOneWidget);
      expect(find.text('정말 삭제하시겠습니까?'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);

      // 확인 버튼 탭
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('삭제 확인'), findsNothing);
    });

    testWidgets('confirm 팝업 취소 버튼 탭 시 false 반환 검증', (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AppDialog.confirm(
                  context,
                  title: '진행 확인',
                  message: '계속 진행하시겠습니까?',
                  cancelText: '돌아가기',
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('진행 확인'), findsOneWidget);

      // 취소 버튼 탭
      await tester.tap(find.text('돌아가기'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('진행 확인'), findsNothing);
    });
  });

  group('AppDialog.prompt 위젯 테스트', () {
    testWidgets('prompt 팝업 텍스트 입력 및 확인 시 입력값 반환 검증', (tester) async {
      String? result;

      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AppDialog.prompt(
                  context,
                  title: '새 계획',
                  message: '이름을 입력하세요',
                  initialValue: '기본 여행',
                  confirmText: '생성',
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('새 계획'), findsOneWidget);
      expect(find.text('기본 여행'), findsOneWidget);

      // 텍스트 수정 입력
      await tester.enterText(find.byType(TextFormField), '오사카 여행');
      await tester.pumpAndSettle();

      // 생성 버튼 탭
      await tester.tap(find.text('생성'));
      await tester.pumpAndSettle();

      expect(result, '오사카 여행');
      expect(find.text('새 계획'), findsNothing);
    });

    testWidgets('prompt 팝업 취소 시 null 반환 검증', (tester) async {
      String? result;

      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AppDialog.prompt(
                  context,
                  title: '입력 요청',
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 취소 탭
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('AppDialog.alert 및 showCustom 위젯 테스트', () {
    testWidgets('alert 팝업 정상 표시 및 확인 버튼으로 닫힘 검증', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppDialog.alert(
                  context,
                  title: '안내',
                  message: '작업이 완료되었습니다.',
                  type: AppDialogType.success,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('안내'), findsOneWidget);
      expect(find.text('작업이 완료되었습니다.'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('안내'), findsNothing);
    });

    testWidgets('showCustom 커스텀 위젯 다이얼로그 검증', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppDialog.showCustom(
                  context,
                  child: const Text('커스텀 위젯 내용'),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('커스텀 위젯 내용'), findsOneWidget);
    });
  });
}
