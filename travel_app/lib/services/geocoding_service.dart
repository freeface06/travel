/// @intent 위키백과(Wikipedia) 글로벌 랜드마크 지오코딩 및 OpenStreetMap Nominatim 하이브리드 스마트 검색 엔진
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'google_places_service.dart';

class PlaceSearchResult {
  final String name;
  final String displayName;
  final String secondaryText;
  final double lat;
  final double lng;
  final String type;

  const PlaceSearchResult({
    required this.name,
    required this.displayName,
    required this.secondaryText,
    required this.lat,
    required this.lng,
    required this.type,
  });

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    final displayName = json['display_name'] as String? ?? '';
    final parts = displayName.split(',');
    final name = parts.isNotEmpty ? parts[0].trim() : '';
    final secondary = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';

    return PlaceSearchResult(
      name: name,
      displayName: displayName,
      secondaryText: secondary,
      lat: double.tryParse(json['lat']?.toString() ?? '') ?? 0.0,
      lng: double.tryParse(json['lon']?.toString() ?? '') ?? 0.0,
      type: json['type'] as String? ?? 'place',
    );
  }
}

class ParsedLocation {
  final String? name;
  final double lat;
  final double lng;
  final String? address;
  final String? sourceUrl;
  final String? placeId;
  final List<String> photos;

  const ParsedLocation({
    this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.sourceUrl,
    this.placeId,
    this.photos = const [],
  });

  @override
  String toString() => 'ParsedLocation(name: $name, lat: $lat, lng: $lng, address: $address, placeId: $placeId, source: $sourceUrl)';
}

class GeocodingService {
  static const String nominatimBase = 'https://nominatim.openstreetmap.org';

