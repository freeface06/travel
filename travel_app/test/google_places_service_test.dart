/// @intent GooglePlacesService 구글맵 장소 사진(Place Photos) 실시간 API 조회 및 MockClient 단위 테스트
/// @agent Gemini/manager-develop
/// @branch feat/google-place-photos
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/services/google_places_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GooglePlacesService API 키 및 기본 동작 테스트', () {
    test('기본 내장 API 키가 유효하게 디코딩된다', () {
      final key = GooglePlacesService.defaultApiKey;
      expect(key, isNotEmpty);
      expect(key.startsWith('AIzaSy'), isTrue);
    });

    test('SharedPreferences 사용자 정의 API 키 저장 및 복원', () async {
      const customKey = 'CUSTOM_TEST_API_KEY_123';
      await GooglePlacesService.saveApiKey(customKey);
      final retrieved = await GooglePlacesService.getApiKey();
      expect(retrieved, equals(customKey));

      await GooglePlacesService.saveApiKey('');
      final fallback = await GooglePlacesService.getApiKey();
      expect(fallback, equals(GooglePlacesService.defaultApiKey));
    });

    test('장소명이 비어있으면 빈 목록을 즉시 반환한다', () async {
      final photos = await GooglePlacesService.fetchPlacePhotos(placeName: '   ');
      expect(photos, isEmpty);
    });
  });

  group('GooglePlacesService HTTP 모의 응답(MockClient) 테스트', () {
    test('Find Place API에서 사진 목록 10장을 정상적으로 반환한다', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('findplacefromtext')) {
          final dummyPhotos = List.generate(
            10,
            (i) => {'photo_reference': 'REF_TOKEN_$i', 'width': 1200, 'height': 800},
          );
          final responseBody = {
            'candidates': [
              {
                'place_id': 'ChIJ_TOKYO_TOWER_123',
                'name': '도쿄 타워',
                'photos': dummyPhotos,
              }
            ],
            'status': 'OK'
          };
          return http.Response(jsonEncode(responseBody), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final photos = await GooglePlacesService.fetchPlacePhotos(
        placeName: '도쿄 타워',
        client: mockClient,
      );

      expect(photos.length, equals(10));
      expect(photos.first, contains('photoreference=REF_TOKEN_0'));
      expect(photos.last, contains('photoreference=REF_TOKEN_9'));
      expect(photos.first, contains('maps.googleapis.com/maps/api/place/photo'));
    });

    test('Find Place에 사진이 없으나 place_id가 있을 때 Place Details로 사진을 보강한다', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('findplacefromtext')) {
          final responseBody = {
            'candidates': [
              {
                'place_id': 'ChIJ_PLACE_WITH_DETAILS_ONLY',
                'name': '신주쿠 교엔',
                'photos': [], // 사진 없음
              }
            ],
            'status': 'OK'
          };
          return http.Response(jsonEncode(responseBody), 200, headers: {'content-type': 'application/json'});
        } else if (request.url.path.contains('place/details')) {
          final dummyPhotos = List.generate(
            5,
            (i) => {'photo_reference': 'DETAIL_REF_$i'},
          );
          final detailBody = {
            'result': {
              'photos': dummyPhotos,
              'name': '신주쿠 교엔',
            },
            'status': 'OK'
          };
          return http.Response(jsonEncode(detailBody), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final photos = await GooglePlacesService.fetchPlacePhotos(
        placeName: '신주쿠 교엔',
        client: mockClient,
      );

      expect(photos.length, equals(5));
      expect(photos.first, contains('photoreference=DETAIL_REF_0'));
    });

    test('장소를 찾지 못하거나 ZERO_RESULTS 응답 시 빈 목록을 반환한다', () async {
      final mockClient = MockClient((request) async {
        final body = {'candidates': [], 'status': 'ZERO_RESULTS'};
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      });

      final photos = await GooglePlacesService.fetchPlacePhotos(
        placeName: '존재하지않는미지의장소12345',
        client: mockClient,
      );

      expect(photos, isEmpty);
    });
  });
}
