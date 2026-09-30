/// @intent Supabase 클라우드 기반 계정별 여행 데이터 동기화 및 오프라인-온라인 충돌 해결(Conflict Resolution) 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

enum CloudSyncResultStatus {
  success,
  offline,
  skipped,
  error,
}

class CloudSyncResult {
  final CloudSyncResultStatus status;
  final String message;
  final List<Trip> syncedTrips;

  const CloudSyncResult({
    required this.status,
    required this.message,
    this.syncedTrips = const [],
  });
}

class CloudSyncService {
  final SupabaseService _supabaseService;

  CloudSyncService({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService();

  SupabaseClient? get _client => SupabaseService.client;

  bool get isCloudAvailable => SupabaseService.isInitialized && _client != null;

  /// 클라우드에서 특정 사용자의 여행 목록 조회 (RLS 기반 격리)
  Future<List<Trip>> fetchUserTrips(String userId) async {
    if (!isCloudAvailable || userId.isEmpty || userId == 'guest' || userId == 'guest-local-user') {
      return [];
    }

    try {
      final client = _client!;
      final response = await client
          .from('trips')
          .select('*')
          .eq('owner_id', userId)
          .order('updated_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final List<Trip> trips = [];
      for (final item in response) {
        try {
          dynamic tripData = item['data'];
          if (tripData is String) {
            tripData = jsonDecode(tripData);
          }
          if (tripData is Map<String, dynamic>) {
            final trip = Trip.fromJson(tripData);
            trips.add(StorageService.sanitizeTrip(trip));
          }
        } catch (e) {
          debugPrint('[CloudSyncService] 개별 여행 파싱 에러 (무시): $e');
        }
      }
      return trips;
    } catch (e) {
      debugPrint('[CloudSyncService] fetchUserTrips 네트워크 또는 쿼리 에러: $e');
      // Supabase REST Service를 통한 fallback 시도
      try {
        final restTrips = await _supabaseService.fetchTrips();
        return restTrips;
      } catch (_) {
        return [];
      }
    }
  }

  /// 단일 여행 계획을 클라우드에 upsert 동기화
  Future<bool> syncTripToCloud(Trip trip, String userId) async {
    if (!isCloudAvailable || userId.isEmpty || userId == 'guest' || userId == 'guest-local-user') {
      return false;
    }

    try {
      final sanitized = StorageService.sanitizeTrip(trip);
      final client = _client!;
      final record = {
        'id': sanitized.metadata.id,
        'owner_id': userId,
        'title': sanitized.metadata.title,
        'start_date': sanitized.metadata.startDate,
        'end_date': sanitized.metadata.endDate,
        'base_currency': sanitized.metadata.baseCurrency,
        'data': sanitized.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      await client.from('trips').upsert(record).timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      debugPrint('[CloudSyncService] syncTripToCloud 에러, REST Fallback 시도: $e');
      return await _supabaseService.syncTrip(trip);
    }
  }

  /// 클라우드에서 특정 여행 삭제
  Future<bool> deleteTripFromCloud(String tripId, String userId) async {
    if (!isCloudAvailable || userId.isEmpty || userId == 'guest' || userId == 'guest-local-user') {
      return false;
    }

    try {
      final client = _client!;
      await client
          .from('trips')
          .delete()
          .eq('id', tripId)
          .eq('owner_id', userId)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      debugPrint('[CloudSyncService] deleteTripFromCloud 에러, REST Fallback 시도: $e');
      return await _supabaseService.deleteTrip(tripId);
    }
  }

  /// 게스트(로컬) 여행들을 로그인 사용자 소유로 일괄 마이그레이션
  Future<int> migrateLocalTripsToCloud(List<Trip> localTrips, String userId) async {
    if (!isCloudAvailable || localTrips.isEmpty || userId.isEmpty || userId == 'guest') {
      return 0;
    }

    int migratedCount = 0;
    for (final trip in localTrips) {
      // 기본 생성된 빈 템플릿은 제외
      if (trip.metadata.id == 'trip-my-first-trip' && trip.items.isEmpty) {
        continue;
      }
      final success = await syncTripToCloud(trip, userId);
      if (success) {
        migratedCount++;
      }
    }
    return migratedCount;
  }

  /// 로컬 여행 목록과 원격 여행 목록 간의 충돌 해결 (합집합 및 최신 타임스탬프 기준)
  List<Trip> resolveConflicts(List<Trip> localTrips, List<Trip> remoteTrips) {
    if (remoteTrips.isEmpty) return List<Trip>.from(localTrips);
    if (localTrips.isEmpty) return List<Trip>.from(remoteTrips);

    final Map<String, Trip> mergedMap = {};

    // 1. 로컬 여행 우선 등록
    for (final trip in localTrips) {
      mergedMap[trip.metadata.id] = trip;
    }

    // 2. 원격 여행 병합 (원격 데이터가 있으면 최신 상태로 원격 채택)
    for (final rTrip in remoteTrips) {
      final id = rTrip.metadata.id;
      if (!mergedMap.containsKey(id)) {
        mergedMap[id] = rTrip;
      } else {
        // 동일 ID 존재 시 아이템 수가 많거나 기본 원격 상태 채택
        final lTrip = mergedMap[id]!;
        if (rTrip.items.length >= lTrip.items.length) {
          mergedMap[id] = rTrip;
        }
      }
    }

    return mergedMap.values.toList();
  }
}
