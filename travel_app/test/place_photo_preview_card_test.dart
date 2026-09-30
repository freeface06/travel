/// @intent PlacePhotoPreviewCard 위젯, PlaceAllPhotosSheet 팝업 시트 및 TripItem.locationUrl 직렬화/역직렬화 검증 테스트
/// @agent Gemini/manager-develop
/// @branch feat/lazy-google-photos
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/ui/sheets/place_all_photos_sheet.dart';
import 'package:travel_app/ui/widgets/place_photo_preview_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TripItem locationUrl 직렬화 및 모델 테스트', () {
    test('locationUrl 기본값 빈 문자열 및 생성자 지정 검증', () {
      const itemDefault = TripItem(id: '1', day: 1, title: '도쿄 타워');
      expect(itemDefault.locationUrl, equals(''));

      const itemWithUrl = TripItem(
        id: '2',
        day: 1,
        title: '도쿄 타워',
        locationUrl: 'https://maps.app.goo.gl/sample123',
      );
      expect(itemWithUrl.locationUrl, equals('https://maps.app.goo.gl/sample123'));
    });

    test('toJson 및 fromJson에서 locationUrl 완벽 보존 검증', () {
      const original = TripItem(
        id: 'test-item-url',
        day: 2,
        title: '인천국제공항',
        category: 'AIRPORT',
        locationUrl: 'https://maps.app.goo.gl/incheon123',
        lat: 37.4602,
        lng: 126.4407,
      );

      final json = original.toJson();
      expect(json['locationUrl'], equals('https://maps.app.goo.gl/incheon123'));

      final restored = TripItem.fromJson(json);
      expect(restored.locationUrl, equals('https://maps.app.goo.gl/incheon123'));
      expect(restored.title, equals('인천국제공항'));
      expect(restored.lat, equals(37.4602));
      expect(restored.lng, equals(126.4407));
    });

    test('copyWith에서 locationUrl 변경 및 유지 검증', () {
      const original = TripItem(
        id: '10',
        day: 1,
        title: '루브르 박물관',
        locationUrl: 'https://maps.app.goo.gl/louvre',
      );

      final updated = original.copyWith(locationUrl: 'https://maps.app.goo.gl/louvre_new');
      expect(updated.locationUrl, equals('https://maps.app.goo.gl/louvre_new'));
      expect(updated.title, equals('루브르 박물관'));

      final unchanged = original.copyWith(title: '루브르 박물관 신관');
      expect(unchanged.locationUrl, equals('https://maps.app.goo.gl/louvre'));
      expect(unchanged.title, equals('루브르 박물관 신관'));
    });
  });

  group('PlacePhotoPreviewCard 위젯 렌더링 테스트', () {
    testWidgets('사진이 있고 showHeader=true 일 때 장소 헤더와 액션 버튼, 오버레이 카드가 렌더링된다', (tester) async {
      final samplePhotos = [
        'https://images.unsplash.com/photo-1503899036084-c55cdd92da26',
        'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlacePhotoPreviewCard(
                title: '인천국제공항',
                locationUrl: 'https://maps.app.goo.gl/incheon',
                lat: 37.4602,
                lng: 126.4407,
                personalPhotos: samplePhotos,
                showHeader: true,
                onDirections: () {},
                onFocusMap: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 헤더 및 액션 버튼 검증
      expect(find.text('인천국제공항'), findsOneWidget);
      expect(find.text('경로'), findsOneWidget);
      expect(find.text('지도에서 보기'), findsOneWidget);
      expect(find.text('사진 전체보기'), findsOneWidget);

      // 마지막 '사진 모두 보기 / 전체보기' 오버레이 카드 검증
      expect(find.text('사진 모두 보기'), findsOneWidget);
      expect(find.text('전체보기'), findsOneWidget);
    });

    testWidgets('showHeader=false 일 때 헤더 없이 사진 목록과 오버레이 카드만 컴팩트하게 렌더링된다', (tester) async {
      final samplePhotos = [
        'https://images.unsplash.com/photo-1503899036084-c55cdd92da26',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlacePhotoPreviewCard(
              title: '도쿄 타워',
              personalPhotos: samplePhotos,
              showHeader: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 헤더의 장소명 텍스트와 액션 버튼은 표시되지 않아야 함
      expect(find.text('경로'), findsNothing);
      expect(find.text('지도에서 보기'), findsNothing);

      // 오버레이 카드는 여전히 렌더링되어 전체보기를 지원해야 함
      expect(find.text('사진 모두 보기'), findsOneWidget);
      expect(find.text('전체보기'), findsOneWidget);
    });
  });

  group('PlaceAllPhotosSheet 팝업 시트 렌더링 테스트', () {
    testWidgets('PlaceAllPhotosSheet가 전달받은 사진과 장소명을 그리드로 정상 렌더링한다', (tester) async {
      final samplePhotos = [
        'https://images.unsplash.com/photo-1',
        'https://images.unsplash.com/photo-2',
        'https://images.unsplash.com/photo-3',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PlaceAllPhotosSheet.show(
                    context,
                    placeName: '인천국제공항',
                    initialPhotos: samplePhotos,
                    rating: 4.5,
                    userRatingsTotal: 33257,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );

      // 시트 열기 버튼 탭
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 시트 헤더 검증 (장소명과 사진 수만 깔끔하게 표시, 별점/리뷰 없음)
      expect(find.text('인천국제공항'), findsOneWidget);
      expect(find.text('사진 3장'), findsOneWidget);
      expect(find.text('4.5'), findsNothing);
      expect(find.text('리뷰 33,257개'), findsNothing);
    });
  });
}
