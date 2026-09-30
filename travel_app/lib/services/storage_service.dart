/// @intent SharedPreferences 기반 다중 여행 영구 저장 및 더미/레거시 데이터 자동 정제 서비스
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';


class StorageService {
  static const String storageKeyV2 = 'mytriplog_trips_data_v2';
  static const String storageKeyLegacy = 'mytriplog_trip_data_v1';

  static const Set<String> dummyItemIds = {
    'item-001', 'item-002', 'item-003', 'item-004',
    'item-005', 'item-006', 'item-007', 'item-008',
  };

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

  /// 저장소에서 전체 여행 목록 및 현재 활성 여행 ID 로드
  Future<({List<Trip> trips, String currentTripId})> loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultTrip = Trip.defaultTrip();

    try {
      // 1. V2 복수 여행 데이터 로드 시도
      final rawV2 = prefs.getString(storageKeyV2);
      if (rawV2 != null && rawV2.isNotEmpty) {
        final decoded = jsonDecode(rawV2);
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
            String currentId = decoded['currentTripId'] as String? ?? parsedTrips.first.metadata.id;
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

      // 2. V1 레거시 단일 여행 로드 및 마이그레이션
      final rawV1 = prefs.getString(storageKeyLegacy);
      if (rawV1 != null && rawV1.isNotEmpty) {
        final decoded = jsonDecode(rawV1);
        if (decoded is Map<String, dynamic>) {
          final legacyTrip = sanitizeTrip(Trip.fromJson(decoded));
          await saveTrips([legacyTrip], legacyTrip.metadata.id);
          return (trips: [legacyTrip], currentTripId: legacyTrip.metadata.id);
        }
      }
    } catch (_) {
      // 파싱 실패 시 기본 상태 반환
    }

    return (trips: [defaultTrip], currentTripId: defaultTrip.metadata.id);
  }

  /// 전체 여행 목록 및 활성 여행 영구 저장
  Future<void> saveTrips(List<Trip> trips, String currentTripId) async {
    final prefs = await SharedPreferences.getInstance();
    final validTrips = trips.map((t) => sanitizeTrip(t)).toList();

    final payload = {
      'trips': validTrips.map((t) => t.toJson()).toList(),
      'currentTripId': currentTripId,
    };

    final jsonStr = jsonEncode(payload);
    await prefs.setString(storageKeyV2, jsonStr);

    final currentTrip = validTrips.firstWhere(
      (t) => t.metadata.id == currentTripId,
      orElse: () => validTrips.isNotEmpty ? validTrips.first : Trip.defaultTrip(),
    );
    await prefs.setString(storageKeyLegacy, jsonEncode(currentTrip.toJson()));
  }
}