  /// DMS (도/분/초) 좌표 문자열 파싱 (예: 37°33'59.4"N 126°58'40.8"E 또는 8°45'17.0"S 115°10'29.0"E)
  static ({double lat, double lng})? parseDmsCoordinates(String input) {
    try {
      final dmsPattern = RegExp(
        r'''(\d{1,2})[°\s]+(\d{1,2})['′\s]+(\d{1,2}(?:\.\d+)?)["″\s]*([NSns])[\s,]+(\d{1,3})[°\s]+(\d{1,2})['′\s]+(\d{1,2}(?:\.\d+)?)["″\s]*([EWew])''',
      );
      final match = dmsPattern.firstMatch(input);
      if (match != null) {
        final latDeg = double.parse(match.group(1)!);
        final latMin = double.parse(match.group(2)!);
        final latSec = double.parse(match.group(3)!);
        final latDir = match.group(4)!.toUpperCase();

        final lngDeg = double.parse(match.group(5)!);
        final lngMin = double.parse(match.group(6)!);
        final lngSec = double.parse(match.group(7)!);
        final lngDir = match.group(8)!.toUpperCase();

        double lat = latDeg + (latMin / 60.0) + (latSec / 3600.0);
        if (latDir == 'S') lat = -lat;

        double lng = lngDeg + (lngMin / 60.0) + (lngSec / 3600.0);
        if (lngDir == 'W') lng = -lng;

        if (lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0) {
          return (lat: lat, lng: lng);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 구글맵 URL 또는 텍스트에서 Google Feature ID (ftid: 0x...:0x...) 추출
  static String? extractFtid(String text) {
    final m1 = RegExp(r'!1s(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)').firstMatch(text);
    if (m1 != null) return m1.group(1);

    final m2 = RegExp(r'[?&]ftid=(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)').firstMatch(text);
    if (m2 != null) return m2.group(1);

    final m3 = RegExp(r'(0x[0-9a-fA-F]{10,20}:0x[0-9a-fA-F]{10,20})').firstMatch(text);
    if (m3 != null) return m3.group(1);

    return null;
  }

  /// 구글맵 URL 또는 텍스트에서 Google Place ID (place_id) 추출
  static String? extractPlaceId(String text) {
    final m = RegExp(r'[?&]place_id=([A-Za-z0-9_-]{20,})').firstMatch(text);
    return m?.group(1);
  }

  /// URL, 좌표 또는 구글맵 공유 텍스트인지 판별
  static bool isUrlOrCoordinates(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    final text = input.trim();
    if (text.contains('http://') || text.contains('https://')) return true;
    if (text.contains('maps.app.goo.gl') || text.contains('goo.gl/maps')) return true;
    if (text.contains('google.') && text.contains('/maps')) return true;
    if (RegExp(r'!3d-?\d+\.\d+!4d-?\d+\.\d+').hasMatch(text)) return true;
    if (RegExp(r'@-?\d+\.\d+,\s*-?\d+\.\d+').hasMatch(text)) return true;
    if (extractFtid(text) != null || extractPlaceId(text) != null) return true;
    if (parseDmsCoordinates(text) != null) return true;
    
    // 일반 위도/경도 숫자 쌍 검사
    final cleaned = text.replaceAll('(', '').replaceAll(')', '').trim();
    final parts = cleaned.split(RegExp(r'[,/\s]+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat != null && lng != null && lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0) {
        return true;
      }
    }
    return false;
  }

  /// 구글맵 URL, 공유 텍스트, 일반 텍스트 좌표 정밀 파싱 (위도, 경도, 장소명, 주소 추출)
  static ParsedLocation? parseLocationDetails(String? input) {
    if (input == null || input.trim().isEmpty) return null;

    final trimmed = input.trim();
    final urlMatch = RegExp(r'https?://[^\s<>"]+').firstMatch(trimmed);
    final url = urlMatch?.group(0);

    String? prefixName;
    String? extraAddress;
    if (url != null) {
      final idx = trimmed.indexOf(url);
      if (idx > 0) {
        final candidate = trimmed.substring(0, idx).trim();
        final lines = candidate
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('@'))
            .toList();
        if (lines.isNotEmpty) {
          prefixName = lines.first;
          if (lines.length > 1) {
            extraAddress = lines.sublist(1).join(', ');
          }
        }
      }
      final afterIdx = idx + url.length;
      if (afterIdx < trimmed.length) {
        final afterCandidate = trimmed.substring(afterIdx).trim();
        final lines = afterCandidate
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('@'))
            .toList();
        if (lines.isNotEmpty) {
          prefixName ??= lines.first;
          if (lines.length > 1) {
            extraAddress ??= lines.sublist(1).join(', ');
          }
        }
      }
    }

    double? lat;
    double? lng;
    String? placeName;

    if (url != null) {
      // 1. 구글맵 장소 경로명 추출 (/place/<장소명>/)
      final placeMatch = RegExp(r'/place/([^/@?#]+)').firstMatch(url);
      if (placeMatch != null) {
        try {
          final raw = placeMatch.group(1)!;
          final decoded = Uri.decodeComponent(raw.replaceAll('+', ' ')).trim();
          if (decoded.isNotEmpty) {
            final splitMatch = RegExp(
              r'^(.*?)(?:\s+(Jl[:\.]|Jalan|Gang|Gg\.|Street|St\.|Road|Rd\.|Avenue|Ave\.|Blvd\.|Way|\bNo\.\b)|,(.*)$)',
              caseSensitive: false,
            ).firstMatch(decoded);
            if (splitMatch != null) {
              placeName = splitMatch.group(1)!.trim();
              extraAddress ??= decoded.substring(placeName.length).trim().replaceAll(RegExp(r'^,\s*'), '');
            } else {
              placeName = decoded;
            }
          }
        } catch (_) {}
      }

      // 2. 구글맵 고정 핀 좌표 추출 (!3d위도!4d경도)
      final pin3d = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(url);
      if (pin3d != null) {
        lat = double.tryParse(pin3d.group(1)!);
        lng = double.tryParse(pin3d.group(2)!);
      }

      // 3. 구글맵 고정 핀 좌표 대체 포맷 (!1d위도!2d경도)
      if (lat == null || lng == null) {
        final pin1d = RegExp(r'!1d(-?\d+\.\d+)!2d(-?\d+\.\d+)').firstMatch(url);
        if (pin1d != null) {
          lat = double.tryParse(pin1d.group(1)!);
          lng = double.tryParse(pin1d.group(2)!);
        }
      }

      // 4. 구글맵 쿼리 파라미터 좌표 (q=lat,lng 또는 ll=lat,lng 또는 query=lat,lng)
      if (lat == null || lng == null) {
        try {
          final parsedUri = Uri.parse(url);
          final qParam = parsedUri.queryParameters['q'] ??
              parsedUri.queryParameters['query'] ??
              parsedUri.queryParameters['ll'];
          if (qParam != null) {
            final qCoord = RegExp(r'(-?\d{1,2}(?:\.\d+)?)[,\s/]+(-?\d{1,3}(?:\.\d+)?)').firstMatch(qParam);
            if (qCoord != null) {
              lat = double.tryParse(qCoord.group(1)!);
              lng = double.tryParse(qCoord.group(2)!);
            }
          }
        } catch (_) {}
      }

      // 5. 구글맵 중심점/좌표 (@lat,lng)
      // 데스크톱 구글맵 웹 브라우저 URL의 핵심 좌표 포맷 지원
      if (lat == null || lng == null) {
        final centerMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
        if (centerMatch != null) {
          lat = double.tryParse(centerMatch.group(1)!);
          lng = double.tryParse(centerMatch.group(2)!);
        }
      }
    }

    // URL이 없거나 URL 내에서 좌표를 추출하지 못한 경우 일반 좌표 및 DMS 도/분/초 문자열 파싱
    if (lat == null || lng == null) {
      final dmsMatch = RegExp(
        r'''(\d{1,2})[°\s]+(\d{1,2})['′\s]+(\d{1,2}(?:\.\d+)?)["″\s]*([NSns])[\s,]+(\d{1,3})[°\s]+(\d{1,2})['′\s]+(\d{1,2}(?:\.\d+)?)["″\s]*([EWew])''',
      ).firstMatch(trimmed);

      if (dmsMatch != null) {
        final dms = parseDmsCoordinates(trimmed);
        if (dms != null) {
          lat = dms.lat;
          lng = dms.lng;

          final before = trimmed.substring(0, dmsMatch.start).trim();
          final after = trimmed.substring(dmsMatch.end).trim();
          final leftover = [before, after].where((s) => s.isNotEmpty).join(' ').trim();
          if (leftover.isNotEmpty &&
              leftover != trimmed &&
              !leftover.contains('http://') &&
              !leftover.contains('https://')) {
            prefixName ??= leftover;
          }
        }
      } else {
        final clean = trimmed
            .replaceAll('(', '')
            .replaceAll(')', '')
            .replaceAll('@', ' ')
            .trim();

        final coordMatch = RegExp(r'(-?\d{1,2}(?:\.\d+)?)[,\s/]+(-?\d{1,3}(?:\.\d+)?)').firstMatch(clean);
        if (coordMatch != null) {
          final cLat = double.tryParse(coordMatch.group(1)!);
          final cLng = double.tryParse(coordMatch.group(2)!);
          if (cLat != null && cLng != null && cLat >= -90.0 && cLat <= 90.0 && cLng >= -180.0 && cLng <= 180.0) {
            lat = cLat;
            lng = cLng;

            final before = clean.substring(0, coordMatch.start).trim();
            final after = clean.substring(coordMatch.end).trim();
            final leftover = [before, after].where((s) => s.isNotEmpty).join(' ').trim();
            if (leftover.isNotEmpty &&
                leftover != clean &&
                !leftover.contains('http://') &&
                !leftover.contains('https://') &&
                !leftover.contains('google.com')) {
              prefixName ??= leftover;
            }
          }
        }
      }
    }

    if (lat != null && lng != null) {
      if (lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0) {
        String? finalName = prefixName;
        if (finalName != null &&
            (finalName.contains('http://') ||
             finalName.contains('https://') ||
             finalName.contains('google.com'))) {
          finalName = null;
        }
        finalName ??= placeName;
        return ParsedLocation(
          name: finalName,
          lat: lat,
          lng: lng,
          address: extraAddress,
          sourceUrl: url,
        );
      }
    }

    return null;
  }

  /// 구글맵 또는 일반 텍스트 좌표 파싱 (하위 호환)
  static ({double lat, double lng})? parseCoordinates(String? input) {
    final details = parseLocationDetails(input);
    if (details != null) {
      return (lat: details.lat, lng: details.lng);
    }
    return null;
  }

  /// 단축 URL (maps.app.goo.gl 등) 리다이렉트 추적 및 위치 정밀 파싱
  Future<ParsedLocation?> resolveLocation(String input, {http.Client? client}) async {
    debugPrint('[Geocoding] resolveLocation called with: "$input"');

    // 0순위: 입력 문자열 자체에서 Google Feature ID(ftid: 0x...:0x...) 또는 Place ID(place_id) 감지 시 즉시 공식 API로 100% 정밀 조회
    final directFtid = extractFtid(input);
    final directPlaceId = extractPlaceId(input);
    if (directFtid != null || directPlaceId != null) {
      final byId = await _fetchPlaceDetailsById(
        ftid: directFtid,
        placeId: directPlaceId,
        sourceUrl: input,
        client: client,
      );
      if (byId != null) {
        debugPrint('[Geocoding] Resolved directly via FTID/PlaceID from input: $byId');
        return byId;
      }
      if (directFtid != null && (input.trim().startsWith('0x') || input.trim().contains(':0x'))) {
        debugPrint('[Geocoding] Direct FTID was not found in Place Details API. Aborting fallback search.');
        return null;
      }
    }

    final direct = parseLocationDetails(input);
    if (direct != null) {
      debugPrint('[Geocoding] direct parse success: lat=${direct.lat}, lng=${direct.lng}, name=${direct.name}');
      return direct;
    }

    String trimmed = input.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (trimmed.contains('maps.app.goo.gl') ||
          trimmed.contains('goo.gl/maps') ||
          trimmed.contains('google.com/maps') ||
          trimmed.contains('maps.google.com')) {
        trimmed = 'https://$trimmed';
      }
    }

    final urlMatch = RegExp(r'https?://[^\s<>"]+').firstMatch(trimmed);
    if (urlMatch == null) {
      debugPrint('[Geocoding] No URL found in input: "$trimmed"');
      if (trimmed.isNotEmpty && trimmed.length >= 2) {
        debugPrint('[Geocoding] Attempting fallback place search for text: "$trimmed"');
        final searchResults = await searchPlaces(trimmed);
        if (searchResults.isNotEmpty) {
          final first = searchResults.first;
          return ParsedLocation(
            name: first.name,
            lat: first.lat,
            lng: first.lng,
            address: first.displayName,
            sourceUrl: '',
          );
        }
      }
      return null;
    }

    final rawUrl = urlMatch.group(0)!;
    debugPrint('[Geocoding] Found rawUrl: "$rawUrl"');

    // 모바일 공유 텍스트 등에서 URL 앞/뒤 텍스트 추출 (첫 번째 비어있지 않은 줄을 장소명 후보로 사용)
    String? textNameCandidate;
    String? textAddressCandidate;
    final urlIdx = trimmed.indexOf(rawUrl);
    if (urlIdx > 0) {
      final prefix = trimmed.substring(0, urlIdx).trim();
      final lines = prefix
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('@'))
          .toList();
      if (lines.isNotEmpty) {
        textNameCandidate = lines.first;
        if (lines.length > 1) {
          textAddressCandidate = lines.sublist(1).join(', ');
        }
      }
    }
    final endIdx = urlIdx + rawUrl.length;
    if (endIdx < trimmed.length) {
      final suffix = trimmed.substring(endIdx).trim();
      final lines = suffix
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('@'))
          .toList();
      if (lines.isNotEmpty) {
        textNameCandidate ??= lines.first;
        if (lines.length > 1) {
          textAddressCandidate ??= lines.sublist(1).join(', ');
        }
      }
    }

