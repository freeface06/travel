/// @intent 구글맵 시스템 공유 인텐트 수신 및 스마트 클립보드 자동 감지 서비스
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// 구글맵 공유 인텐트 및 클립보드 장소 링크 감지 서비스
class QuickImportService {
  QuickImportService._internal();
  static final QuickImportService instance = QuickImportService._internal();
  factory QuickImportService() => instance;

  // 구글맵 URL 정규식 패턴 (단축 URL 및 일반 URL)
  static final RegExp googleMapsUrlRegex = RegExp(
    r'https?://(?:(?:maps\.app\.goo\.gl|goo\.gl/maps|www\.google\.[a-z.]+/maps|maps\.google\.[a-z.]+|google\.[a-z.]+/maps)[^\s<>"]*)',
    caseSensitive: false,
  );

  // 이벤트 스트림 컨트롤러 (Broadcast)
  final StreamController<String> _placeUrlController = StreamController<String>.broadcast();
  Stream<String> get onPlaceUrlDetected => _placeUrlController.stream;

  // 클립보드 및 인텐트 중복 감지 방지 가드
  String? _lastProcessedUrl;
  DateTime? _lastProcessedTime;
  static const Duration cooldownDuration = Duration(seconds: 15);

  StreamSubscription<List<SharedMediaFile>>? _intentSubscription;
  bool _isInitialized = false;

  /// 서비스 초기화: 시스템 공유 인텐트 리스너 등록 및 앱 시작 시 전달된 초기 공유 데이터 확인
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // 1. 앱 실행 중(백그라운드 -> 포그라운드 포함) 공유 인텐트 스트림 리스너
      _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> files) {
          _handleSharedMediaFiles(files);
        },
        onError: (err) {
          debugPrint('[QuickImportService] getMediaStream 에러: $err');
        },
      );

      // 2. 앱이 종료된 상태에서 공유를 통해 열렸을 때의 초기 데이터 수신
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedMediaFiles(files);
          ReceiveSharingIntent.instance.reset();
        }
      }).catchError((err) {
        debugPrint('[QuickImportService] getInitialMedia 에러: $err');
      });
    } catch (e) {
      debugPrint('[QuickImportService] 인텐트 초기화 예외 (테스트 환경 또는 데스크톱 환경): $e');
    }
  }

  /// 공유된 SharedMediaFile 목록에서 텍스트 및 구글맵 링크 추출
  void _handleSharedMediaFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    for (final file in files) {
      final text = file.path.trim();
      if (text.isNotEmpty && isGoogleMapsContent(text)) {
        notifyDetectedUrl(text);
        break;
      }
    }
  }

  /// 텍스트 또는 클립보드 내용에서 구글맵 URL이 포함되어 있는지 확인
  static bool isGoogleMapsContent(String text) {
    if (text.trim().isEmpty) return false;
    final lower = text.toLowerCase();
    if (lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('maps.google.') ||
        (lower.contains('google.') && lower.contains('/maps'))) {
      return true;
    }
    return googleMapsUrlRegex.hasMatch(text);
  }

  /// 텍스트에서 첫 번째 구글맵 URL 추출 (없으면 null)
  static String? extractGoogleMapsUrl(String text) {
    if (text.trim().isEmpty) return null;
    final match = googleMapsUrlRegex.firstMatch(text);
    return match?.group(0);
  }

  /// 텍스트에서 구글맵 URL 이전 또는 이후의 장소명 힌트 텍스트 추출
  static String? extractPlaceNameHint(String text) {
    if (text.trim().isEmpty) return null;
    final url = extractGoogleMapsUrl(text);
    if (url == null) return null;

    final trimmed = text.trim();
    final idx = trimmed.indexOf(url);
    if (idx > 0) {
      final prefix = trimmed.substring(0, idx).trim();
      final lines = prefix.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) return lines.first;
    }

    final afterIdx = idx + url.length;
    if (afterIdx < trimmed.length) {
      final postfix = trimmed.substring(afterIdx).trim();
      final lines = postfix.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) return lines.first;
    }

    return null;
  }

  /// 스마트 클립보드 감지: 앱이 활성화(resumed)될 때 클립보드 텍스트를 검사하여 구글맵 링크 발견 시 알림
  Future<bool> checkClipboard({bool force = false}) async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();

      if (text == null || text.isEmpty) return false;

      if (!isGoogleMapsContent(text)) return false;

      // 쿨다운 및 중복 처리 가드
      final now = DateTime.now();
      if (!force && _lastProcessedUrl == text) {
        if (_lastProcessedTime != null && now.difference(_lastProcessedTime!) < cooldownDuration) {
          return false;
        }
      }

      _lastProcessedUrl = text;
      _lastProcessedTime = now;

      notifyDetectedUrl(text);
      return true;
    } catch (e) {
      debugPrint('[QuickImportService] checkClipboard 에러: $e');
      return false;
    }
  }

  /// 장소 감지 이벤트 발행 (중복 가드 갱신)
  void notifyDetectedUrl(String text) {
    _lastProcessedUrl = text;
    _lastProcessedTime = DateTime.now();
    _placeUrlController.add(text);
  }

  /// 사용자가 명시적으로 처리 완료 또는 닫았을 때 기록
  void markUrlProcessed(String url) {
    _lastProcessedUrl = url;
    _lastProcessedTime = DateTime.now();
  }

  /// 중복 가드 히스토리 초기화 (테스트용)
  void clearHistory() {
    _lastProcessedUrl = null;
    _lastProcessedTime = null;
  }

  /// 리소스 정리
  void dispose() {
    _intentSubscription?.cancel();
    _intentSubscription = null;
    _isInitialized = false;
  }
}
