/// @intent 모던 카드 스타일의 공통 팝업 다이얼로그(confirm, prompt, alert, showCustom)
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';

enum AppDialogType {
  primary,
  danger,
  warning,
  success,
}

class AppDialog {
  /// 확인/취소 2버튼 확인 팝업
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    AppDialogType type = AppDialogType.primary,
    IconData? icon,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogCtx) => _ModernCardDialogLayout(
        type: type,
        icon: icon,
        title: title,
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actions: [
          Expanded(
            child: _DialogButton(
              text: cancelText,
              isPrimary: false,
              type: type,
              onPressed: () => Navigator.of(dialogCtx).pop(false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DialogButton(
              text: confirmText,
              isPrimary: true,
              type: type,
              onPressed: () => Navigator.of(dialogCtx).pop(true),
            ),
          ),
        ],
      ),
    );
  }

  /// 텍스트 입력 프롬프트 팝업
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? message,
    String? initialValue,
    String? hintText,
    String confirmText = '확인',
    String cancelText = '취소',
    AppDialogType type = AppDialogType.primary,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final textController = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _ModernCardDialogLayout(
          type: type,
          icon: icon,
          title: title,
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message != null && message.isNotEmpty) ...[
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: textController,
                  keyboardType: keyboardType,
                  autofocus: true,
                  validator: validator,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                    ),
                  ),
                  onFieldSubmitted: (_) {
                    if (formKey.currentState?.validate() ?? true) {
                      Navigator.of(dialogCtx).pop(textController.text.trim());
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            Expanded(
              child: _DialogButton(
                text: cancelText,
                isPrimary: false,
                type: type,
                onPressed: () => Navigator.of(dialogCtx).pop(null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DialogButton(
                text: confirmText,
                isPrimary: true,
                type: type,
                onPressed: () {
                  if (formKey.currentState?.validate() ?? true) {
                    Navigator.of(dialogCtx).pop(textController.text.trim());
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 단순 알림 1버튼 팝업
  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    AppDialogType type = AppDialogType.primary,
    IconData? icon,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _ModernCardDialogLayout(
        type: type,
        icon: icon,
        title: title,
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actions: [
          Expanded(
            child: _DialogButton(
              text: confirmText,
              isPrimary: true,
              type: type,
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
          ),
        ],
      ),
    );
  }

  /// 커스텀 위젯을 감싸는 모던 카드 다이얼로그 래퍼
  static Future<T?> showCustom<T>(
    BuildContext context, {
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}

class _ModernCardDialogLayout extends StatelessWidget {
  final AppDialogType type;
  final IconData? icon;
  final String title;
  final Widget content;
  final List<Widget> actions;

  const _ModernCardDialogLayout({
    required this.type,
    this.icon,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final style = _getDialogStyle(type);
    final displayIcon = icon ?? style.defaultIcon;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 상단 56x56 아이콘 뱃지
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: style.badgeBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(
                  displayIcon,
                  color: style.badgeIconColor,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 다이얼로그 제목
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            // 콘텐츠 영역
            content,
            const SizedBox(height: 24),

            // 액션 버튼 영역 (높이 48dp, Row)
            Row(
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  _DialogTypeStyle _getDialogStyle(AppDialogType type) {
    switch (type) {
      case AppDialogType.danger:
        return const _DialogTypeStyle(
          badgeBgColor: Color(0xFFFEE2E2),
          badgeIconColor: Color(0xFFEF4444),
          buttonColor: Color(0xFFEF4444),
          defaultIcon: Icons.warning_amber_rounded,
        );
      case AppDialogType.warning:
        return const _DialogTypeStyle(
          badgeBgColor: Color(0xFFFEF3C7),
          badgeIconColor: Color(0xFFD97706),
          buttonColor: Color(0xFFD97706),
          defaultIcon: Icons.error_outline_rounded,
        );
      case AppDialogType.success:
        return const _DialogTypeStyle(
          badgeBgColor: Color(0xFFDCFCE7),
          badgeIconColor: Color(0xFF16A34A),
          buttonColor: Color(0xFF16A34A),
          defaultIcon: Icons.check_circle_outline_rounded,
        );
      case AppDialogType.primary:
        return const _DialogTypeStyle(
          badgeBgColor: Color(0xFFEFF6FF),
          badgeIconColor: Color(0xFF2563EB),
          buttonColor: Color(0xFF2563EB),
          defaultIcon: Icons.info_outline_rounded,
        );
    }
  }
}

class _DialogTypeStyle {
  final Color badgeBgColor;
  final Color badgeIconColor;
  final Color buttonColor;
  final IconData defaultIcon;

  const _DialogTypeStyle({
    required this.badgeBgColor,
    required this.badgeIconColor,
    required this.buttonColor,
    required this.defaultIcon,
  });
}

class _DialogButton extends StatelessWidget {
  final String text;
  final bool isPrimary;
  final AppDialogType type;
  final VoidCallback onPressed;

  const _DialogButton({
    required this.text,
    required this.isPrimary,
    required this.type,
    required this.onPressed,
  });

  Color _getPrimaryColor() {
    switch (type) {
      case AppDialogType.danger:
        return const Color(0xFFEF4444);
      case AppDialogType.warning:
        return const Color(0xFFD97706);
      case AppDialogType.success:
        return const Color(0xFF16A34A);
      case AppDialogType.primary:
        return const Color(0xFF2563EB);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isPrimary) {
      return SizedBox(
        height: 48,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final btnColor = _getPrimaryColor();

    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: btnColor.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
