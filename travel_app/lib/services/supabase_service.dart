/// @intent Supabase 클라우드 클라이언트 초기화(Safe Fallback), 인증 및 REST/스토리지 동기화 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip.dart';

class SupabaseService {
  static const String defaultUrl = 'https://qmqklwelrsmlsrmtnsxt.supabase.co';
  static const String defaultAnonKey = 'sb_publishable_Gz-4w0mexqsHUTaNl6AtDw_b9W1nddm';

  static bool _isInitialized = false;

  /// Supabase SDK 초기화 여부
  static bool get isInitialized => _isInitialized;

  /// SupabaseClient 인스턴스 (초기화되지 않은 경우 null 안전 반환)
  static SupabaseClient? get client {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Supabase 클라이언트 안전 초기화 (Safe Fallback)
  static Future<void> initialize({String? url, String? anonKey}) async {
    final targetUrl = url ?? defaultUrl;
    final targetKey = anonKey ?? defaultAnonKey;

    if (targetUrl.isEmpty || targetKey.isEmpty) {
      _isInitialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: targetUrl,
        // ignore: deprecated_member_use
        anonKey: targetKey,
        debug: kDebugMode,
      );
      _isInitialized = true;
    } catch (e) {
      // 키 불일치, 네트워크 장애, 테스트 환경 등에서도 크래시 없이 안전하게 Fallback 모드로 작동
      debugPrint('[SupabaseService] 초기화 안전 건너뜀 (Fallback): $e');
      _isInitialized = false;
    }
  }

  final String url;
  final String anonKey;

  SupabaseService({
    this.url = defaultUrl,
    this.anonKey = defaultAnonKey,
  });

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  /// Supabase trips 테이블에서 전체 여행 목록 조회
  Future<List<Trip>> fetchTrips() async {
    try {
      final endpoint = Uri.parse('$url/rest/v1/trips?select=*&order=updated_at.desc');
      final response = await http.get(endpoint, headers: _headers).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! List) return [];
        final List<Trip> trips = [];

        for (final item in decoded) {
          if (item is Map) {
            try {
              dynamic tripData = item['data'];
              if (tripData is String) {
                tripData = jsonDecode(tripData);
              }
              if (tripData is Map) {
                final trip = Trip.fromJson(Map<String, dynamic>.from(tripData));
                trips.add(trip);
              }
            } catch (_) {
              // 개별 여행 파싱 에러 방어
            }
          }
        }
        return trips;
      }
    } catch (_) {
      // 네트워크 오프라인 시 빈 목록 안전 반환
    }
    return [];
  }

  /// 단일 여행 계획을 Supabase trips 테이블에 upsert 동기화
  Future<bool> syncTrip(Trip trip) async {
    try {
      final endpoint = Uri.parse('$url/rest/v1/trips');
      final record = {
        'id': trip.metadata.id,
        'title': trip.metadata.title,
        'start_date': trip.metadata.startDate,
        'end_date': trip.metadata.endDate,
        'base_currency': trip.metadata.baseCurrency,
        'data': trip.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final headers = Map<String, String>.from(_headers);
      headers['Prefer'] = 'resolution=merge-duplicates';

      final response = await http
          .post(endpoint, headers: headers, body: jsonEncode(record))
          .timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Supabase trips 테이블에서 특정 여행 계획 삭제
  Future<bool> deleteTrip(String tripId) async {
    try {
      final endpoint = Uri.parse('$url/rest/v1/trips?id=eq.$tripId');
      final response = await http.delete(endpoint, headers: _headers).timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Supabase Storage 'trip-photos' 버킷에 이미지 업로드 후 공개 CDN URL 반환
  Future<String?> uploadPhoto(Uint8List imageBytes, {String filename = 'photo.jpg'}) async {
    try {
      final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'jpg';
      final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
      final randomStr = DateTime.now().millisecondsSinceEpoch.toString();
      final path = 'trip-photos/${randomStr}_photo.$safeExt';
      final mimeType = safeExt == 'png'
          ? 'image/png'
          : safeExt == 'webp'
              ? 'image/webp'
              : 'image/jpeg';

      final uploadUrl = Uri.parse('$url/storage/v1/object/trip-photos/$path');
      final response = await http.post(
        uploadUrl,
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
          'Content-Type': mimeType,
          'x-upsert': 'true',
        },
        body: imageBytes,
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 공개 CDN URL 생성
        return '$url/storage/v1/object/public/trip-photos/$path';
      }
    } catch (_) {
      // 업로드 실패 시 null 반환
    }
    return null;
  }

  /// Supabase Storage 'trip-photos' 버킷에서 특정 사진 파일 삭제
  Future<bool> deletePhoto(String photoUrlOrPath) async {
    try {
      if (photoUrlOrPath.isEmpty || !photoUrlOrPath.contains('trip-photos')) {
        return false;
      }

      String relativePath = photoUrlOrPath;
      if (photoUrlOrPath.contains('/trip-photos/')) {
        relativePath = photoUrlOrPath.split('/trip-photos/').last;
      } else if (photoUrlOrPath.startsWith('trip-photos/')) {
        relativePath = photoUrlOrPath.substring('trip-photos/'.length);
      }

      if (relativePath.contains('?')) {
        relativePath = relativePath.split('?').first;
      }

      final deleteUrl = Uri.parse('$url/storage/v1/object/trip-photos/$relativePath');
      final response = await http.delete(
        deleteUrl,
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
      ).timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
