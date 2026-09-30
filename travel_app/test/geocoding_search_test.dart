/// @intent GeocodingService 하이브리드 검색 단위 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/geocoding_service.dart';

void main() {
  group('GeocodingService - 하이브리드 스마트 검색(위키백과 랜드마크 + Nominatim) 검증', () {
    late GeocodingService service;

    setUp(() {
      service = GeocodingService();
    });

    test('해외 공항 한글 검색 검증: 응우라라이 공항 -> 응우라라이 국제공항 반환', () async {
      final results = await service.searchPlaces('응우라라이 공항');
      expect(results, isNotEmpty);
      expect(results.first.name, contains('응우라라이'));
      expect(results.first.lat, closeTo(-8.748, 0.05));
      expect(results.first.lng, closeTo(115.167, 0.05));
    });

    test('해외 도시별 공항 검색 검증: 발리 공항 -> 응우라라이/발리 관련 장소 반환', () async {
      final results = await service.searchPlaces('발리 공항');
      expect(results, isNotEmpty);
      final hasAirport = results.any((r) => r.name.contains('응우라라이') || r.name.contains('발리'));
      expect(hasAirport, isTrue);
    });

    test('글로벌 랜드마크 한글 검색 검증: 도쿄 타워', () async {
      final results = await service.searchPlaces('도쿄 타워');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name.contains('도쿄')), isTrue);
    });

    test('국내 대표 공항 검색 검증: 인천공항', () async {
      final results = await service.searchPlaces('인천공항');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name.contains('인천')), isTrue);
    });
  });
}
