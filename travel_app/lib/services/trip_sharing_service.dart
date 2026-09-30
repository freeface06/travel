/// @intent 여행 초대 코드 생성, 초대 코드를 통한 동행자 참여 및 참여 멤버 권한 관리 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';
import '../models/trip_member.dart';
import 'cloud_sync_service.dart';
import 'supabase_service.dart';

class TripSharingService {
  final SupabaseService _supabaseService;
  final CloudSyncService _cloudSyncService;

  // 로컬/테스트 환경 및 캐시용 메모리 맵: inviteCode -> tripId
  static final Map<String, String> _inviteCodeToTripId = {};
  static final Map<String, Trip> _sharedTripsCache = {};

  TripSharingService({
    SupabaseService? supabaseService,
    CloudSyncService? cloudSyncService,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _cloudSyncService = cloudSyncService ?? CloudSyncService();

  SupabaseService get supabaseService => _supabaseService;
  CloudSyncService get cloudSyncService => _cloudSyncService;

  SupabaseClient? get _client => SupabaseService.client;

  /// 6자리 읽기 쉬운 초대 코드 생성 (I, O, 1, 0 등 헷갈리는 문자 제외)
  static String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < 6; i++) {
      buffer.write(chars[rand.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  /// 코드 정규화 ('TRIP-ABC123' -> 'ABC123', 대문자 트림)
  static String normalizeCode(String code) {
    String clean = code.trim().toUpperCase();
    if (clean.startsWith('TRIP-')) {
      clean = clean.substring('TRIP-'.length).trim();
    }
    return clean;
  }

  /// 여행에 대한 초대 코드 발급 및 등록
  Future<String> generateInviteCode(Trip trip, {String? ownerId, String? ownerName}) async {
    // 이미 발급된 초대 코드가 있으면 유지
    if (trip.metadata.inviteCode.isNotEmpty) {
      final existingCode = normalizeCode(trip.metadata.inviteCode);
      _inviteCodeToTripId[existingCode] = trip.metadata.id;
      _sharedTripsCache[existingCode] = trip;
      return existingCode;
    }

    final newCode = generateCode();
    _inviteCodeToTripId[newCode] = trip.metadata.id;

    // 메타데이터에 코드와 소유자 정보 반영
    final updatedMeta = trip.metadata.copyWith(
      inviteCode: newCode,
      ownerId: trip.metadata.ownerId.isNotEmpty ? trip.metadata.ownerId : (ownerId ?? ''),
      ownerName: trip.metadata.ownerName.isNotEmpty ? trip.metadata.ownerName : (ownerName ?? '호스트 여행자'),
    );
    final updatedTrip = trip.copyWith(metadata: updatedMeta);
    _sharedTripsCache[newCode] = updatedTrip;

    // 클라우드가 연결되어 있으면 업데이트
    if (_cloudSyncService.isCloudAvailable && ownerId != null && ownerId.isNotEmpty) {
      await _cloudSyncService.syncTripToCloud(updatedTrip, ownerId);
    }

    return newCode;
  }

  /// 초대 코드로 대상 여행 조회
  Future<Trip?> getTripByInviteCode(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.isEmpty || code.length < 5) return null;

    // 1. 메모리/로컬 캐시 확인
    if (_sharedTripsCache.containsKey(code)) {
      return _sharedTripsCache[code];
    }

    // 2. Supabase 클라우드 조회
    final client = _client;
    if (client != null && SupabaseService.isInitialized) {
      try {
        final response = await client
            .from('trips')
            .select('*')
            .filter('data->metadata->>inviteCode', 'eq', code)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));

        if (response != null) {
          dynamic tripData = response['data'];
          if (tripData is String) {
            tripData = jsonDecode(tripData);
          }
          if (tripData is Map<String, dynamic>) {
            final trip = Trip.fromJson(tripData);
            _inviteCodeToTripId[code] = trip.metadata.id;
            _sharedTripsCache[code] = trip;
            return trip;
          }
        }
      } catch (e) {
        debugPrint('[TripSharingService] getTripByInviteCode 클라우드 조회 실패: $e');
      }
    }

    return null;
  }

  /// 초대 코드로 여행 참여하기 (새 멤버 등록)
  Future<Trip?> joinTripWithInviteCode({
    required String inviteCode,
    required String userId,
    required String email,
    required String displayName,
  }) async {
    final code = normalizeCode(inviteCode);
    final trip = await getTripByInviteCode(code);
    if (trip == null) return null;

    // 이미 소유자인 경우
    if (trip.metadata.ownerId == userId) {
      return trip;
    }

    // 이미 멤버에 등록되어 있는지 확인
    final members = List<TripMember>.from(trip.metadata.members);
    final existingIndex = members.indexWhere((m) => m.userId == userId);

    if (existingIndex != -1) {
      // 이미 참여 중
      return trip;
    }

    // 새 멤버(기본 editor) 생성 및 추가
    final newMember = TripMember(
      userId: userId,
      email: email,
      displayName: displayName.isNotEmpty ? displayName : '동행자',
      role: 'editor',
      joinedAt: DateTime.now().toUtc().toIso8601String(),
    );
    members.add(newMember);

    final updatedMeta = trip.metadata.copyWith(members: members);
    final updatedTrip = trip.copyWith(metadata: updatedMeta);

    // 캐시 갱신
    _sharedTripsCache[code] = updatedTrip;

    // Supabase 클라우드 동기화 (trip_members 및 trips 테이블 갱신)
    final client = _client;
    if (client != null && SupabaseService.isInitialized) {
      try {
        // trip_members 테이블 등록
        await client.from('trip_members').upsert({
          'trip_id': trip.metadata.id,
          'user_id': userId,
          'role': 'editor',
        }).timeout(const Duration(seconds: 8));

        // trips 테이블 data 필드에 멤버 반영
        await client
            .from('trips')
            .update({'data': updatedTrip.toJson()})
            .eq('id', trip.metadata.id)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[TripSharingService] joinTrip 클라우드 멤버 등록 에러: $e');
      }
    }

    return updatedTrip;
  }

  /// 멤버 역할(Role: 'editor' | 'viewer') 변경 (Owner 전용)
  Trip updateMemberRole({
    required Trip trip,
    required String targetUserId,
    required String newRole,
    required String requestUserId,
  }) {
    Trip baseTrip = trip;
    if (trip.metadata.inviteCode.isNotEmpty) {
      final code = normalizeCode(trip.metadata.inviteCode);
      if (_sharedTripsCache.containsKey(code)) {
        baseTrip = _sharedTripsCache[code]!;
      }
    }

    if (baseTrip.metadata.ownerId != requestUserId && baseTrip.metadata.ownerId.isNotEmpty) {
      throw Exception('여행 소유자(Owner)만 참여자 권한을 변경할 수 있습니다.');
    }

    final members = List<TripMember>.from(baseTrip.metadata.members);
    final idx = members.indexWhere((m) => m.userId == targetUserId);
    if (idx == -1) return baseTrip;

    members[idx] = members[idx].copyWith(role: newRole);
    final updatedTrip = baseTrip.copyWith(metadata: baseTrip.metadata.copyWith(members: members));

    if (baseTrip.metadata.inviteCode.isNotEmpty) {
      final code = normalizeCode(baseTrip.metadata.inviteCode);
      _sharedTripsCache[code] = updatedTrip;
    }

    // Supabase 클라우드 동기화
    final client = _client;
    if (client != null && SupabaseService.isInitialized) {
      try {
        client.from('trip_members').update({'role': newRole})
            .eq('trip_id', baseTrip.metadata.id)
            .eq('user_id', targetUserId)
            .timeout(const Duration(seconds: 8));
        client.from('trips').update({'data': updatedTrip.toJson()})
            .eq('id', baseTrip.metadata.id)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[TripSharingService] updateMemberRole 클라우드 갱신 에러: $e');
      }
    }

    return updatedTrip;
  }

  /// 멤버 내보내기/탈퇴 (Owner의 추방 또는 멤버 본인의 자진 탈퇴)
  Trip removeMember({
    required Trip trip,
    required String targetUserId,
    required String requestUserId,
  }) {
    Trip baseTrip = trip;
    if (trip.metadata.inviteCode.isNotEmpty) {
      final code = normalizeCode(trip.metadata.inviteCode);
      if (_sharedTripsCache.containsKey(code)) {
        baseTrip = _sharedTripsCache[code]!;
      }
    }

    final isOwner = baseTrip.metadata.ownerId == requestUserId || baseTrip.metadata.ownerId.isEmpty;
    final isSelf = targetUserId == requestUserId;

    if (!isOwner && !isSelf) {
      throw Exception('참여자 추방은 소유자만 가능하며, 본인만 탈퇴할 수 있습니다.');
    }

    final members = List<TripMember>.from(baseTrip.metadata.members);
    members.removeWhere((m) => m.userId == targetUserId);
    final updatedTrip = baseTrip.copyWith(metadata: baseTrip.metadata.copyWith(members: members));

    if (baseTrip.metadata.inviteCode.isNotEmpty) {
      final code = normalizeCode(baseTrip.metadata.inviteCode);
      _sharedTripsCache[code] = updatedTrip;
    }

    // Supabase 클라우드 동기화
    final client = _client;
    if (client != null && SupabaseService.isInitialized) {
      try {
        client.from('trip_members').delete()
            .eq('trip_id', baseTrip.metadata.id)
            .eq('user_id', targetUserId)
            .timeout(const Duration(seconds: 8));
        client.from('trips').update({'data': updatedTrip.toJson()})
            .eq('id', baseTrip.metadata.id)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[TripSharingService] removeMember 클라우드 삭제 에러: $e');
      }
    }

    return updatedTrip;
  }

  /// 테스트 격리용 캐시 초기화
  static void clearCache() {
    _inviteCodeToTripId.clear();
    _sharedTripsCache.clear();
  }
}
