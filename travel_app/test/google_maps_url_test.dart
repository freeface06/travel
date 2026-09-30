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
}
