/// @intent 모던 플로팅 토스트(Toss/iOS HUD 스타일) 알림 컴포넌트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';

/// 토스트 메시지 유형
enum AppToastType {
  success,
  warning,
  error,
  info,
}

/// 모던 플로팅 카드 형태의 스낵바 토스트 유틸리티
class AppToast {
  const AppToast._();

  /// 플로팅 토스트 표시
  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    IconData iconData;
    Color iconColor;

    switch (type) {
      case AppToastType.success:
        iconData = Icons.check_circle_rounded;
        iconColor = const Color(0xFF10B981);
        break;
      case AppToastType.warning:
        iconData = Icons.warning_amber_rounded;
        iconColor = const Color(0xFFFBBF24);
        break;
      case AppToastType.error:
        iconData = Icons.error_outline_rounded;
        iconColor = const Color(0xFFF87171);
        break;
      case AppToastType.info:
        iconData = Icons.info_rounded;
        iconColor = const Color(0xFF38BDF8);
        break;
    }

    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      duration: duration,
      content: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155), width: 0.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              iconData,
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// 성공 토스트
  static void success(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: AppToastType.success,
      duration: duration ?? const Duration(milliseconds: 2200),
    );
  }

  /// 경고 토스트
  static void warning(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: AppToastType.warning,
      duration: duration ?? const Duration(milliseconds: 2200),
    );
  }

  /// 에러 토스트
  static void error(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: AppToastType.error,
      duration: duration ?? const Duration(milliseconds: 2200),
    );
  }

  /// 정보 토스트
  static void info(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: AppToastType.info,
      duration: duration ?? const Duration(milliseconds: 2200),
    );
  }
}
