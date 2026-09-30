/// @intent 다중 사용자 여행 공유, 초대 코드 발급/참여 및 역할별(Owner/Editor/Viewer) 권한 제어 검증 테스트
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/models/trip_member.dart';
import 'package:travel_app/models/trip_metadata.dart';
import 'package:travel_app/providers/trip_provider.dart';
import 'package:travel_app/services/cloud_sync_service.dart';
import 'package:travel_app/services/storage_service.dart';
import 'package:travel_app/services/supabase_service.dart';
import 'package:travel_app/services/trip_sharing_service.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TripSharingService 및 TripProvider 여행 공유 단위 테스트', () {
    late StorageService storageService;
    late MockSupabaseService mockSupabase;
    late MockCloudSyncService mockCloudSync;
    late TripSharingService sharingService;
    late TripProvider providerA;
    late TripProvider providerB;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      TripSharingService.clearCache();

      storageService = StorageService();
      mockSupabase = MockSupabaseService();
      mockCloudSync = MockCloudSyncService(supabaseService: mockSupabase);
      sharingService = TripSharingService(
        supabaseService: mockSupabase,
        cloudSyncService: mockCloudSync,
      );

      // User A의 Provider
      providerA = TripProvider(
        storageService: storageService,
        supabaseService: mockSupabase,
        cloudSyncService: mockCloudSync,
        tripSharingService: sharingService,
      );
      await providerA.bindUser('user-a');

      // User B의 Provider
      providerB = TripProvider(
        storageService: storageService,
        supabaseService: mockSupabase,
        cloudSyncService: mockCloudSync,
        tripSharingService: sharingService,
      );
      await providerB.bindUser('user-b');
    });

    test('초대 코드 생성 및 정규화(Normalization) 정합성 검증', () {
      final code1 = TripSharingService.generateCode();
      expect(code1.length, 6);
      expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(code1), isTrue);

      // TRIP- 접두사 및 소문자 정규화 확인
      expect(TripSharingService.normalizeCode('trip-ab34cd'), 'AB34CD');
      expect(TripSharingService.normalizeCode('TRIP-XY89ZK'), 'XY89ZK');
      expect(TripSharingService.normalizeCode('qwerty'), 'QWERTY');
    });

    test('TripMetadata 권한(Role) 판정 및 canUserEdit 로직 검증', () {
      const meta = TripMetadata(
        id: 'trip-shared-1',
        title: '함께 떠나는 발리 여행',
        ownerId: 'user-a',
        ownerName: '호스트앨리스',
        inviteCode: 'BALI99',
        members: [
          TripMember(
            userId: 'user-b',
            email: 'bob@test.com',
            displayName: '밥',
            role: 'editor',
            joinedAt: '2026-09-30T00:00:00Z',
          ),
          TripMember(
            userId: 'user-c',
            email: 'charlie@test.com',
            displayName: '찰리',
            role: 'viewer',
            joinedAt: '2026-09-30T00:00:00Z',
          ),
        ],
      );

      // 소유자 권한 확인
      expect(meta.currentUserRole('user-a'), 'owner');
      expect(meta.canUserEdit('user-a'), isTrue);

      // 편집자 권한 확인
      expect(meta.currentUserRole('user-b'), 'editor');
      expect(meta.canUserEdit('user-b'), isTrue);

      // 뷰어 권한 확인
      expect(meta.currentUserRole('user-c'), 'viewer');
      expect(meta.canUserEdit('user-c'), isFalse);

      // 미등록 외부인 확인 (기본 viewer)
      expect(meta.currentUserRole('user-outsider'), 'viewer');
      expect(meta.canUserEdit('user-outsider'), isFalse);

      // 공유 상태 확인
      expect(meta.isShared, isTrue);
    });

    test('User A가 여행을 생성하고 발급한 초대 코드로 User B가 정상 참여한다', () async {
      // 1. User A가 여행 생성 및 초대 코드 발급
      final tripA = providerA.createTrip(
        metadata: const TripMetadata(
          id: 'trip-paris-shared',
          title: '파리 감성 여행 (공유용)',
        ),
      );
      providerA.addItem(const TripItem(
        id: 'item-louvre',
        day: 1,
        title: '루브르 박물관 관람',
      ));

      final inviteCode = await providerA.getOrGenerateInviteCode(
        tripA.metadata.id,
        ownerName: '앨리스',
      );
      expect(inviteCode.isNotEmpty, isTrue);
      expect(providerA.currentTrip.metadata.inviteCode, inviteCode);
      expect(providerA.currentTrip.metadata.ownerId, 'user-a');

      // 2. User B가 초대 코드로 참여 시도
      final joinSuccess = await providerB.joinTripByInviteCode(
        inviteCode,
        userEmail: 'bob@mytriplog.com',
        userDisplayName: '밥',
      );
      expect(joinSuccess, isTrue);

      // 3. User B의 현재 여행으로 자동 전환되었는지 확인
      expect(providerB.currentTripId, 'trip-paris-shared');
      expect(providerB.currentTrip.metadata.title, '파리 감성 여행 (공유용)');
      expect(providerB.currentTrip.items.any((i) => i.id == 'item-louvre'), isTrue);

      // User B의 멤버 역할(editor) 및 권한 확인
      expect(providerB.currentTripRole, 'editor');
      expect(providerB.canEditCurrentTrip, isTrue);
      expect(providerB.isCurrentTripShared, isTrue);

      // 4. User A의 여행 메타데이터 확인 및 캐시 조회를 통한 User B 멤버 등록 확인
      final tripInA = providerA.trips.firstWhere((t) => t.metadata.id == 'trip-paris-shared');
      expect(tripInA.metadata.inviteCode, inviteCode);

      final latestSharedTrip = await providerA.previewTripByInviteCode(inviteCode);
      expect(latestSharedTrip, isNotNull);
      expect(latestSharedTrip!.metadata.members.any((m) => m.userId == 'user-b'), isTrue);
    });

    test('소유자(User A)가 참여자(User B)의 권한을 뷰어(Viewer)로 변경 시 편집 권한이 제한된다', () async {
      // 1. User A 여행 및 초대
      final trip = providerA.createTrip(
        metadata: const TripMetadata(
          id: 'trip-role-test',
          title: '권한 변경 테스트 여행',
        ),
      );
      final code = await providerA.getOrGenerateInviteCode(trip.metadata.id, ownerName: '앨리스');

      // 2. User B 참여
      await providerB.joinTripByInviteCode(code, userEmail: 'bob@test.com', userDisplayName: '밥');
      expect(providerB.currentTripRole, 'editor');
      expect(providerB.canEditCurrentTrip, isTrue);

      // 3. User A가 User B를 'viewer'로 권한 하향
      final roleChanged = await providerA.updateMemberRole('user-b', 'viewer');
      expect(roleChanged, isTrue);

      // 4. User B의 권한이 viewer로 변경되어 canEditCurrentTrip이 false가 됨
      final updatedTrip = await providerB.previewTripByInviteCode(code);
      expect(updatedTrip, isNotNull);
      expect(updatedTrip!.metadata.currentUserRole('user-b'), 'viewer');
      expect(updatedTrip.metadata.canUserEdit('user-b'), isFalse);
    });
  });
}