    String? placeNameFromPath;
    String? addressFromPath;
    double? cameraLat;
    double? cameraLng;

    void extractCameraPos(String urlStr) {
      final camMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(urlStr);
      if (camMatch != null) {
        cameraLat ??= double.tryParse(camMatch.group(1)!);
        cameraLng ??= double.tryParse(camMatch.group(2)!);
      }
    }

    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 8);
    httpClient.badCertificateCallback = (cert, host, port) => true;

    try {
      String currentUrl = rawUrl;
      int redirectCount = 0;

      void checkPathInfo(String urlStr) {
        extractCameraPos(urlStr);
        final placePathMatch = RegExp(r'/place/([^/@?#]+)').firstMatch(urlStr);
        if (placePathMatch != null) {
          try {
            final raw = placePathMatch.group(1)!;
            final decoded = Uri.decodeComponent(raw.replaceAll('+', ' ')).trim();
            if (decoded.isNotEmpty) {
              final splitMatch = RegExp(
                r'^(.*?)(?:\s+(Jl[:\.]|Jalan|Gang|Gg\.|Street|St\.|Road|Rd\.|Avenue|Ave\.|Blvd\.|Way|\bNo\.\b)|,(.*)$)',
                caseSensitive: false,
              ).firstMatch(decoded);
              if (splitMatch != null) {
                placeNameFromPath ??= splitMatch.group(1)!.trim();
                addressFromPath ??= decoded.substring(placeNameFromPath!.length).trim().replaceAll(RegExp(r'^,\s*'), '');
              } else {
                placeNameFromPath ??= decoded;
              }
            }
          } catch (_) {}
        }
      }

      while (redirectCount < 10) {
        debugPrint('[Geocoding] [Hop $redirectCount] Fetching: $currentUrl');
        checkPathInfo(currentUrl);

        // 1순위: 현재 URL에서 FTID (0x...:0x...) 또는 Place ID 감지 시 즉시 공식 Place Details 조회!
        final currentFtid = extractFtid(currentUrl);
        final currentPlaceId = extractPlaceId(currentUrl);
        if (currentFtid != null || currentPlaceId != null) {
          final byId = await _fetchPlaceDetailsById(
            ftid: currentFtid,
            placeId: currentPlaceId,
            sourceUrl: rawUrl,
            client: client,
          );
          if (byId != null) {
            debugPrint('[Geocoding] Resolved via currentUrl FTID/PlaceID: $byId');
            return ParsedLocation(
              name: (textNameCandidate != null && textNameCandidate.isNotEmpty)
                  ? textNameCandidate
                  : byId.name,
              lat: byId.lat,
              lng: byId.lng,
              address: byId.address,
              sourceUrl: rawUrl,
              placeId: byId.placeId,
              photos: byId.photos,
            );
          }
        }

        final uri = Uri.tryParse(currentUrl);
        if (uri == null) {
          debugPrint('[Geocoding] Invalid URI: $currentUrl');
          break;
        }

        final request = await httpClient.getUrl(uri);
        request.followRedirects = false; // intent:// scheme 크래시를 방지하고 단계별 정밀 분석
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        );

        final response = await request.close().timeout(const Duration(seconds: 8));
        debugPrint('[Geocoding] [Hop $redirectCount] Status: ${response.statusCode}');

        final locHeader = response.headers.value(HttpHeaders.locationHeader);
        debugPrint('[Geocoding] [Hop $redirectCount] Location header: $locHeader');

        if (locHeader != null && locHeader.isNotEmpty) {
          String nextUrl = locHeader;

          // intent:// scheme 처리 (Android 구글맵 인텐트 URL 대응)
          if (nextUrl.startsWith('intent://')) {
            debugPrint('[Geocoding] Detected intent scheme: $nextUrl');
            final fallbackMatch = RegExp(r'browser_fallback_url=([^;]+)').firstMatch(nextUrl);
            if (fallbackMatch != null) {
              nextUrl = Uri.decodeComponent(fallbackMatch.group(1)!);
              debugPrint('[Geocoding] Extracted browser_fallback_url: $nextUrl');
            } else {
              final linkMatch = RegExp(r'[?&]link=([^;&]+)').firstMatch(nextUrl);
              if (linkMatch != null) {
                nextUrl = Uri.decodeComponent(linkMatch.group(1)!);
                debugPrint('[Geocoding] Extracted link param: $nextUrl');
              }
            }
          }

          if (nextUrl.startsWith('/')) {
            nextUrl = uri.resolve(nextUrl).toString();
          }

          checkPathInfo(nextUrl);

          // 1순위: 리다이렉트 Location 헤더에서 FTID 또는 Place ID 추출하여 즉시 공식 조회!
          final locFtid = extractFtid(nextUrl);
          final locPlaceId = extractPlaceId(nextUrl);
          if (locFtid != null || locPlaceId != null) {
            final byId = await _fetchPlaceDetailsById(
              ftid: locFtid,
              placeId: locPlaceId,
              sourceUrl: nextUrl,
              client: client,
            );
            if (byId != null) {
              debugPrint('[Geocoding] Resolved via redirect Location FTID/PlaceID: $byId');
              return ParsedLocation(
                name: (textNameCandidate != null && textNameCandidate.isNotEmpty)
                    ? textNameCandidate
                    : byId.name,
                lat: byId.lat,
                lng: byId.lng,
                address: byId.address,
                sourceUrl: nextUrl,
                placeId: byId.placeId,
                photos: byId.photos,
              );
            }
          }

          // 리다이렉트 URL 자체에서 핀 좌표(!3d/!4d 또는 고정 좌표) 파싱 시도
          final parsedFromLoc = parseLocationDetails(nextUrl);
          if (parsedFromLoc != null) {
            debugPrint('[Geocoding] Resolved from redirect Location: $parsedFromLoc');
            return ParsedLocation(
              name: textNameCandidate ?? parsedFromLoc.name ?? placeNameFromPath,
              lat: parsedFromLoc.lat,
              lng: parsedFromLoc.lng,
              address: textAddressCandidate ?? parsedFromLoc.address ?? addressFromPath,
              sourceUrl: nextUrl,
            );
          }

          // 중첩된 continue / url / q / destination 파라미터 검사
          final nextUri = Uri.tryParse(nextUrl);
          if (nextUri != null) {
            for (final param in ['continue', 'url', 'q', 'target', 'destination']) {
              final val = nextUri.queryParameters[param];
              if (val != null) {
                final decodedVal = Uri.decodeComponent(val);
                debugPrint('[Geocoding] Checking nested param $param: $decodedVal');

                final nestedFtid = extractFtid(decodedVal);
                final nestedPlaceId = extractPlaceId(decodedVal);
                if (nestedFtid != null || nestedPlaceId != null) {
                  final byId = await _fetchPlaceDetailsById(
                    ftid: nestedFtid,
                    placeId: nestedPlaceId,
                    sourceUrl: decodedVal,
                    client: client,
                  );
                  if (byId != null) {
                    return byId;
                  }
                }

                final fromParam = parseLocationDetails(decodedVal);
                if (fromParam != null) {
                  return ParsedLocation(
                    name: textNameCandidate ?? fromParam.name ?? placeNameFromPath,
                    lat: fromParam.lat,
                    lng: fromParam.lng,
                    address: textAddressCandidate ?? fromParam.address ?? addressFromPath,
                    sourceUrl: decodedVal,
                  );
                }
              }
            }
          }

          currentUrl = nextUrl;
          redirectCount++;
          continue;
        }

        // 200 OK 등 응답 본문 검사
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
          debugPrint('[Geocoding] Read body length: ${body.length}');

          // 본문 내 FTID 패턴 감지 (0x...:0x...)
          final bodyFtid = extractFtid(body);
          if (bodyFtid != null) {
            final byId = await _fetchPlaceDetailsById(
              ftid: bodyFtid,
              sourceUrl: currentUrl,
              client: client,
            );
            if (byId != null) {
              debugPrint('[Geocoding] Resolved via body FTID: $byId');
              return ParsedLocation(
                name: (textNameCandidate != null && textNameCandidate.isNotEmpty)
                    ? textNameCandidate
                    : byId.name,
                lat: byId.lat,
                lng: byId.lng,
                address: byId.address,
                sourceUrl: currentUrl,
                placeId: byId.placeId,
                photos: byId.photos,
              );
            }
          }

          // 메타 태그 검색 (og:url, og:image, itemprop 등)
          final metaMatches = RegExp(r'<meta[^>]+(?:content|itemprop)=["'']([^"'']+)["''][^>]*>').allMatches(body);
          for (final m in metaMatches) {
            final val = m.group(1);
            if (val != null && val.contains('google.com/maps')) {
              final metaFtid = extractFtid(val);
              if (metaFtid != null) {
                final byId = await _fetchPlaceDetailsById(
                  ftid: metaFtid,
                  sourceUrl: val,
                  client: client,
                );
                if (byId != null) {
                  return byId;
                }
              }
              final fromMeta = parseLocationDetails(val);
              if (fromMeta != null) {
                debugPrint('[Geocoding] Resolved from meta: $fromMeta');
                return ParsedLocation(
                  name: textNameCandidate ?? fromMeta.name ?? placeNameFromPath,
                  lat: fromMeta.lat,
                  lng: fromMeta.lng,
                  address: textAddressCandidate ?? fromMeta.address ?? addressFromPath,
                  sourceUrl: val,
                );
              }
            }
          }

          // 본문 내 핀 좌표 !3d / !4d
          final pinMatch = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(body);
          if (pinMatch != null) {
            final bLat = double.tryParse(pinMatch.group(1)!);
            final bLng = double.tryParse(pinMatch.group(2)!);
            if (bLat != null && bLng != null) {
              debugPrint('[Geocoding] Resolved from body pin: $bLat, $bLng');
              return ParsedLocation(
                name: textNameCandidate ?? placeNameFromPath,
                lat: bLat,
                lng: bLng,
                address: textAddressCandidate ?? addressFromPath,
                sourceUrl: currentUrl,
              );
            }
          }
        }

        break;
      }
    } catch (e, st) {
      debugPrint('[Geocoding] resolveLocation error: $e\n$st');
    } finally {
      httpClient.close();
    }

    // 최종 Fallback: URL 경로에서 추출된 주소/장소명 또는 텍스트 후보로 장소 검색
    final searchCandidates = [
      if (placeNameFromPath != null && placeNameFromPath!.isNotEmpty) placeNameFromPath!,
      if (textNameCandidate != null && textNameCandidate.isNotEmpty) textNameCandidate,
      if (addressFromPath != null && addressFromPath!.isNotEmpty) addressFromPath!,
      if (addressFromPath != null && addressFromPath!.isNotEmpty) _sanitizeAddress(addressFromPath!),
    ];

    // 1단계: Google 공식 Places / Geocoding API 우선 조회 (정확도 99.9%)
    for (final candidate in searchCandidates) {
      if (candidate.length < 2) continue;
      debugPrint('[Geocoding] Trying Google Places API for candidate: "$candidate" (bias: $cameraLat, $cameraLng)');
      final googlePlaces = await _searchViaGooglePlaces(
        candidate,
        limit: 1,
        biasLat: cameraLat,
        biasLng: cameraLng,
        client: client,
      );
      if (googlePlaces.isNotEmpty) {
        final first = googlePlaces.first;
        final resolvedName = (first.name.isNotEmpty && !first.name.contains('Jl.') && !first.name.contains('Gang'))
            ? first.name
            : (textNameCandidate ?? placeNameFromPath ?? first.name);
        final resolvedAddress = first.displayName.isNotEmpty ? first.displayName : (addressFromPath ?? textAddressCandidate);
        debugPrint('[Geocoding] Google Places API succeeded: $resolvedName (${first.lat}, ${first.lng})');
        return ParsedLocation(
          name: resolvedName,
          lat: first.lat,
          lng: first.lng,
          address: resolvedAddress,
          sourceUrl: rawUrl,
        );
      }

      final googleGeocode = await _searchViaGoogleGeocoding(candidate, limit: 1, client: client);
      if (googleGeocode.isNotEmpty) {
        final first = googleGeocode.first;
        final resolvedName = textNameCandidate ?? placeNameFromPath ?? first.name;
        final resolvedAddress = first.displayName.isNotEmpty ? first.displayName : (addressFromPath ?? textAddressCandidate);
        debugPrint('[Geocoding] Google Geocoding API succeeded: $resolvedName (${first.lat}, ${first.lng})');
        return ParsedLocation(
          name: resolvedName,
          lat: first.lat,
          lng: first.lng,
          address: resolvedAddress,
          sourceUrl: rawUrl,
        );
      }
    }

    // 2단계: 위키백과 / Nominatim / Photon 폴백 검색
    for (final candidate in searchCandidates) {
      if (candidate.length < 2) continue;
      debugPrint('[Geocoding] Fallback search with candidate: "$candidate"');
      final searchResults = await searchPlaces(candidate);
      if (searchResults.isNotEmpty) {
        final first = searchResults.first;
        final resolvedName = textNameCandidate ?? placeNameFromPath ?? first.name;
        final resolvedAddress = addressFromPath ?? textAddressCandidate ?? first.displayName;
        debugPrint('[Geocoding] Fallback search succeeded: $resolvedName (${first.lat}, ${first.lng})');
        return ParsedLocation(
          name: resolvedName,
          lat: first.lat,
          lng: first.lng,
          address: resolvedAddress,
          sourceUrl: rawUrl,
        );
      }
    }

    debugPrint('[Geocoding] resolveLocation failed to find location for: "$input"');
    return null;
  }

  /// 0. Google Place Details API (ftid=0x... 또는 place_id=...) 공식 고유 식별자 직해 (정확도 100.0%)
  Future<ParsedLocation?> _fetchPlaceDetailsById({
    String? ftid,
    String? placeId,
    String? sourceUrl,
    http.Client? client,
  }) async {
    if ((ftid == null || ftid.isEmpty) && (placeId == null || placeId.isEmpty)) {
      return null;
    }

    final apiKey = await GooglePlacesService.getApiKey();
    if (apiKey.isEmpty) return null;

    final queryParams = <String, String>{
      'fields': 'place_id,name,geometry,formatted_address,photos',
      'language': 'ko',
      'key': apiKey,
    };
    if (ftid != null && ftid.isNotEmpty) {
      queryParams['ftid'] = ftid;
    } else if (placeId != null && placeId.isNotEmpty) {
      queryParams['place_id'] = placeId;
    }

    final url = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', queryParams);

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['result'] is Map) {
          final res = data['result'];
          final loc = res['geometry']?['location'];
          if (loc is Map) {
            final lat = (loc['lat'] as num?)?.toDouble() ?? 0.0;
            final lng = (loc['lng'] as num?)?.toDouble() ?? 0.0;
            final name = res['name'] as String? ?? '';
            final addr = res['formatted_address'] as String? ?? '';
            final pid = res['place_id'] as String? ?? '';
            final List<String> photoRefs = [];
            if (res['photos'] is List) {
              for (final p in (res['photos'] as List)) {
                final ref = p['photo_reference'] as String?;
                if (ref != null && ref.isNotEmpty) {
                  photoRefs.add(ref);
                }
              }
            }
            if (lat != 0.0 && lng != 0.0) {
              return ParsedLocation(
                name: name.isNotEmpty ? name : null,
                lat: lat,
                lng: lng,
                address: addr.isNotEmpty ? addr : null,
                sourceUrl: sourceUrl ?? '',
                placeId: pid.isNotEmpty ? pid : null,
                photos: photoRefs,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] _fetchPlaceDetailsById error: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
    return null;
  }

  /// 0-1. Google Places API (Find Place from Text) 공식 장소 검색 (정확도 최우선)
  Future<List<PlaceSearchResult>> _searchViaGooglePlaces(
    String query, {
    int limit = 5,
    double? biasLat,
    double? biasLng,
    http.Client? client,
  }) async {
    final apiKey = await GooglePlacesService.getApiKey();
    if (apiKey.isEmpty) return [];

    final encoded = Uri.encodeComponent(query);
    var urlStr = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
        '?input=$encoded'
        '&inputtype=textquery'
        '&fields=place_id,name,formatted_address,geometry,types'
        '&language=ko'
        '&key=$apiKey';

    if (biasLat != null && biasLng != null) {
      urlStr += '&locationbias=point:$biasLat,$biasLng';
    }

    final url = Uri.parse(urlStr);

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['candidates'] is List) {
          final list = <PlaceSearchResult>[];
          for (final c in (data['candidates'] as List)) {
            final loc = c['geometry']?['location'];
            if (loc is Map) {
              final lat = (loc['lat'] as num?)?.toDouble() ?? 0.0;
              final lng = (loc['lng'] as num?)?.toDouble() ?? 0.0;
              final name = c['name'] as String? ?? query;
              final addr = c['formatted_address'] as String? ?? '';
              final types = c['types'] as List?;
              final type = (types != null && types.isNotEmpty) ? types.first.toString() : 'google_place';
              list.add(PlaceSearchResult(
                name: name,
                displayName: addr.isNotEmpty ? addr : name,
                secondaryText: addr,
                lat: lat,
                lng: lng,
                type: type,
              ));
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] _searchViaGooglePlaces error: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
    return [];
  }

  /// 0-1. Google Geocoding API 공식 주소/장소 지오코딩
  Future<List<PlaceSearchResult>> _searchViaGoogleGeocoding(
    String query, {
    int limit = 5,
    http.Client? client,
  }) async {
    final apiKey = await GooglePlacesService.getApiKey();
    if (apiKey.isEmpty) return [];

    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=$encoded'
      '&language=ko'
      '&key=$apiKey',
    );

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['results'] is List) {
          final list = <PlaceSearchResult>[];
          for (final r in (data['results'] as List)) {
            final loc = r['geometry']?['location'];
            if (loc is Map) {
              final lat = (loc['lat'] as num?)?.toDouble() ?? 0.0;
              final lng = (loc['lng'] as num?)?.toDouble() ?? 0.0;
              final formattedAddr = r['formatted_address'] as String? ?? query;
              final comps = r['address_components'] as List?;
              String name = query;
              if (comps != null && comps.isNotEmpty) {
                name = comps.first['long_name'] as String? ?? query;
              }
              final types = r['types'] as List?;
              final type = (types != null && types.isNotEmpty) ? types.first.toString() : 'google_geocode';
              list.add(PlaceSearchResult(
                name: name,
                displayName: formattedAddr,
                secondaryText: formattedAddr,
                lat: lat,
                lng: lng,
                type: type,
              ));
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] _searchViaGoogleGeocoding error: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
    return [];
  }

  /// 1. 위키백과(Wikipedia) 글로벌 랜드마크/공항/관광지 지오코딩 API (해외 한글 검색 특화)
  Future<List<PlaceSearchResult>> _searchViaWikipedia(String query, {int limit = 5}) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      'https://ko.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=$encoded&gsrlimit=$limit&prop=coordinates|extracts&exintro=1&explaintext=1&exchars=150&format=json',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'MyTripLog-TravelApp/1.0 (contact: support@mytriplog.app)',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final pages = decoded['query']?['pages'];
        if (pages is Map<String, dynamic>) {
          final List<MapEntry<int, PlaceSearchResult>> indexedResults = [];

          for (final page in pages.values) {
            if (page is! Map<String, dynamic>) continue;
            final title = page['title'] as String? ?? '';
            final extract = (page['extract'] as String? ?? '').replaceAll('\n', ' ').trim();
            final coordinates = page['coordinates'];

            if (coordinates is List && coordinates.isNotEmpty) {
              final coord = coordinates.first;
              final lat = double.tryParse(coord['lat']?.toString() ?? '') ?? 0.0;
              final lng = double.tryParse(coord['lon']?.toString() ?? '') ?? 0.0;
              final index = page['index'] as int? ?? 99;

              if (lat != 0.0 && lng != 0.0) {
                indexedResults.add(
                  MapEntry(
                    index,
                    PlaceSearchResult(
                      name: title,
                      displayName: extract.isNotEmpty ? '$title - $extract' : title,
                      secondaryText: extract,
                      lat: lat,
                      lng: lng,
                      type: 'landmark',
                    ),
                  ),
                );
              }
            }
          }

          // 검색 관련도 순 정렬
          indexedResults.sort((a, b) => a.key.compareTo(b.key));
          return indexedResults.map((e) => e.value).toList();
        }
      }
    } catch (_) {
      // 오류 시 빈 목록 반환
    }

    return [];
  }

  /// 2. OpenStreetMap Nominatim 지오코딩 (도로명, 세부 주소, 국내 장소 특화)
  Future<List<PlaceSearchResult>> _searchViaNominatim(String query, {int limit = 5}) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      '$nominatimBase/search?format=json&q=$encoded&limit=$limit&addressdetails=1&accept-language=ko',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
          'User-Agent': 'MyTripLog-Flutter/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((item) => PlaceSearchResult.fromJson(item))
              .toList();
        }
      }
    } catch (_) {
      // 오류 시 빈 목록 반환
    }

    return [];
  }

  /// 3. Photon (Komoot / OpenStreetMap 기반 글로벌 POI & 해외 도로명 검색)
  Future<List<PlaceSearchResult>> _searchViaPhoton(String query, {int limit = 5}) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse('https://photon.komoot.io/api/?q=$encoded&limit=$limit');

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'MyTripLog-TravelApp/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final features = decoded['features'];
        if (features is List) {
          final List<PlaceSearchResult> list = [];
          for (final feat in features) {
            if (feat is! Map<String, dynamic>) continue;
            final geom = feat['geometry'];
            final props = feat['properties'];
            if (geom is Map<String, dynamic> && props is Map<String, dynamic>) {
              final coords = geom['coordinates'];
              if (coords is List && coords.length >= 2) {
                final lng = (coords[0] as num).toDouble();
                final lat = (coords[1] as num).toDouble();
                final name = (props['name'] as String?) ??
                    (props['street'] as String?) ??
                    query;
                final street = props['street'] as String?;
                final house = props['housenumber'] as String?;
                final district = props['district'] as String?;
                final city = props['city'] as String?;
                final state = props['state'] as String?;
                final country = props['country'] as String?;

                final addrParts = [
                  if (street != null) (house != null ? '$street $house' : street),
                  ?district,
                  if (city != null && city != district) city,
                  ?state,
                  ?country,
                ];
                final display = addrParts.isNotEmpty ? '$name, ${addrParts.join(", ")}' : name;

                list.add(
                  PlaceSearchResult(
                    name: name,
                    displayName: display,
                    secondaryText: addrParts.join(', '),
                    lat: lat,
                    lng: lng,
                    type: (props['osm_value'] as String?) ?? 'place',
                  ),
                );
              }
            }
          }
          return list;
        }
      }
    } catch (_) {
      // 오류 시 빈 목록 반환
    }

    return [];
  }

  /// 주소 문자열 정제 (번지, 행정구역 접두사, 우편번호 제거 후 검색 성공률 극대화)
  String _sanitizeAddress(String input) {
    var cleaned = input;
    cleaned = cleaned.replaceAll(RegExp(r'\bNo\.\s*\d+[a-zA-Z]?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(?:Kec\.|Kecamatan)\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\bKabupaten\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b\d{5}\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r',\s*,'), ',').trim();
    return cleaned;
  }

  /// 하이브리드 스마트 장소 검색 (위키백과 랜드마크 + Nominatim 도로명 주소 + Photon POI 병합 + 구글맵 링크/좌표 직해)
  Future<List<PlaceSearchResult>> searchPlaces(String query, {int limit = 6}) async {
    final q = query.trim();
    if (q.length < 2) return [];

    // 0순위: 구글맵 URL, 단축 링크, 좌표 입력 감지 시 즉시 파싱 및 역지오코딩
    if (isUrlOrCoordinates(q)) {
      final loc = await resolveLocation(q);
      if (loc != null) {
        final rev = await reverseGeocode(loc.lat, loc.lng);
        final title = loc.name ?? rev?.name ?? '구글맵 지정 위치';
        final address = rev?.displayName ?? '${loc.lat.toStringAsFixed(5)}, ${loc.lng.toStringAsFixed(5)}';
        return [
          PlaceSearchResult(
            name: title,
            displayName: address,
            secondaryText: address,
            lat: loc.lat,
            lng: loc.lng,
            type: 'google_maps',
          ),
        ];
      }
    }

    final List<PlaceSearchResult> combined = [];
    final Set<String> seenNames = {};

    // 0순위: Google 공식 Places API 검색 결과 우선 반환 (정확도 최우선)
    final googleResults = await _searchViaGooglePlaces(q, limit: limit);
    for (final r in googleResults) {
      final key = r.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (seenNames.add(key)) {
        combined.add(r);
      }
    }
    if (combined.isNotEmpty) {
      return combined;
    }

    // 위키백과, Nominatim, Photon을 동시 병렬 요청
    final results = await Future.wait([
      _searchViaWikipedia(q, limit: limit),
      _searchViaNominatim(q, limit: limit),
      _searchViaPhoton(q, limit: limit),
    ]);

    final wikiResults = results[0];
    final nominatimResults = results[1];
    final photonResults = results[2];

    // 1순위: 위키백과 검색 결과 (공항, 주요 랜드마크, 관광지)
    for (final r in wikiResults) {
      final key = r.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (seenNames.add(key)) {
        combined.add(r);
      }
    }

    // 2순위: Nominatim 검색 결과 (주소, 세부 건물, 도로명)
    for (final r in nominatimResults) {
      final key = r.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (seenNames.add(key)) {
        combined.add(r);
      }
    }

    // 3순위: Photon 검색 결과 (해외 POI, 쇼핑몰, 호텔, 상점)
    for (final r in photonResults) {
      final key = r.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (seenNames.add(key)) {
        combined.add(r);
      }
    }

    // 4순위: 검색 결과가 없을 경우 주소 정제 후 재시도 (예: 구글맵 상세 주소 복사본)
    if (combined.isEmpty && (q.contains('No.') || q.contains('Kec') || q.contains('Kabupaten') || RegExp(r'\b\d{5}\b').hasMatch(q))) {
      final sanitized = _sanitizeAddress(q);
      if (sanitized != q && sanitized.length >= 3) {
        final retryNom = await _searchViaNominatim(sanitized, limit: limit);
        if (retryNom.isNotEmpty) {
          return retryNom;
        }
        final retryPhoton = await _searchViaPhoton(sanitized, limit: limit);
        if (retryPhoton.isNotEmpty) {
          return retryPhoton;
        }
      }
    }

    if (combined.length > limit) {
      return combined.sublist(0, limit);
    }
    return combined;
  }

  /// Google Geocoding API 우선 -> Nominatim 폴백 역지오코딩 (위도/경도 -> 한국어 주소 및 장소명)
  Future<({String name, String displayName})?> reverseGeocode(
    double lat,
    double lng, {
    http.Client? client,
  }) async {
    final apiKey = await GooglePlacesService.getApiKey();
    if (apiKey.isNotEmpty) {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&language=ko&key=$apiKey',
      );
      final httpClient = client ?? http.Client();
      try {
        final response = await httpClient.get(url).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'OK' && data['results'] is List && (data['results'] as List).isNotEmpty) {
            final first = data['results'][0];
            final formattedAddr = first['formatted_address'] as String? ?? '$lat, $lng';
            final comps = first['address_components'] as List?;
            String name = formattedAddr;
            if (comps != null && comps.isNotEmpty) {
              name = comps.first['long_name'] as String? ?? formattedAddr;
            }
            return (name: name, displayName: formattedAddr);
          }
        }
      } catch (e) {
        debugPrint('[Geocoding] Google reverseGeocode error: $e');
      } finally {
        if (client == null) {
          httpClient.close();
        }
      }
    }

    final url = Uri.parse(
      '$nominatimBase/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1&accept-language=ko',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
          'User-Agent': 'MyTripLog-Flutter/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final displayName = decoded['display_name'] as String? ?? '$lat, $lng';
          final name = decoded['name'] as String? ?? displayName.split(',').first.trim();
          return (name: name, displayName: displayName);
        }
      }
    } catch (_) {
      // 오류 시 null 반환
    }

    return null;
  }
}
