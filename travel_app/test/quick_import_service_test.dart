/// @intent 구글맵 원터치 장소 스크랩 시스템 단위 및 위젯 테스트
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_metadata.dart';
import 'package:travel_app/providers/trip_provider.dart';
import 'package:travel_app/services/quick_import_service.dart';
import 'package:travel_app/services/supabase_service.dart';
import 'package:travel_app/ui/sheets/quick_place_import_sheet.dart';

class MockSupabaseService extends SupabaseService {
  @override
  Future<List<Trip>> fetchTrips() async => [];

  @override
  Future<bool> syncTrip(Trip trip) async => true;

  @override
  Future<bool> deleteTrip(String tripId) async => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    QuickImportService.instance.clearHistory();
  });

  group('QuickImportService 구글맵 장소 링크 및 텍스트 감지 단위 테스트', () {
    test('다양한 구글맵 URL 및 공유 텍스트 패턴을 정확히 감지한다', () {
      // 1. 단축 URL
      expect(
        QuickImportService.isGoogleMapsContent('https://maps.app.goo.gl/w1234abcd'),
        isTrue,
      );
      expect(
        QuickImportService.isGoogleMapsContent('https://goo.gl/maps/x9876efgh'),
        isTrue,
      );

      // 2. 일반 구글맵 URL
      expect(
        QuickImportService.isGoogleMapsContent('https://www.google.com/maps/place/Tokyo+Tower'),
        isTrue,
      );
      expect(
        QuickImportService.isGoogleMapsContent('https://maps.google.com/?q=35.6585,139.7454'),
        isTrue,
      );

      // 3. 텍스트와 함께 공유된 복합 포맷
      const shareText = '''
도쿄 타워
4 Chome-2-8 Shibakoen, Minato City, Tokyo 105-0011 일본
https://maps.app.goo.gl/w1234abcd
''';
      expect(QuickImportService.isGoogleMapsContent(shareText), isTrue);

      // 4. 비구글맵 URL 및 일반 텍스트는 감지하지 않음
      expect(QuickImportService.isGoogleMapsContent('https://naver.com'), isFalse);
      expect(QuickImportService.isGoogleMapsContent('내일 도쿄 여행 출발!'), isFalse);
      expect(QuickImportService.isGoogleMapsContent(''), isFalse);
    });

    test('복합 공유 텍스트에서 구글맵 URL과 장소명 힌트를 분리 추출한다', () {
      const shareText = '''
도쿄 스카이트리
1 Chome-1-2 Oshiage, Sumida City, Tokyo 131-0045 일본
https://maps.app.goo.gl/skytree123
''';

      final url = QuickImportService.extractGoogleMapsUrl(shareText);
      expect(url, 'https://maps.app.goo.gl/skytree123');

      final nameHint = QuickImportService.extractPlaceNameHint(shareText);
      expect(nameHint, '도쿄 스카이트리');
    });

    test('onPlaceUrlDetected 스트림 이벤트 발행 및 중복/쿨다운 가드를 검증한다', () async {
      final service = QuickImportService.instance;
      service.clearHistory();

      final detectedUrls = <String>[];
      final sub = service.onPlaceUrlDetected.listen((url) {
        detectedUrls.add(url);
      });

      // 1. 첫 이벤트 발행
      const testUrl1 = 'https://maps.app.goo.gl/sample1';
      service.notifyDetectedUrl(testUrl1);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(detectedUrls.length, 1);
      expect(detectedUrls.first, testUrl1);

      // 2. 다른 URL 발행 시 정상 추가 수신
      const testUrl2 = 'https://maps.app.goo.gl/sample2';
      service.notifyDetectedUrl(testUrl2);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(detectedUrls.length, 2);
      expect(detectedUrls[1], testUrl2);

      await sub.cancel();
    });
  });

  group('QuickPlaceImportSheet 원터치 장소 등록 위젯 테스트', () {
    late TripProvider provider;

    setUp(() {
      provider = TripProvider(supabaseService: MockSupabaseService());
      provider.createTrip(
        metadata: const TripMetadata(
          id: 'quick-trip-test',
          title: '도쿄 테스트 여행',
          startDate: '2026-10-01',
          endDate: '2026-10-04',
        ),
      );
    });

    testWidgets('감지된 구글맵 링크로 바텀시트가 렌더링되고 일정에 즉시 추가된다', (WidgetTester tester) async {
      const rawInput = '''
신주쿠 교엔
11 Naitomachi, Shinjuku City, Tokyo 160-0014 일본
https://maps.app.goo.gl/shinjukuGyoen
''';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<TripProvider>.value(
            value: provider,
            child: const Scaffold(
              body: QuickPlaceImportSheet(
                rawInput: rawInput,
                initialDay: 2,
              ),
            ),
          ),
        ),
      );

      // 렌더링 대기
      await tester.pumpAndSettle();

      // 1. 상단 배지 노출 확인
      expect(find.text('구글맵에서 장소 감지됨'), findsOneWidget);

      // 2. 장소명 힌트 파싱 확인
      expect(find.text('신주쿠 교엔'), findsOneWidget);

      // 3. Day 선택 확인 (초기값 Day 2가 선택되어 있어야 함)
      expect(find.text('Day 2'), findsOneWidget);

      // 4. 카테고리 칩 선택 (맛집/식당 선택)
      final diningChip = find.text('맛집/식당');
      expect(diningChip, findsOneWidget);
      await tester.tap(diningChip);
      await tester.pumpAndSettle();

      // 5. [일정에 추가하기] 버튼 탭
      final addButton = find.widgetWithText(ElevatedButton, '일정에 추가하기');
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // 6. TripProvider에 아이템이 추가되었는지 확인
      final items = provider.currentTrip.items;
      expect(items.length, 1);
      final addedItem = items.first;
      expect(addedItem.title, '신주쿠 교엔');
      expect(addedItem.day, 2);
      expect(addedItem.category, 'DINING');
      expect(addedItem.locationUrl, 'https://maps.app.goo.gl/shinjukuGyoen');
    });
  });
}
