/// @intent ThousandsSeparatorInputFormatter 실시간 콤마 포맷팅 및 커서 위치 단위 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/ui/widgets/thousands_separator_input_formatter.dart';

void main() {
  group('ThousandsSeparatorInputFormatter - 실시간 천 단위 콤마 포맷팅 검증', () {
    late ThousandsSeparatorInputFormatter formatter;

    setUp(() {
      formatter = ThousandsSeparatorInputFormatter();
    });

    test('3자리 이하 숫자는 콤마 없이 그대로 반환', () {
      final oldVal = TextEditingValue.empty;
      final newVal = const TextEditingValue(
        text: '500',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '500');
      expect(result.selection.baseOffset, 3);
    });

    test('4자리 이상 숫자 입력 시 자동으로 천 단위 콤마 추가 및 커서 위치 유지', () {
      final oldVal = const TextEditingValue(
        text: '100',
        selection: TextSelection.collapsed(offset: 3),
      );
      final newVal = const TextEditingValue(
        text: '1000',
        selection: TextSelection.collapsed(offset: 4),
      );
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '1,000');
      expect(result.selection.baseOffset, 5); // 1,000 뒤
    });

    test('대규모 금액(1,000,000) 연속 타이핑 시 실시간 다중 콤마 포맷팅 검증', () {
      var current = TextEditingValue.empty;
      const inputSequence = '1000000';
      for (int i = 0; i < inputSequence.length; i++) {
        final nextChar = inputSequence[i];
        final nextText = current.text + nextChar;
        final newVal = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
        current = formatter.formatEditUpdate(current, newVal);
      }
      expect(current.text, '1,000,000');
      expect(current.selection.baseOffset, 9);
    });

    test('소수점이 포함된 외화 금액(USD 등) 포맷팅 검증', () {
      final oldVal = const TextEditingValue(
        text: '1,500',
        selection: TextSelection.collapsed(offset: 5),
      );
      final newVal = const TextEditingValue(
        text: '1,500.50',
        selection: TextSelection.collapsed(offset: 8),
      );
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '1,500.50');
      expect(result.selection.baseOffset, 8);
    });

    test('중간에 숫자를 삽입할 때 커서가 올바른 위치를 유지하는지 검증', () {
      // 1,000의 '1' 뒤에 '2' 삽입 -> 12000 -> 12,000 (커서는 '2' 뒤인 인덱스 2)
      final oldVal = const TextEditingValue(
        text: '1,000',
        selection: TextSelection.collapsed(offset: 1),
      );
      final newVal = const TextEditingValue(
        text: '12,000',
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '12,000');
      expect(result.selection.baseOffset, 2);
    });

    test('빈 문자열 입력 시 안전하게 빈 문자열 반환', () {
      final oldVal = const TextEditingValue(
        text: '100',
        selection: TextSelection.collapsed(offset: 3),
      );
      final newVal = TextEditingValue.empty;
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '');
      expect(result.selection.baseOffset, 0);
    });
  });
}
