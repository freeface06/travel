// @intent GeocodingService parseCoordinates 정규식 및 경계값 파싱 단위 테스트
// @agent  Gemini/manager-develop
// @branch feat/flutter-migration
// @author @developer_name
// @date   2026-09-30

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/geocoding_service.dart';

void main() {
  group('GeocodingService - parseCoordinates 좌표 파싱 검증', () {
    test('쉼표 구분 구글맵 좌표 문자열 정상 파싱', () {
      const input = '35.65858, 139.74543';
      final coord = GeocodingService.parseCoordinates(input);
      expect(coord, isNotNull);
      expect(coord!.lat, closeTo(35.65858, 0.0001));
      expect(coord.lng, closeTo(139.74543, 0.0001));
    });

    test('괄호 및 공백 포함 구글맵 좌표 정상 파싱', () {
      const input = '(37.5665, 126.9780)';
      final coord = GeocodingService.parseCoordinates(input);
      expect(coord, isNotNull);
      expect(coord!.lat, closeTo(37.5665, 0.0001));
      expect(coord.lng, closeTo(126.9780, 0.0001));
    });

    test('슬래시 구분 좌표 문자열 정상 파싱', () {
      const input = '48.8584 / 2.2945';
      final coord = GeocodingService.parseCoordinates(input);
      expect(coord, isNotNull);
      expect(coord!.lat, closeTo(48.8584, 0.0001));
      expect(coord.lng, closeTo(2.2945, 0.0001));
    });

    test('위도/경도 유효 범위 초과 시 null 반환 (위도 90 초과, 경도 180 초과)', () {
      expect(GeocodingService.parseCoordinates('95.0, 120.0'), isNull);
      expect(GeocodingService.parseCoordinates('-95.0, 120.0'), isNull);
      expect(GeocodingService.parseCoordinates('35.0, 185.0'), isNull);
      expect(GeocodingService.parseCoordinates('35.0, -185.0'), isNull);
    });

    test('비정상 문자열 또는 빈 문자열 입력 시 null 반환', () {
      expect(GeocodingService.parseCoordinates(''), isNull);
      expect(GeocodingService.parseCoordinates('도쿄타워'), isNull);
      expect(GeocodingService.parseCoordinates('abc, def'), isNull);
    });

    test('구글맵 데스크톱 KELANTEL BALI URL에서 핀 좌표 및 장소명 추출', () {
      const url = 'https://www.google.co.kr/maps/place/KELANTEL+BALI/@-8.7483295,115.1667894,16.75z/data=!4m17!1m7!3m6!1s0x2dd2440939527ecb:0xcbcba0c9b0e1a3bc!2sKELANTEL+BALI!8m2!3d-8.7517083!4d115.1708333';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.name, 'KELANTEL BALI');
      expect(details.lat, closeTo(-8.7517083, 0.0001));
      expect(details.lng, closeTo(115.1708333, 0.0001));

      final coord = GeocodingService.parseCoordinates(url);
      expect(coord, isNotNull);
      expect(coord!.lat, closeTo(-8.7517083, 0.0001));
      expect(coord.lng, closeTo(115.1708333, 0.0001));
    });

    test('구글맵 한글 URL 인코딩 장소명 및 좌표 추출', () {
      const url = 'https://www.google.com/maps/place/%EB%8F%84%EC%BF%84+%ED%83%80%EC%9B%8C/@35.6585805,139.7454329,17z';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.name, '도쿄 타워');
      expect(details.lat, closeTo(35.6585805, 0.0001));
      expect(details.lng, closeTo(139.7454329, 0.0001));
    });

    test('모바일 공유 텍스트(상호명 + URL)에서 상호명과 좌표 추출', () {
      const shareText = 'KELANTEL BALI https://www.google.com/maps/place/KELANTEL+BALI/@-8.7517083,115.1708333,17z';
      final details = GeocodingService.parseLocationDetails(shareText);
      expect(details, isNotNull);
      expect(details!.name, 'KELANTEL BALI');
      expect(details.lat, closeTo(-8.7517083, 0.0001));
      expect(details.lng, closeTo(115.1708333, 0.0001));
    });

    test('구글맵 쿼리 파라미터(q=lat,lng) 좌표 추출', () {
      const url = 'https://www.google.com/maps?q=-8.7517083,115.1708333';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.lat, closeTo(-8.7517083, 0.0001));
      expect(details.lng, closeTo(115.1708333, 0.0001));
    });

    test('@ 접두사 좌표 문자열 정상 파싱', () {
      const input = '@-8.7517083, 115.1708333';
      final details = GeocodingService.parseLocationDetails(input);
      expect(details, isNotNull);
      expect(details!.lat, closeTo(-8.7517083, 0.0001));
      expect(details.lng, closeTo(115.1708333, 0.0001));
    });

    test('모바일 멀티라인 공유 텍스트(상호명 + 주소 + URL)에서 상호명, 주소, 좌표 분리 추출', () {
      const shareText = '''
KELANTEL BALI
Jl. Taman Sari No.22, Tuban, Kec. Kuta, Kabupaten Badung, Bali 80361
https://www.google.com/maps/place/KELANTEL+BALI/@-8.7517083,115.1708333,17z
''';
      final details = GeocodingService.parseLocationDetails(shareText);
      expect(details, isNotNull);
      expect(details!.name, 'KELANTEL BALI');
      expect(details.address, 'Jl. Taman Sari No.22, Tuban, Kec. Kuta, Kabupaten Badung, Bali 80361');
      expect(details.lat, closeTo(-8.7517083, 0.0001));
      expect(details.lng, closeTo(115.1708333, 0.0001));
    });

    test('isUrlOrCoordinates URL 및 좌표 감지 판별', () {
      expect(GeocodingService.isUrlOrCoordinates('https://google.com/maps/place/KELANTEL+BALI'), isTrue);
      expect(GeocodingService.isUrlOrCoordinates('https://maps.app.goo.gl/xyz123'), isTrue);
      expect(GeocodingService.isUrlOrCoordinates('-8.7517, 115.1708'), isTrue);
      expect(GeocodingService.isUrlOrCoordinates('도쿄 타워\nhttps://maps.app.goo.gl/xyz123'), isTrue);
      expect(GeocodingService.isUrlOrCoordinates('도쿄 타워'), isFalse);
      expect(GeocodingService.isUrlOrCoordinates(''), isFalse);
    });
  });
}
