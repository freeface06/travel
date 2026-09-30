/// @intent ItemDetailSheet 일정 상세 보기 바텀 시트 위젯 및 타임라인 연동 테스트
/// @agent Gemini/manager-develop
/// @branch feat/item-detail-sheet
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/providers/trip_provider.dart';
import 'package:travel_app/services/supabase_service.dart';
import 'package:travel_app/ui/sheets/item_detail_sheet.dart';
import 'package:travel_app/ui/tabs/timeline_tab.dart';

class MockSupabaseService extends SupabaseService {
  @override
  Future<List<Trip>> fetchTrips() async => [];

  @override
  Future<bool> syncTrip(Trip trip) async => true;

  @override
  Future<bool> deleteTrip(String tripId) async => true;
}

void main() {
  late TripProvider mockProvider;

  const hotelItem = TripItem(
    id: 'item-hotel-1',
    day: 1,
    title: '신주쿠 그레이스리 호텔',
    category: 'HOTEL',
    lat: 35.6946,
    lng: 139.7022,
    address: '1-19-1 Kabukicho, Shinjuku, Tokyo',
    cost: 25000,
    currency: 'JPY',
    payer: '나',
    memo: '체크인 시 여권 제시 필수, 8층 로비',
    time: '15:00',
    checkOutTime: '11:00',
    voucherNo: 'VOUCHER-98765',
    passcode: '8294#',
    luggageStorage: '체크인 전 1층 컨시어지 보관 가능',
  );

  const flightItem = TripItem(
    id: 'item-flight-1',
    day: 1,
    title: '인천 -> 나리타 항공편',
    category: 'FLIGHT',
    flightType: 'DEPARTURE',
    airline: '대한항공',
    flightNo: 'KE703',
    airport: '인천국제공항 T2',
    terminalGate: '제2터미널 250번 게이트',
    seat: '28A, 28B',
    bookingRef: 'ABCDEF123',
    time: '09:30',
  );

  const transitItem = TripItem(
    id: 'item-transit-1',
    day: 1,
    title: '나리타 익스프레스(N-EX)',
    category: 'TRANSIT',
    transitMode: '열차/KTX',
    departureStation: '나리타공항역',
    arrivalStation: '신주쿠역',
    transitLine: 'JR 동일본 나리타선',
    ticketOrSeat: '5호차 12A',
    transferMemo: '신주쿠역 남쪽 출구 방면',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockProvider = TripProvider(supabaseService: MockSupabaseService());
    await mockProvider.init();

    mockProvider.clearCurrentTripItems();
    mockProvider.addItem(hotelItem);
    mockProvider.addItem(flightItem);
    mockProvider.addItem(transitItem);
  });

  Widget buildTestHost(Widget child) {
    return ChangeNotifierProvider<TripProvider>.value(
      value: mockProvider,
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('ItemDetailSheet 위젯 렌더링 및 기능 테스트', () {
    testWidgets('숙소(HOTEL) 카테고리 세부 정보 및 도어락 비밀번호가 정상 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ItemDetailSheet.show(context, item: hotelItem),
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 헤더 및 타이틀 확인
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('숙소'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('신주쿠 그레이스리 호텔'), findsOneWidget);

      // 위치 정보 및 액션 버튼 확인
      expect(find.text('1-19-1 Kabukicho, Shinjuku, Tokyo'), findsOneWidget);
      expect(find.text('지도에서 보기'), findsOneWidget);
      expect(find.text('구글맵 앱'), findsOneWidget);

      // 숙소 특화 필드 확인
      expect(find.text('체크아웃 시간'), findsOneWidget);
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('VOUCHER-98765'), findsOneWidget);
      expect(find.text('도어락 비밀번호'), findsOneWidget);
      expect(find.text('8294#'), findsOneWidget);
      expect(find.text('체크인 전 1층 컨시어지 보관 가능'), findsOneWidget);

      // 지출 및 정산 확인
      expect(find.text('지출 금액 및 결제자'), findsOneWidget);
      expect(find.text('25,000엔'), findsOneWidget);
      expect(find.text('나'), findsOneWidget);

      // 메모 확인
      expect(find.text('체크인 시 여권 제시 필수, 8층 로비'), findsOneWidget);

      // 하단 액션 버튼
      expect(find.text('일정 수정'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('항공편(FLIGHT) 특화 필드가 정확하게 렌더링된다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ItemDetailSheet.show(context, item: flightItem),
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('인천 -> 나리타 항공편'), findsOneWidget);
      expect(find.text('출발편'), findsOneWidget);
      expect(find.text('대한항공 KE703'), findsOneWidget);
      expect(find.text('인천국제공항 T2'), findsOneWidget);
      expect(find.text('제2터미널 250번 게이트'), findsOneWidget);
      expect(find.text('28A, 28B'), findsOneWidget);
      expect(find.text('ABCDEF123'), findsOneWidget);
    });

    testWidgets('지도에서 보기 버튼 탭 시 onFocusMap 콜백이 정상 호출된다', (tester) async {
      bool focusMapCalled = false;

      await tester.pumpWidget(
        buildTestHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ItemDetailSheet.show(
                context,
                item: hotelItem,
                onFocusMap: () {
                  focusMapCalled = true;
                },
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('지도에서 보기'));
      await tester.pumpAndSettle();

      expect(focusMapCalled, isTrue);
      // 시트가 닫혔는지 검증
      expect(find.text('신주쿠 그레이스리 호텔'), findsNothing);
    });
  });

  group('TimelineTab과 ItemDetailSheet 연동 테스트', () {
    testWidgets('타임라인 카드를 탭하면 상세 보기 시트가 열린다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          const TimelineTab(),
        ),
      );
      await tester.pumpAndSettle();

      // 첫 번째 일정 카드 확인
      expect(find.text('신주쿠 그레이스리 호텔'), findsOneWidget);

      // 카드 본문 탭
      await tester.tap(find.text('신주쿠 그레이스리 호텔'));
      await tester.pumpAndSettle();

      // 상세 시트가 열려서 도어락 비밀번호 등 세부 내역이 나타나는지 검증
      expect(find.text('도어락 비밀번호'), findsOneWidget);
      expect(find.text('8294#'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('타임라인 더보기(...) 메뉴의 상세보기 항목을 탭하면 상세 보기 시트가 열린다', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          const TimelineTab(),
        ),
      );
      await tester.pumpAndSettle();

      // 첫 번째 더보기 버튼 찾기
      final moreButtons = find.byIcon(Icons.more_horiz);
      expect(moreButtons, findsWidgets);

      await tester.tap(moreButtons.first);
      await tester.pumpAndSettle();

      // 팝업 메뉴에 '상세보기' 항목이 존재하는지 확인
      expect(find.text('상세보기'), findsOneWidget);
      expect(find.text('수정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);

      // '상세보기' 탭
      await tester.tap(find.text('상세보기'));
      await tester.pumpAndSettle();

      // 상세 시트가 열렸는지 확인
      expect(find.text('도어락 비밀번호'), findsOneWidget);
      expect(find.text('8294#'), findsOneWidget);
    });
  });
}
