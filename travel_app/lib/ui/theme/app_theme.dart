/// @intent 앱 테마 스타일 및 일차별/카테고리별 컬러 팔레트와 메타데이터 정의
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';

class CategoryMeta {
  final String label;
  final IconData icon;
  final Color color;

  const CategoryMeta({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class AppTheme {
  // 테마 컬러 팔레트
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFFDBEAFE);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color cardShadow = Color(0x0A000000);

  // 일차별 고유 색상
  static Color getDayColor(int day) {
    switch (day) {
      case 1:
        return const Color(0xFF2563EB); // Blue
      case 2:
        return const Color(0xFF059669); // Emerald
      case 3:
        return const Color(0xFFD97706); // Amber
      case 4:
        return const Color(0xFFDB2777); // Pink
      case 5:
        return const Color(0xFF7C3AED); // Purple
      case 6:
        return const Color(0xFF0891B2); // Cyan
      default:
        return const Color(0xFF4B5563); // Slate
    }
  }

  // 카테고리 메타데이터
  static const Map<String, CategoryMeta> categories = {
    'FLIGHT': CategoryMeta(
      label: '비행기',
      icon: Icons.flight_takeoff,
      color: Color(0xFF2563EB),
    ),
    'AIRPORT': CategoryMeta(
      label: '공항',
      icon: Icons.local_airport,
      color: Color(0xFF0891B2),
    ),
    'HOTEL': CategoryMeta(
      label: '숙소',
      icon: Icons.hotel,
      color: Color(0xFF7C3AED),
    ),
    'ATTRACTION': CategoryMeta(
      label: '관광명소',
      icon: Icons.place,
      color: Color(0xFF059669),
    ),
    'DINING': CategoryMeta(
      label: '식당/카페',
      icon: Icons.restaurant,
      color: Color(0xFFD97706),
    ),
    'TRANSIT': CategoryMeta(
      label: '교통/이동',
      icon: Icons.directions_subway,
      color: Color(0xFF4B5563),
    ),
  };

  static CategoryMeta getCategoryMeta(String categoryKey) {
    return categories[categoryKey.toUpperCase()] ??
        const CategoryMeta(
          label: '기타',
          icon: Icons.category,
          color: Color(0xFF64748B),
        );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: Color(0xFF0D9488),
        surface: surface,
      ),
      fontFamily: null, // 시스템 기본 한글 글꼴
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: surface,
        elevation: 6,
        shadowColor: const Color(0x1E0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        textStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 0.8),
        ),
        elevation: 6,
      ),
      dividerColor: const Color(0xFFF1F5F9),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFF1F5F9),
        thickness: 0.8,
        space: 1.0,
      ),
    );
  }
}
