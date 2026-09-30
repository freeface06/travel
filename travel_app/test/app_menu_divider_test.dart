/// @intent AppMenuDivider 팝업 메뉴 인셋 디바이더 위젯 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/ui/widgets/app_menu_divider.dart';

void main() {
  Widget buildTestHost({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('AppMenuDivider 위젯 테스트', () {
    testWidgets('PopupMenuButton 내부에서 AppMenuDivider가 정상적으로 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(value: '1', child: Text('항목 1')),
              const AppMenuDivider(),
              const PopupMenuItem(value: '2', child: Text('항목 2')),
            ],
            child: const Text('메뉴 열기'),
          ),
        ),
      );

      // 메뉴 열기
      await tester.tap(find.text('메뉴 열기'));
      await tester.pumpAndSettle();

      // Divider 확인
      final dividerFinder = find.byType(Divider);
      expect(dividerFinder, findsOneWidget);

      final divider = tester.widget<Divider>(dividerFinder);
      expect(divider.color, const Color(0xFFF1F5F9));
      expect(divider.indent, 12.0);
      expect(divider.endIndent, 12.0);
      expect(divider.thickness, 0.75);

      const menuDivider = AppMenuDivider();
      expect(menuDivider.height, 1.0);
      expect(menuDivider.represents(null), isFalse);
    });
  });
}
