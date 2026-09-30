/// @intent TripProvider 상태 관리자의 CRUD, 다중 여행 계획 전환/복제/삭제, 일정 비우기 및 Mock Supabase 동기화 단위 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/models/trip_metadata.dart';
import 'package:travel_app/providers/trip_provider.dart';
import 'package:travel_app/services/supabase_service.dart';

class MockSupabaseService extends SupabaseService {
  List<Trip> mockTrips;

  MockSupabaseService({this.mockTrips = const []});

  @override
  Future<List<Trip>> fetchTrips() async => List<Trip>.from(mockTrips);

  @override
  Future<bool> syncTrip(Trip trip) async => true;

  @override
  Future<bool> deleteTrip(String tripId) async => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TripProvider - CRUD 및 필터링 테스트', () {
    test('일정 아이템 추가(addItem) 및 일차 필터링 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      expect(provider.currentTrip.items, isEmpty);

      // Day 1 아이템 추가
      provider.setSelectedDay(1);
      final item1 = provider.addItem(const TripItem(id: 'i1', day: 1, title: '도쿄 도착', time: '10:00'));

      // Day 2 아이템 추가
      provider.setSelectedDay(2);
      final item2 = provider.addItem(const TripItem(id: 'i2', day: 2, title: '디즈니랜드', time: '09:00'));
      expect(item2.id, isNotEmpty);

      expect(provider.currentTrip.items.length, 2);

      // Day 1 선택 시 1개만 조회
      provider.setSelectedDay(1);
      expect(provider.itemsForSelectedDay.length, 1);
      expect(provider.itemsForSelectedDay.first.id, item1.id);

      // 'all' 선택 시 전체 2개 조회
      provider.setSelectedDay('all');
      expect(provider.itemsForSelectedDay.length, 2);

      // 'all' 상태에서 아이템 추가 시 1일차 안전 배정 검증
      final item3 = provider.addItem(const TripItem(id: 'i3', day: 0, title: '자유 일정'));
      expect(item3.day, 1);
    });

    test('일정 아이템 수정(updateItem) 및 삭제(deleteItem) 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      provider.addItem(const TripItem(id: 'item-edit', day: 1, title: '기존 일정', cost: 1000.0));
      expect(provider.currentTrip.items.first.title, '기존 일정');

      // 수정
      provider.updateItem(
        'item-edit',
        provider.currentTrip.items.first.copyWith(title: '수정된 일정', cost: 2000.0),
      );
      expect(provider.currentTrip.items.first.title, '수정된 일정');
      expect(provider.currentTrip.items.first.cost, 2000.0);

      // 삭제
      final deleteSuccess = provider.deleteItem('item-edit');
      expect(deleteSuccess, isTrue);
      expect(provider.currentTrip.items, isEmpty);
    });

    test('일정 아이템 사진(photos) 수정 및 삭제 시 상태 반영 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      // 사진 2장이 포함된 아이템 추가
      provider.addItem(const TripItem(
        id: 'photo-test-item',
        day: 1,
        title: '포토 스팟',
        photos: ['https://cdn.supabase.co/p1.jpg', 'https://cdn.supabase.co/p2.jpg'],
      ));
      expect(provider.currentTrip.items.first.photos.length, 2);

      // 사진 1장 삭제 수정
      provider.updateItem(
        'photo-test-item',
        provider.currentTrip.items.first.copyWith(
          photos: ['https://cdn.supabase.co/p1.jpg'],
        ),
      );
      expect(provider.currentTrip.items.first.photos.length, 1);
      expect(provider.currentTrip.items.first.photos.first, 'https://cdn.supabase.co/p1.jpg');

      // 아이템 삭제
      final deleted = provider.deleteItem('photo-test-item');
      expect(deleted, isTrue);
      expect(provider.currentTrip.items, isEmpty);
    });

    test('현재 일정 전체 비우기(clearCurrentTripItems) 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      provider.addItem(const TripItem(id: 'c1', day: 1, title: '일정 1'));
      provider.addItem(const TripItem(id: 'c2', day: 2, title: '일정 2'));
      expect(provider.currentTrip.items.length, 2);

      provider.clearCurrentTripItems();
      expect(provider.currentTrip.items, isEmpty);
    });
  });

  group('TripProvider - 다중 여행 계획 관리 (Multi-Trip) 테스트', () {
    test('새 계획 생성(createTrip) 및 활성 전환(switchTrip) 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      expect(provider.trips.length, 1);

      // 새 여행 생성
      final newTrip = provider.createTrip(
        metadata: const TripMetadata(
          id: 'trip-japan-2026',
          title: '오사카 벚꽃 여행',
        ),
      );

      expect(provider.trips.length, 2);
      expect(provider.currentTripId, newTrip.metadata.id);

      // 이전 여행으로 전환
      provider.switchTrip('trip-my-first-trip');
      expect(provider.currentTrip.metadata.title, '나의 여행 계획');
    });

    test('여행 계획 복제(duplicateTrip) 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      provider.addItem(const TripItem(id: 'orig-1', day: 1, title: '첫 방문지'));
      final duplicated = provider.duplicateTrip(provider.currentTripId);

      expect(duplicated, isNotNull);
      expect(duplicated!.metadata.title, contains('(사본)'));
      expect(duplicated.items.length, 1);
      expect(duplicated.items.first.title, '첫 방문지');
      expect(duplicated.items.first.id, isNot('orig-1')); // 아이디 재발급
    });

    test('여행 계획 삭제(deleteTrip) 및 최소 1개 방어 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      // 1개만 있을 때는 삭제 불가
      expect(provider.trips.length, 1);
      final resultFail = provider.deleteTrip(provider.currentTripId);
      expect(resultFail, isFalse);

      // 2개 생성 후 삭제
      final tripB = provider.createTrip(
        metadata: const TripMetadata(id: 'trip-b', title: '계획 B'),
      );
      expect(provider.trips.length, 2);

      final resultSuccess = provider.deleteTrip(tripB.metadata.id);
      expect(resultSuccess, isTrue);
      expect(provider.trips.length, 1);
    });

    test('Supabase 클라우드 동기화(syncFromCloud) 데이터 병합 검증', () async {
      final mockCloudTrip = Trip(
        metadata: const TripMetadata(id: 'cloud-trip-1', title: '발리 여행 2'),
        items: const [
          TripItem(id: 'ci-1', day: 1, title: '우붓 사원', photos: ['https://example.com/photo.jpg']),
        ],
      );

      final provider = TripProvider(
        supabaseService: MockSupabaseService(mockTrips: [mockCloudTrip]),
      );
      await provider.init();

      expect(provider.trips.any((t) => t.metadata.id == 'cloud-trip-1'), isTrue);
      final syncedTrip = provider.trips.firstWhere((t) => t.metadata.id == 'cloud-trip-1');
      expect(syncedTrip.items.first.photos, contains('https://example.com/photo.jpg'));
    });

    test('신규 일정 추가 시 해당 일차의 최하단에 삽입되는지 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      // Day 1 아이템 2개 추가
      provider.addItem(const TripItem(id: 'd1-1', day: 1, title: '일정 1', time: '10:00'));
      provider.addItem(const TripItem(id: 'd1-2', day: 1, title: '일정 2', time: '12:00'));

      // Day 2 아이템 추가
      provider.addItem(const TripItem(id: 'd2-1', day: 2, title: '일정 3'));

      // 시간 없는 신규 아이템을 Day 1에 추가 -> Day 1의 최하단(일정 2 뒤)에 삽입되어야 함
      final newD1 = provider.addItem(const TripItem(id: 'd1-3', day: 1, title: '신규 일정'));

      provider.setSelectedDay(1);
      final day1Items = provider.itemsForSelectedDay;
      expect(day1Items.length, 3);
      expect(day1Items[0].id, 'd1-1');
      expect(day1Items[1].id, 'd1-2');
      expect(day1Items[2].id, newD1.id); // 최상단이 아닌 최하단에 위치
    });

    test('일정 순서 변경(reorderItems) 검증', () async {
      final provider = TripProvider(supabaseService: MockSupabaseService());
      await provider.init();

      provider.addItem(const TripItem(id: 'item-a', day: 1, title: 'A'));
      provider.addItem(const TripItem(id: 'item-b', day: 1, title: 'B'));
      provider.addItem(const TripItem(id: 'item-c', day: 1, title: 'C'));

      provider.setSelectedDay(1);
      expect(provider.itemsForSelectedDay.map((i) => i.id).toList(), ['item-a', 'item-b', 'item-c']);

      // A(0)를 C 뒤(2)로 이동 -> [B, C, A]
      provider.reorderItems(0, 2);
      expect(provider.itemsForSelectedDay.map((i) => i.id).toList(), ['item-b', 'item-c', 'item-a']);

      // C(1)를 맨 앞(0)으로 이동 -> [C, B, A]
      provider.reorderItems(1, 0);
      expect(provider.itemsForSelectedDay.map((i) => i.id).toList(), ['item-c', 'item-b', 'item-a']);
    });
  });
}
