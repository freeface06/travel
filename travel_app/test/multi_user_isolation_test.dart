/// @intent 다중 사용자 계정별 여행 데이터 완벽 격리 및 게스트 마이그레이션 검증 테스트
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/models/trip_metadata.dart';
import 'package:travel_app/providers/trip_provider.dart';
import 'package:travel_app/services/cloud_sync_service.dart';
import 'package:travel_app/services/storage_service.dart';
import 'package:travel_app/services/supabase_service.dart';

class MockSupabaseService extends SupabaseService {
  MockSupabaseService() : super(url: 'https://mock.supabase.co', anonKey: 'mock-key');

  @override
  Future<List<Trip>> fetchTrips() async => [];

  @override
  Future<bool> syncTrip(Trip trip) async => true;

  @override
  Future<bool> deleteTrip(String tripId) async => true;
}

class MockCloudSyncService extends CloudSyncService {
  final Map<String, List<Trip>> _remoteStore = {};

  MockCloudSyncService({super.supabaseService});

  @override
  bool get isCloudAvailable => true;

  @override
  Future<List<Trip>> fetchUserTrips(String userId) async {
    return _remoteStore[userId] ?? [];
  }

  @override
  Future<bool> syncTripToCloud(Trip trip, String userId) async {
    final list = _remoteStore.putIfAbsent(userId, () => []);
    list.removeWhere((t) => t.metadata.id == trip.metadata.id);
    list.add(trip);
    return true;
  }

  @override
  Future<bool> deleteTripFromCloud(String tripId, String userId) async {
    final list = _remoteStore[userId];
    if (list != null) {
      list.removeWhere((t) => t.metadata.id == tripId);
    }
    return true;
  }

  @override
  Future<int> migrateLocalTripsToCloud(List<Trip> localTrips, String userId) async {
    for (final trip in localTrips) {
      await syncTripToCloud(trip, userId);
    }
    return localTrips.length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Tenant 계정별 여행 데이터 격리 및 마이그레이션 단위 테스트', () {
    late StorageService storageService;
    late MockSupabaseService mockSupabase;
    late MockCloudSyncService mockCloudSync;
    late TripProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storageService = StorageService();
      mockSupabase = MockSupabaseService();
      mockCloudSync = MockCloudSyncService(supabaseService: mockSupabase);

      provider = TripProvider(
        storageService: storageService,
        supabaseService: mockSupabase,
        cloudSyncService: mockCloudSync,
      );
      await provider.init();
    });

    test('StorageService 계정별 격리 키 생성 및 레거시 데이터 하위 호환 검증', () async {
      expect(StorageService.getTripsKey(null), 'guest_trips_data_v2');
      expect(StorageService.getTripsKey('guest'), 'guest_trips_data_v2');
      expect(StorageService.getTripsKey('user_alpha'), 'user_user_alpha_trips_data_v2');

      expect(StorageService.getCurrentTripIdKey(null), 'current_trip_id_guest');
      expect(StorageService.getCurrentTripIdKey('user_alpha'), 'current_trip_id_user_alpha');

      // 레거시 1.0.0 데이터 주입
      final prefs = await SharedPreferences.getInstance();
      final legacyPayload = {
        'trips': [
          {
            'metadata': {
              'id': 'legacy-trip-01',
              'title': '과거 1.0 레거시 여행',
              'startDate': '2026-05-01',
              'endDate': '2026-05-04',
              'baseCurrency': 'KRW',
            },
            'items': [],
          }
        ],
        'currentTripId': 'legacy-trip-01',
      };
      await prefs.setString(StorageService.legacyStorageKeyV2, jsonEncode(legacyPayload));

      // 게스트로 로드 시 레거시 여행이 안전하게 로드되어야 함
      final loaded = await storageService.loadTrips(userId: null);
      expect(loaded.trips.any((t) => t.metadata.id == 'legacy-trip-01'), isTrue);
      expect(loaded.currentTripId, 'legacy-trip-01');
    });

    test('User A와 User B 간의 여행 데이터가 상호 침범하지 않고 완벽히 격리된다', () async {
      // 1. User A 로그인 및 일정 등록
      await provider.bindUser('user-a');
      expect(provider.currentUserId, 'user-a');

      provider.createTrip(
        metadata: const TripMetadata(
          id: 'trip-a-paris',
          title: 'User A의 파리 여행',
        ),
      );
      provider.addItem(const TripItem(
        id: 'item-a-1',
        day: 1,
        title: '에펠탑 관람',
      ));
      expect(provider.trips.any((t) => t.metadata.id == 'trip-a-paris'), isTrue);

      // 2. User B 로그인 및 상태 확인
      await provider.bindUser('user-b');
      expect(provider.currentUserId, 'user-b');

      // User A의 데이터가 User B에게 보이지 않아야 함
      expect(provider.trips.any((t) => t.metadata.id == 'trip-a-paris'), isFalse);

      // User B만의 새 여행 등록
      provider.createTrip(
        metadata: const TripMetadata(
          id: 'trip-b-tokyo',
          title: 'User B의 도쿄 힐링',
        ),
      );
      expect(provider.trips.any((t) => t.metadata.id == 'trip-b-tokyo'), isTrue);

      // 3. User A로 다시 전환
      await provider.bindUser('user-a');
      expect(provider.trips.any((t) => t.metadata.id == 'trip-a-paris'), isTrue);
      expect(provider.trips.any((t) => t.metadata.id == 'trip-b-tokyo'), isFalse);
    });

    test('로그아웃(unbindUser) 시 메모리에서 이전 사용자 데이터가 완전 정화되어 게스트에게 노출되지 않는다', () async {
      await provider.bindUser('user-secret');
      provider.createTrip(
        metadata: const TripMetadata(
          id: 'trip-classified',
          title: '기밀 비즈니스 출장',
        ),
      );
      expect(provider.trips.any((t) => t.metadata.id == 'trip-classified'), isTrue);

      // 로그아웃 수행
      await provider.unbindUser();

      expect(provider.currentUserId, isNull);
      // 게스트 상태에서는 기밀 일정이 절대 노출되지 않아야 함
      expect(provider.trips.any((t) => t.metadata.id == 'trip-classified'), isFalse);
    });

    test('게스트 모드에서 작성된 일정이 신규 로그인 계정으로 안전하게 마이그레이션된다', () async {
      // 1. 게스트 상태에서 일정 작성
      await provider.bindUser(null);
      provider.addItem(const TripItem(
        id: 'guest-item-1',
        day: 1,
        title: '게스트가 찾은 오사카 라멘 맛집',
      ));

      // 마이그레이션 대상 검사
      final hasTrips = await provider.hasGuestTripsToMigrate();
      expect(hasTrips, isTrue);

      // 2. 신규 사용자 가입 및 바인딩
      await provider.bindUser('newbie-user');

      // 3. 마이그레이션 실행
      final migratedCount = await provider.migrateGuestTripsToUser();
      expect(migratedCount, greaterThan(0));

      // 4. 새 계정의 여행 목록에 게스트 일정이 병합되었는지 확인
      final currentTripItems = provider.currentTrip.items;
      expect(currentTripItems.any((i) => i.id == 'guest-item-1'), isTrue);

      // 5. 게스트 저장소는 비워져야 함
      final hasTripsAfter = await provider.hasGuestTripsToMigrate();
      expect(hasTripsAfter, isFalse);
    });
  });
}
