/// @intent Test Google Maps short link resolution behavior and verify Korean IP / Tancheon Viaduct false positive elimination
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/geocoding_service.dart';

import 'dart:io';

void main() {
  HttpOverrides.global = null;
  test('Test GeocodingService parseLocationDetails with various inputs', () {
    // 1. Raw coordinates
    final r1 = GeocodingService.parseLocationDetails('-8.51234, 115.12345');
    expect(r1, isNotNull);
    expect(r1!.lat, closeTo(-8.51234, 0.0001));
    expect(r1.lng, closeTo(115.12345, 0.0001));

    // 2. Google Maps place URL with coordinates
    final r2 = GeocodingService.parseLocationDetails(
      'https://www.google.com/maps/place/Kelantel+Bali/@-8.51234,115.12345,17z/data=!3m1!4b1!4m6!3m5!1s0x2dd23f000:0x0!8m2!3d-8.51234!4d115.12345',
    );
    expect(r2, isNotNull);
    expect(r2!.name, equals('Kelantel Bali'));
    expect(r2.lat, closeTo(-8.51234, 0.0001));
    expect(r2.lng, closeTo(115.12345, 0.0001));

    // 3. User exact redirected URL
    final r3 = GeocodingService.parseLocationDetails(
      'https://www.google.co.kr/maps/place/%EC%95%84%EC%9D%B4%EC%BD%98%EB%B0%9C%EB%A6%AC/@-8.6868201,115.2607875,17z/data=!3m1!4b1!4m6!3m5!1s0x2dd24192e5750eed:0x129054577eae3c17!8m2!3d-8.6868254!4d115.2633624!16s%2Fg%2F11j5fq082f?entry=tts',
    );
    expect(r3, isNotNull);
    expect(r3!.name, equals('아이콘발리'));
    expect(r3.lat, closeTo(-8.6868, 0.001));
    expect(r3.lng, closeTo(115.263, 0.001));
  });

  test('Test GeocodingService resolveLocation with ZEMd8tfm1rK8MCAU8', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('https://maps.app.goo.gl/ZEMd8tfm1rK8MCAU8');
    // ignore: avoid_print
    print('RESOLVED RESULT 1: $result');
    expect(result, isNotNull);
    expect(result!.name, contains('아이콘발리'));
    expect(result.lat, closeTo(-8.6868, 0.01));
    expect(result.lng, closeTo(115.2633, 0.01));

    // Verify it is NOT Korean IP / Tancheon Viaduct (37.4797, 127.1169)
    expect(result.lat, isNot(closeTo(37.4797, 0.1)));
    expect(result.lng, isNot(closeTo(127.1169, 0.1)));
  });

  test('Test GeocodingService resolveLocation with TqhgvcyPa4C6aP8g7', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('https://maps.app.goo.gl/TqhgvcyPa4C6aP8g7?g_st=ac');
    // ignore: avoid_print
    print('RESOLVED RESULT 2: $result');
    expect(result, isNotNull);
    expect(result!.name, contains('아이콘발리'));
    expect(result.lat, closeTo(-8.6868, 0.05));
    expect(result.lng, closeTo(115.2633, 0.05));

    // Verify it is NOT Korean IP / Tancheon Viaduct (37.4797, 127.1169)
    expect(result.lat, isNot(closeTo(37.4797, 0.1)));
    expect(result.lng, isNot(closeTo(127.1169, 0.1)));
  });

  test('Test GeocodingService resolveLocation with UYsaPYJzftGy3wpCA (Kos Bulan Bali)', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('https://maps.app.goo.gl/UYsaPYJzftGy3wpCA');
    // ignore: avoid_print
    print('RESOLVED RESULT 3 (Kos Bulan Bali): $result');
    expect(result, isNotNull);
    expect(result!.name, contains('Kos Bulan Bali'));
    // Exact location in Kuta/Tuban: -8.7547, 115.1747
    expect(result.lat, closeTo(-8.7547, 0.01));
    expect(result.lng, closeTo(115.1747, 0.01));
  });

  test('Test GeocodingService resolveLocation with uSgojHRexKhmgE2F6 (Hilton Garden Inn Bali)', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('https://maps.app.goo.gl/uSgojHRexKhmgE2F6?g_st=ac');
    // ignore: avoid_print
    print('RESOLVED RESULT 4 (Hilton Garden Inn): $result');
    expect(result, isNotNull);
    expect(result!.name, anyOf(contains('힐튼'), contains('Hilton')));
    // Exact hotel location: -8.7436, 115.1710 (NOT the airport runway -8.7434, 115.1665)
    expect(result.lat, closeTo(-8.7436, 0.01));
    expect(result.lng, closeTo(115.1710, 0.01));
  });

  test('Test GeocodingService resolveLocation with tVhyKqK4EnbdRuGP8 (Kos Bulan Bali clean name & pin)', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('https://maps.app.goo.gl/tVhyKqK4EnbdRuGP8?g_st=ac');
    // ignore: avoid_print
    print('RESOLVED RESULT 5 (tVhyKqK4EnbdRuGP8): $result');
    expect(result, isNotNull);
    expect(result!.name, equals('Kos Bulan Bali'));
    expect(result.lat, closeTo(-8.7547172, 0.001));
    expect(result.lng, closeTo(115.1747161, 0.001));
    expect(result.address, isNotNull);
  });

  test('Test GeocodingService parseDmsCoordinates and DMS input in parseLocationDetails', () {
    final dms = GeocodingService.parseDmsCoordinates('8°45\'17.0"S 115°10\'29.0"E');
    expect(dms, isNotNull);
    expect(dms!.lat, closeTo(-8.754722, 0.001));
    expect(dms.lng, closeTo(115.174722, 0.001));

    final parsed = GeocodingService.parseLocationDetails('Kos Bulan Bali 8°45\'17.0"S 115°10\'29.0"E');
    expect(parsed, isNotNull);
    expect(parsed!.lat, closeTo(-8.754722, 0.001));
    expect(parsed.lng, closeTo(115.174722, 0.001));
  });

  test('Test GeocodingService resolveLocation with direct FTID', () async {
    final service = GeocodingService();
    final result = await service.resolveLocation('0x2dd245bc9ad2803f:0xa39c8c07d272ed82');
    // ignore: avoid_print
    print('RESOLVED RESULT 6 (Direct FTID): $result');
    expect(result, isNotNull);
    expect(result!.name, equals('Kos Bulan Bali'));
    expect(result.lat, closeTo(-8.7547172, 0.0001));
    expect(result.lng, closeTo(115.1747161, 0.0001));
  });

  group('구글맵 국내외 주요 랜드마크 풀 URL 정밀 파싱 검증', () {
    test('파리 에펠탑 데스크톱 URL에서 핀 좌표 및 장소명 100% 정밀 추출', () {
      const url = 'https://www.google.com/maps/place/Eiffel+Tower/@48.8583701,2.2944813,17z/data=!3m1!4b1!4m6!3m5!1s0x47e66e2964e34e2d:0x8ddca9ee380ef7e0!8m2!3d48.8583701!4d2.2944813';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.name, 'Eiffel Tower');
      expect(details.lat, closeTo(48.8583701, 0.000001));
      expect(details.lng, closeTo(2.2944813, 0.000001));
    });

    test('서울 롯데월드타워 데스크톱 URL에서 핀 좌표 및 한글 장소명 100% 정밀 추출', () {
      const url = 'https://www.google.com/maps/place/%EB%A1%AF%EB%8D%B0%EC%9B%94%EB%93%9C%ED%83%80%EC%9B%8C/@37.5125958,127.1025585,17z/data=!4m6!3m5!1s0x357ca59074092497:0x5e2b023e1ef71ff3!8m2!3d37.5125958!4d127.1025585';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.name, '롯데월드타워');
      expect(details.lat, closeTo(37.5125958, 0.000001));
      expect(details.lng, closeTo(127.1025585, 0.000001));
    });

    test('서울 경복궁 데스크톱 URL에서 핀 좌표 및 한글 장소명 100% 정밀 추출', () {
      const url = 'https://www.google.com/maps/place/%EA%B2%BD%EB%B3%B5%EA%B6%81/@37.579617,126.977041,17z/data=!4m6!3m5!1s0x357ca2eb4213f085:0x7e3e782e4e86db8a!8m2!3d37.579617!4d126.977041';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.name, '경복궁');
      expect(details.lat, closeTo(37.579617, 0.000001));
      expect(details.lng, closeTo(126.977041, 0.000001));
    });
  });

  group('모바일 공유 텍스트 및 쿼리 URL 파싱 검증', () {
    test('모바일 공유 멀티라인 텍스트(상호명 + 주소 + URL)에서 정확한 분리 추출', () {
      const shareText = '''
도쿄 타워
일본 〒105-0011 Tokyo, Minato City, Shibakoen, 4 Chome−2−8
https://www.google.com/maps/place/%EB%8F%84%EC%BF%84+%ED%83%80%EC%9B%8C/@35.6585805,139.7454329,17z
''';
      final details = GeocodingService.parseLocationDetails(shareText);
      expect(details, isNotNull);
      expect(details!.name, '도쿄 타워');
      expect(details.address, contains('Tokyo, Minato City'));
      expect(details.lat, closeTo(35.6585805, 0.0001));
      expect(details.lng, closeTo(139.7454329, 0.0001));
    });

    test('구글맵 검색 쿼리 API URL (search/?api=1&query=lat,lng) 좌표 파싱', () {
      const url = 'https://www.google.com/maps/search/?api=1&query=37.566535,126.977969';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.lat, closeTo(37.566535, 0.00001));
      expect(details.lng, closeTo(126.977969, 0.00001));
    });

    test('구글맵 q 파라미터 단축 URL (maps.google.com/?q=lat,lng) 좌표 파싱', () {
      const url = 'https://maps.google.com/?q=-8.6705,115.2126';
      final details = GeocodingService.parseLocationDetails(url);
      expect(details, isNotNull);
      expect(details!.lat, closeTo(-8.6705, 0.0001));
      expect(details.lng, closeTo(115.2126, 0.0001));
    });
  });

  group('DMS (도/분/초) 좌표 파싱 정밀도 검증', () {
    test('뉴욕 자유의 여신상 DMS 좌표 십진수 변환', () {
      final dms = GeocodingService.parseDmsCoordinates('40°41\'21.0"N 74°02\'40.0"W');
      expect(dms, isNotNull);
      expect(dms!.lat, closeTo(40.689167, 0.0001));
      expect(dms.lng, closeTo(-74.044444, 0.0001));
    });

    test('런던 빅벤 DMS 좌표 십진수 변환', () {
      final dms = GeocodingService.parseDmsCoordinates('51°30\'03.0"N 0°07\'28.0"W');
      expect(dms, isNotNull);
      expect(dms!.lat, closeTo(51.500833, 0.0001));
      expect(dms.lng, closeTo(-0.124444, 0.0001));
    });

    test('서울 경복궁 상호명 + DMS 혼합 텍스트 파싱', () {
      final details = GeocodingService.parseLocationDetails('경복궁 37°34\'43.0"N 126°58\'38.0"E');
      expect(details, isNotNull);
      expect(details!.name, '경복궁');
      expect(details.lat, closeTo(37.578611, 0.0001));
      expect(details.lng, closeTo(126.977222, 0.0001));
    });
  });

  group('Google FTID (Feature ID) 직접 조회 정밀도 검증', () {
    test('사누르 아이콘발리 FTID (0x2dd24192e5750eed:0x129054577eae3c17) 공식 직통 조회', () async {
      final service = GeocodingService();
      final result = await service.resolveLocation('0x2dd24192e5750eed:0x129054577eae3c17');
      // ignore: avoid_print
      print('RESOLVED 아이콘발리 FTID: $result');
      expect(result, isNotNull);
      expect(result!.name, contains('아이콘발리'));
      expect(result.lat, closeTo(-8.6868, 0.005));
      expect(result.lng, closeTo(115.2633, 0.005));
    });

    test('파리 에펠탑 FTID (0x47e66e2964e34e2d:0x8ddca9ee380ef7e0) 공식 직통 조회', () async {
      final service = GeocodingService();
      final result = await service.resolveLocation('0x47e66e2964e34e2d:0x8ddca9ee380ef7e0');
      // ignore: avoid_print
      print('RESOLVED 에펠탑 FTID: $result');
      expect(result, isNotNull);
      expect(result!.name, anyOf(contains('에펠탑'), contains('Tour Eiffel'), contains('Eiffel')));
      expect(result.lat, closeTo(48.8583, 0.005));
      expect(result.lng, closeTo(2.2944, 0.005));
    });
  });
}
