/// @intent PhotoGalleryView 복수 사진 렌더링 및 가로 스와이프(_PhotoSwipeViewerDialog) 뷰어 위젯 테스트
/// @agent Gemini/manager-develop
/// @branch feat/photo-swipe-viewer
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/ui/widgets/photo_gallery_view.dart';

void main() {
  final testPhotos = [
    'https://example.com/photo1.jpg',
    'https://example.com/photo2.jpg',
    'https://example.com/photo3.jpg',
  ];

  Widget buildTestHost(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('PhotoGalleryView 렌더링 및 가로 스와이프 뷰어 테스트', () {
    testWidgets('복수 사진 목록이 가로 썸네일로 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          PhotoGalleryView(photos: testPhotos),
        ),
      );

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('사진 탭 시 가로 스와이프 뷰어가 열리고 인덱스 배지가 정상 표시된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PhotoGalleryView.showImageDialog(
                context,
                testPhotos[0],
                testPhotos,
              ),
              child: const Text('사진 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('사진 열기'));
      await tester.pumpAndSettle();

      // 인덱스 배지 확인
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);

      // 다음 사진 버튼(우측 화살표) 탭
      final nextBtn = find.byTooltip('다음 사진');
      expect(nextBtn, findsOneWidget);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // 인덱스가 2/3으로 변경되었는지 확인
      expect(find.text('2 / 3'), findsOneWidget);

      // 이전 사진 버튼(좌측 화살표) 탭
      final prevBtn = find.byTooltip('이전 사진');
      expect(prevBtn, findsOneWidget);
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();

      // 다시 1/3으로 복귀 확인
      expect(find.text('1 / 3'), findsOneWidget);

      // 닫기 버튼 탭
      final closeBtn = find.byTooltip('닫기');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // 뷰어가 닫혔는지 확인
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('가로 드래그 스와이프로 다음 사진으로 부드럽게 전환된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PhotoGalleryView.showImageDialog(
                context,
                testPhotos[0],
                testPhotos,
              ),
              child: const Text('사진 열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('사진 열기'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);

      // PageView를 왼쪽으로 스와이프 (다음 페이지로 이동)
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsOneWidget);
    });
  });
}
