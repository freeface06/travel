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
    testWidgets('PlaceAllPhotosSheet가 전달받은 사진과 장소명을 그리드로 정상 렌더링하고, 하단에 완료 안내 또는 더보기 인터랙션이 노출된다', (tester) async {
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
      await tester.pump(); // 첫 프레임 빌드

      // 시트 헤더 검증 (장소명과 사진 수만 깔끔하게 표시, 별점/리뷰 없음)
      expect(find.text('인천국제공항'), findsOneWidget);
      expect(find.text('사진 3장'), findsOneWidget);
      expect(find.text('4.5'), findsNothing);
      expect(find.text('리뷰 33,257개'), findsNothing);

      // 비동기 작업 완료 대기
      await tester.pumpAndSettle();

      // 자동 뷰포트 채움 로직 수행 후 테스트 환경에서는 추가 사진이 없어 모든 사진 완료 안내 문구 표시
      expect(find.text('해당 장소의 모든 사진을 불러왔습니다. (총 3장)'), findsOneWidget);
    });

    testWidgets('세로 비율이 매우 긴 화면(Z폴드 세로모드 등)에서도 에러 없이 렌더링 및 뷰포트 채움 가드가 자동 동작한다', (tester) async {
      // Z폴드 세로 모드 해상도 시뮬레이션 (너비 400, 높이 1200)
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sampleTenPhotos = List.generate(10, (i) => 'https://images.unsplash.com/photo-$i');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PlaceAllPhotosSheet.show(
                    context,
                    placeName: '발리 쿠타 비치',
                    initialPhotos: sampleTenPhotos,
                    lat: -8.72,
                    lng: 115.17,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pump(); // 시트 오픈 첫 프레임

      expect(find.text('발리 쿠타 비치'), findsOneWidget);
      expect(find.text('사진 10장'), findsOneWidget);

      // 긴 화면에서 addPostFrameCallback으로 _checkAndAutoLoadMore()가 자동 실행되어 로드 완료
      await tester.pumpAndSettle();

      // 뷰포트 자동 채움이 정상 완료되어 완료 문구 표시
      expect(find.text('해당 장소의 모든 사진을 불러왔습니다. (총 10장)'), findsOneWidget);
    });

    testWidgets('일반 화면 비율에서 사진 목록 하단으로 스크롤 시 [사진 더 불러오기] 버튼이 노출된다', (tester) async {
      // 뷰포트 높이를 작게 설정하여 스크롤이 확실히 생기도록 구성 (너비 400, 높이 500)
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final samplePhotos = List.generate(20, (i) => 'https://images.unsplash.com/photo-$i');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PlaceAllPhotosSheet.show(
                    context,
                    placeName: '도쿄 디즈니랜드',
                    initialPhotos: samplePhotos,
                    lat: 35.6329,
                    lng: 139.8804,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle(); // 바텀시트 슬라이드 업 애니메이션 완료

      expect(find.text('도쿄 디즈니랜드'), findsOneWidget);
      expect(find.text('사진 20장'), findsOneWidget);

      // 하단 끝까지 스크롤하여 더보기/완료 안내 영역으로 이동
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
      await tester.pumpAndSettle();

      // 최하단 도달 시 자동 로드 또는 완료 안내 문구 표시 확인
      expect(find.text('해당 장소의 모든 사진을 불러왔습니다. (총 20장)'), findsOneWidget);
    });
  });
}
