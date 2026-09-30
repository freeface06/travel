/// @intent 실시간 천 단위 콤마(,) 자동 포맷팅 및 커서 위치 보존 TextInputFormatter
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // 숫자와 소수점(.) 이외의 문자(콤마 등) 모두 제거
    final cleanText = newValue.text.replaceAll(',', '');

    // 소수점이 2개 이상 들어오는 것 방지
    final dotCount = '.'.allMatches(cleanText).length;
    if (dotCount > 1) {
      return oldValue;
    }

    // 소수점 기준으로 분리
    final parts = cleanText.split('.');
    final integerPart = parts[0].replaceAll(RegExp(r'[^\d]'), '');
    final hasDecimal = parts.length > 1;
    final decimalPart = hasDecimal ? parts[1].replaceAll(RegExp(r'[^\d]'), '') : '';

    if (integerPart.isEmpty && !hasDecimal) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // 정수부 천 단위 콤마 포맷팅
    String formattedInteger = '';
    if (integerPart.isNotEmpty) {
      final parsed = int.tryParse(integerPart);
      if (parsed != null) {
        formattedInteger = _formatter.format(parsed);
      } else {
        formattedInteger = integerPart;
      }
    }

    // 새 텍스트 조합
    String formattedText = formattedInteger;
    if (hasDecimal) {
      formattedText += '.$decimalPart';
    }

    // 커서 위치 계산 (원본 커서 앞의 숫자 및 점의 개수를 세어 새 포맷팅 문자열에서 위치 매칭)
    final cursorOffset = newValue.selection.baseOffset;
    final textBeforeCursor = newValue.text.substring(0, cursorOffset.clamp(0, newValue.text.length));
    final nonCommaCharsBeforeCursor = textBeforeCursor.replaceAll(',', '').length;

    int newCursorOffset = 0;
    int nonCommaCount = 0;
    for (int i = 0; i < formattedText.length; i++) {
      if (formattedText[i] != ',') {
        nonCommaCount++;
      }
      if (nonCommaCount == nonCommaCharsBeforeCursor) {
        newCursorOffset = i + 1;
        break;
      }
    }

    if (nonCommaCount < nonCommaCharsBeforeCursor) {
      newCursorOffset = formattedText.length;
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newCursorOffset.clamp(0, formattedText.length)),
    );
  }
}
