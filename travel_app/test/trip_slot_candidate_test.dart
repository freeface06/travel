/// @intent 일정 후보/대안 플랜(Plan A/B, 2-1/2-2) 슬롯 그룹핑, 스왑, 경비 격리, 자동 승격 및 직렬화 하위 호환성 검증 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-travel-app
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
import 'package:travel_app/services/expense_calculator.dart';
import 'package:travel_app/services/supabase_service.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TripItem 슬롯 후보 모델 및 직렬화 하위 호환성 검증', () {
    test('기본값 생성 시 slotGroupId는 빈 문자열, candidateLabel은 1, isSelected는 true여야 한다', () {
      const item = TripItem(
        id: 'item-1',
        day: 1,
        title: '도쿄 타워',
      );

      expect(item.slotGroupId, '');
      expect(item.candidateLabel, '1');
      expect(item.isSelected, isTrue);
      expect(item.effectiveSlotId, 'item-1');
    });

    test('slotGroupId가 지정된 경우 effectiveSlotId는 slotGroupId를 반환해야 한다', () {
      const item = TripItem(
        id: 'item-1',
        day: 1,
        title: '도쿄 타워',
        slotGroupId: 'slot-day1-1',
        candidateLabel: 'A',
      );

      expect(item.effectiveSlotId, 'slot-day1-1');
      expect(item.candidateLabel, 'A');
    });

    test('과거 레거시 JSON(slotGroupId, candidateLabel, isSelected 누락) 역직렬화 시 100% 하위 호환되어야 한다', () {
      final legacyJson = {
        'id': 'legacy-item-99',
        'day': 2,
        'title': '센소지 사원',
        'cost': 1500.0,
        'category': 'ATTRACTION',
      };

      final item = TripItem.fromJson(legacyJson);
      expect(item.id, 'legacy-item-99');
      expect(item.slotGroupId, '');
      expect(item.candidateLabel, '1');
      expect(item.isSelected, isTrue);
      expect(item.effectiveSlotId, 'legacy-item-99');
    });

    test('슬롯 후보 정보가 포함된 TripItem의 toJson/fromJson 왕복 직렬화가 정상 동작해야 한다', () {
      const original = TripItem(
        id: 'item-cand-1',
        day: 2,
        title: '오르세 미술관',
        slotGroupId: 'slot-paris-day2-seq1',
        candidateLabel: '2',
        isSelected: false,
      );

      final json = original.toJson();
      expect(json['slotGroupId'], 'slot-paris-day2-seq1');
      expect(json['candidateLabel'], '2');
      expect(json['isSelected'], isFalse);

      final restored = TripItem.fromJson(json);
      expect(restored.slotGroupId, original.slotGroupId);
      expect(restored.candidateLabel, original.candidateLabel);
      expect(restored.isSelected, original.isSelected);
      expect(restored.effectiveSlotId, original.effectiveSlotId);
    });
  });

  group('TripProvider 슬롯 후보 관리 로직 검증', () {
    late TripProvider provider;

    setUp(() async {
      provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();
      provider.clearCurrentTripItems();
    });

    test('addCandidateItem 호출 시 baseItem의 slotGroupId가 자동 생성되고 새 후보가 isSelected=false로 추가된다', () {
      const baseItem = TripItem(
        id: 'base-1',
        day: 1,
        title: '루브르 박물관 (Plan A)',
        cost: 30000.0,
      );
      provider.addItem(baseItem);

      const candidateItem = TripItem(
        id: 'cand-1',
        day: 1,
        title: '오르세 미술관 (Plan B)',
        cost: 20000.0,
      );
      final added = provider.addCandidateItem(
        baseItem: baseItem,
        candidateItem: candidateItem,
      );

      expect(added, isNotNull);
      expect(added!.isSelected, isFalse);

      final items = provider.currentTrip.items;
      expect(items.length, 2);

      // baseItem의 slotGroupId가 채워졌는지 확인
      final updatedBase = items.firstWhere((i) => i.id == 'base-1');
      expect(updatedBase.slotGroupId.isNotEmpty, isTrue);
      expect(updatedBase.isSelected, isTrue);

      // 새 후보가 동일한 slotGroupId를 가졌는지 확인
      expect(added.slotGroupId, updatedBase.slotGroupId);
      expect(added.effectiveSlotId, updatedBase.effectiveSlotId);

      // activeItemsForSelectedDay에는 isSelected == true인 baseItem만 포함되어야 함
      final activeItems = provider.activeItemsForSelectedDay;
      expect(activeItems.length, 1);
      expect(activeItems.first.id, 'base-1');
    });

    test('selectCandidate 호출 시 대상 아이템이 isSelected=true로, 기존 아이템이 isSelected=false로 스왑된다', () {
      const baseItem = TripItem(
        id: 'base-1',
        day: 1,
        title: '루브르 박물관 (Plan A)',
      );
      provider.addItem(baseItem);

      const candidateItem = TripItem(
        id: 'cand-1',
        day: 1,
        title: '오르세 미술관 (Plan B)',
      );
      provider.addCandidateItem(
        baseItem: baseItem,
        candidateItem: candidateItem,
      );

      // Plan B 선택
      provider.selectCandidate('cand-1');

      final items = provider.currentTrip.items;
      final updatedBase = items.firstWhere((i) => i.id == 'base-1');
      final updatedCand = items.firstWhere((i) => i.id == 'cand-1');

      expect(updatedBase.isSelected, isFalse);
      expect(updatedCand.isSelected, isTrue);

      // activeItemsForSelectedDay가 Plan B로 변경되었는지 확인
      final activeItems = provider.activeItemsForSelectedDay;
      expect(activeItems.length, 1);
      expect(activeItems.first.id, 'cand-1');
      expect(activeItems.first.title, '오르세 미술관 (Plan B)');
    });

    test('활성(isSelected=true) 후보가 삭제되면 동일 슬롯에 남은 후보 중 첫 번째가 자동으로 isSelected=true로 승격된다', () {
      const baseItem = TripItem(
        id: 'base-1',
        day: 1,
        title: '루브르 박물관 (Plan A)',
      );
      provider.addItem(baseItem);

      const candidateItem = TripItem(
        id: 'cand-1',
        day: 1,
        title: '오르세 미술관 (Plan B)',
      );
      provider.addCandidateItem(
        baseItem: baseItem,
        candidateItem: candidateItem,
      );

      // 활성 상태인 base-1 삭제
      provider.deleteItem('base-1');

      final remainingItems = provider.currentTrip.items;
      expect(remainingItems.length, 1);

      final promotedCandidate = remainingItems.first;
      expect(promotedCandidate.id, 'cand-1');
      expect(promotedCandidate.isSelected, isTrue); // 자동 승격 검증
    });
  });

  group('ExpenseCalculator 후보 플랜 비용 격리 검증', () {
    test('calculateExpenseSummary는 isSelected=true인 아이템의 비용만 집계하고 미선택 후보 비용은 제외한다', () {
      final items = [
        const TripItem(
          id: 'item-1',
          day: 1,
          title: '선택된 호텔',
          cost: 100000.0,
          currency: 'KRW',
          isSelected: true,
        ),
        const TripItem(
          id: 'item-2-candA',
          day: 1,
          title: '플랜 A: 고급 레스토랑 (선택됨)',
          cost: 50000.0,
          currency: 'KRW',
          slotGroupId: 'slot-dinner',
          isSelected: true,
        ),
        const TripItem(
          id: 'item-2-candB',
          day: 1,
          title: '플랜 B: 캐주얼 식당 (미선택)',
          cost: 20000.0,
          currency: 'KRW',
          slotGroupId: 'slot-dinner',
          isSelected: false, // 미선택 후보
        ),
      ];

      final summary = ExpenseCalculator.calculateExpenseSummary(
        items,
        ['참가자1'],
        baseCurrency: 'KRW',
      );

      // 플랜 A(50,000) + 호텔(100,000) = 150,000원만 집계되어야 함 (플랜 B 20,000원은 제외)
      expect(summary.totalInBase, 150000.0);
    });
  });

  group('TimelineTab 다중 후보 세그먼트 알약 스위처 및 확정 인터랙션 위젯 테스트', () {
    testWidgets('후보가 2개 이상인 슬롯은 2-1, 2-2 세그먼트 스위처가 렌더링되고, 탭 전환 및 확정 버튼 동작이 정상 수행된다', (tester) async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();
      provider.clearCurrentTripItems();

      const baseItem = TripItem(
        id: 'slot1-a',
        day: 1,
        title: '루브르 박물관',
        slotGroupId: 'slot-paris-1',
        candidateLabel: '1',
        isSelected: true,
      );
      provider.addItem(baseItem);

      const candidateItem = TripItem(
        id: 'slot1-b',
        day: 1,
        title: '오르세 미술관',
        slotGroupId: 'slot-paris-1',
        candidateLabel: '2',
        isSelected: false,
      );
      provider.addItem(candidateItem);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<TripProvider>.value(
            value: provider,
            child: const Scaffold(
              body: TimelineTab(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 세그먼트 알약 스위처가 표시되는지 확인
      expect(find.text('1-1: 루브르 박물관'), findsOneWidget);
      expect(find.text('1-2: 오르세 미술관'), findsOneWidget);
      expect(find.text('대안 추가'), findsOneWidget);

      // 현재 선택된 루브르 박물관이 메인 제목으로 표시되는지 확인
      expect(find.text('루브르 박물관'), findsWidgets);
      // 루브르는 이미 확정된 상태이므로 하단 확정 버튼은 보이지 않아야 함
      expect(find.text('이 플랜으로 확정 (Plan 1)'), findsNothing);

      // 1-2(오르세 미술관) 알약 탭하여 프리뷰 전환
      await tester.tap(find.text('1-2: 오르세 미술관'));
      await tester.pumpAndSettle();

      // 카드 내용이 오르세 미술관으로 전환되었는지 확인
      expect(find.text('오르세 미술관'), findsWidgets);

      // 미확정 상태이므로 '이 플랜으로 확정' 버튼이 노출되어야 함
      expect(find.text('이 플랜으로 확정 (Plan 2)'), findsOneWidget);

      // '이 플랜으로 확정' 버튼 탭
      await tester.tap(find.text('이 플랜으로 확정 (Plan 2)'));
      await tester.pumpAndSettle();

      // provider 상에서 오르세 미술관이 isSelected = true가 되었는지 검증
      final currentCand = provider.currentTrip.items.firstWhere((i) => i.id == 'slot1-b');
      expect(currentCand.isSelected, isTrue);

      final currentBase = provider.currentTrip.items.firstWhere((i) => i.id == 'slot1-a');
      expect(currentBase.isSelected, isFalse);
    });
  });
}
