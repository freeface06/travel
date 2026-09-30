/// @intent 다중 사용자/게스트 계정별 로컬 격리 저장 및 1.0.0 레거시 데이터 하위 호환 마이그레이션 스토리지 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';

class StorageService {
  static const String legacyStorageKeyV2 = 'mytriplog_trips_data_v2';
  static const String legacyStorageKeyV1 = 'mytriplog_trip_data_v1';

  static const Set<String> dummyItemIds = {
    'item-001',
    'item-002',
    'item-003',
    'item-004',
    'item-005',
    'item-006',
    'item-007',
    'item-008',
  };

  /// 계정별 로컬 저장소 키 반환 (게스트 vs 개별 인증 사용자)
  static String getTripsKey(String? userId) {
    if (userId == null || userId.trim().isEmpty || userId == 'guest' || userId == 'guest-local-user') {
      return 'guest_trips_data_v2';
    }
    return 'user_${userId.trim()}_trips_data_v2';
  }

  /// 계정별 활성 여행 ID 키 반환
  static String getCurrentTripIdKey(String? userId) {
    if (userId == null || userId.trim().isEmpty || userId == 'guest' || userId == 'guest-local-user') {
      return 'current_trip_id_guest';
    }
    return 'current_trip_id_${userId.trim()}';
  }

  /// 더미 데이터 및 레거시 데이터 감지 및 정제(Sanitize)
  static Trip sanitizeTrip(Trip trip) {
    var meta = trip.metadata;
    final legacyTitles = ['우리의 로맨틱 신혼여행', '도쿄 3박 4일 감성 힐링 여행'];

    if (meta.id == 'trip-honeymoon-2026' || legacyTitles.contains(meta.title)) {
      return Trip.defaultTrip();
    }

    final sanitizedItems = trip.items.where((item) {
      if (dummyItemIds.contains(item.id)) return false;
      if (item.title.contains('에어서울 RS701') || item.title.contains('나리타 국제공항')) {
        return false;
      }
      return true;
    }).toList();

    String tripId = meta.id;
    if (tripId.isEmpty) {
      tripId = 'trip-${DateTime.now().millisecondsSinceEpoch}';
      meta = meta.copyWith(id: tripId);
    }

    return Trip(metadata: meta, items: sanitizedItems);
  }

  /// 특정 사용자(또는 게스트)의 저장소에서 전체 여행 목록 및 현재 활성 여행 ID 로드
  Future<({List<Trip> trips, String currentTripId})> loadTrips({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultTrip = Trip.defaultTrip();
    final key = getTripsKey(userId);
    final currentIdKey = getCurrentTripIdKey(userId);

    try {
      // 1. 사용자 계정별 격리 키에서 로드 시도
      final rawUserTrips = prefs.getString(key);
      if (rawUserTrips != null && rawUserTrips.isNotEmpty) {
        final decoded = jsonDecode(rawUserTrips);
        if (decoded is Map<String, dynamic> && decoded['trips'] is List) {
          final rawTrips = decoded['trips'] as List;
          final List<Trip> parsedTrips = [];

          for (final t in rawTrips) {
            if (t is Map<String, dynamic>) {
              final trip = Trip.fromJson(t);
              parsedTrips.add(sanitizeTrip(trip));
            }
          }

          if (parsedTrips.isNotEmpty) {
            String currentId = prefs.getString(currentIdKey) ??
                decoded['currentTripId'] as String? ??
                parsedTrips.first.metadata.id;

            if (currentId == 'trip-honeymoon-2026') {
              currentId = 'trip-my-first-trip';
            }
            if (!parsedTrips.any((t) => t.metadata.id == currentId)) {
              currentId = parsedTrips.first.metadata.id;
            }

            return (trips: parsedTrips, currentTripId: currentId);
          }
        }
      }

      // 2. 계정별 데이터가 없고 게스트인 경우: 1.0.0 레거시 데이터 마이그레이션 확인
      final isGuest = userId == null || userId.isEmpty || userId == 'guest' || userId == 'guest-local-user';
      if (isGuest) {
        final legacyV2 = prefs.getString(legacyStorageKeyV2);
        if (legacyV2 != null && legacyV2.isNotEmpty) {
          final decoded = jsonDecode(legacyV2);
          if (decoded is Map<String, dynamic> && decoded['trips'] is List) {
            final rawTrips = decoded['trips'] as List;
            final List<Trip> parsedTrips = [];

            for (final t in rawTrips) {
              if (t is Map<String, dynamic>) {
                final trip = Trip.fromJson(t);
                parsedTrips.add(sanitizeTrip(trip));
              }
            }

            if (parsedTrips.isNotEmpty) {
              final currentId = decoded['currentTripId'] as String? ?? parsedTrips.first.metadata.id;
              // 게스트 키로 안전 이전 저장
              await saveTrips(parsedTrips, currentId, userId: userId);
              return (trips: parsedTrips, currentTripId: currentId);
            }
          }
        }

        // 레거시 V1 확인
        final legacyV1 = prefs.getString(legacyStorageKeyV1);
        if (legacyV1 != null && legacyV1.isNotEmpty) {
          final decoded = jsonDecode(legacyV1);
          if (decoded is Map<String, dynamic>) {
            final legacyTrip = sanitizeTrip(Trip.fromJson(decoded));
            await saveTrips([legacyTrip], legacyTrip.metadata.id, userId: userId);
            return (trips: [legacyTrip], currentTripId: legacyTrip.metadata.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageService] loadTrips 파싱 에러 (무시): $e');
    }

    return (trips: [defaultTrip], currentTripId: defaultTrip.metadata.id);
  }

  /// 전체 여행 목록 및 활성 여행 영구 저장 (계정별 분리 저장)
  Future<void> saveTrips(
    List<Trip> trips,
    String currentTripId, {
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final validTrips = trips.map((t) => sanitizeTrip(t)).toList();
    final key = getTripsKey(userId);
    final currentIdKey = getCurrentTripIdKey(userId);

    final payload = {
      'trips': validTrips.map((t) => t.toJson()).toList(),
      'currentTripId': currentTripId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    final jsonStr = jsonEncode(payload);
    await prefs.setString(key, jsonStr);
    await prefs.setString(currentIdKey, currentTripId);

    // 하위 호환성: 게스트일 때만 레거시 키 동시 갱신
    final isGuest = userId == null || userId.isEmpty || userId == 'guest' || userId == 'guest-local-user';
    if (isGuest) {
      await prefs.setString(legacyStorageKeyV2, jsonStr);
      final currentTrip = validTrips.firstWhere(
        (t) => t.metadata.id == currentTripId,
        orElse: () => validTrips.isNotEmpty ? validTrips.first : Trip.defaultTrip(),
      );
      await prefs.setString(legacyStorageKeyV1, jsonEncode(currentTrip.toJson()));
    }
  }

  /// 게스트 모드에서 생성한 여행 데이터 조회 (로그인 시 마이그레이션 여부 확인용)
  Future<List<Trip>> getGuestTrips() async {
    final result = await loadTrips(userId: null);
    return result.trips;
  }

  /// 게스트 모드 여행 데이터 클리어 (마이그레이션 후 정리)
  Future<void> clearGuestTrips() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(getTripsKey(null));
    await prefs.remove(getCurrentTripIdKey(null));
    await prefs.remove(legacyStorageKeyV2);
    await prefs.remove(legacyStorageKeyV1);
  }

  /// 특정 사용자 로컬 캐시 클리어
  Future<void> clearUserTrips(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(getTripsKey(userId));
    await prefs.remove(getCurrentTripIdKey(userId));
  }
}
