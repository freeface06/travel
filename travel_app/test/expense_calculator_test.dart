/// @intent 다중 통화 환산, 지출 집계, 1/N 분담금, 그리디 최소 송금 정산 알고리즘 단위 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/services/expense_calculator.dart';

void main() {
  group('ExpenseCalculator - 통화 환산 (convertCurrency)', () {
    test('동일 통화 환산 시 반올림된 정수 반환', () {
      expect(ExpenseCalculator.convertCurrency(10000.4, fromCurrency: 'KRW', toCurrency: 'KRW'), 10000.0);
      expect(ExpenseCalculator.convertCurrency(50.0, fromCurrency: 'USD', toCurrency: 'USD'), 50.0);
    });

    test('0원 환산 시 0.0 반환', () {
      expect(ExpenseCalculator.convertCurrency(0.0, fromCurrency: 'USD', toCurrency: 'KRW'), 0.0);
    });

    test('USD to KRW 환산 (기본 환율 1350원 기준)', () {
      // 100 USD -> 100 * 1350 = 135,000 KRW
      final result = ExpenseCalculator.convertCurrency(100.0, fromCurrency: 'USD', toCurrency: 'KRW');
      expect(result, 135000.0);
    });

    test('KRW to USD 환산 (소수점 둘째 자리 반올림)', () {
      // 135,000 KRW -> 135000 / 1350 = 100.0 USD
      final result = ExpenseCalculator.convertCurrency(135000.0, fromCurrency: 'KRW', toCurrency: 'USD');
      expect(result, 100.0);
    });

    test('JPY to KRW 환산 (9.2원 기준)', () {
      // 1000 JPY -> 1000 * 9.2 = 9200 KRW
      final result = ExpenseCalculator.convertCurrency(1000.0, fromCurrency: 'JPY', toCurrency: 'KRW');
      expect(result, 9200.0);
    });
  });

  group('ExpenseCalculator - 1/N 분담금 (calculateIndividualShares)', () {
    test('원화(KRW) 3명 분담 시 단수(나머지) 분배 정확도 검증', () {
      // 10,000원을 3명이 나눌 경우: 3334원, 3333원, 3333원
      final shares = ExpenseCalculator.calculateIndividualShares(10000.0, ['철수', '영희', '민수'], currency: 'KRW');
      expect(shares['철수'], 3334.0);
      expect(shares['영희'], 3333.0);
      expect(shares['민수'], 3333.0);
      expect(shares.values.reduce((a, b) => a + b), 10000.0);
    });

    test('달러(USD) 3명 분담 시 센트 단위 분배 정확도 검증', () {
      // 10.00 USD를 3명이 나눌 경우: 3.34, 3.33, 3.33
      final shares = ExpenseCalculator.calculateIndividualShares(10.00, ['A', 'B', 'C'], currency: 'USD');
      expect(shares['A'], 3.34);
      expect(shares['B'], 3.33);
      expect(shares['C'], 3.33);
      expect((shares.values.reduce((a, b) => a + b) * 100).round() / 100, 10.00);
    });

    test('참가자가 없거나 금액이 0원일 때 안전 반환', () {
      expect(ExpenseCalculator.calculateIndividualShares(10000.0, [], currency: 'KRW'), isEmpty);
      final zeroShares = ExpenseCalculator.calculateIndividualShares(0.0, ['A', 'B'], currency: 'KRW');
      expect(zeroShares['A'], 0.0);
      expect(zeroShares['B'], 0.0);
    });
  });

  group('ExpenseCalculator - 지출 집계 및 정산 (calculateSettlements)', () {
    test('지출 집계 및 최소 송금 횟수 매칭 알고리즘 검증', () {
      // 철수: 60,000원 결제
      // 영희: 0원 결제
      // 민수: 0원 결제
      // 총액: 60,000원 -> 1인당 20,000원 분담
      // 영희 -> 철수 20,000원, 민수 -> 철수 20,000원 (총 2회 송금)
      final items = [
        const TripItem(id: '1', day: 1, title: '호텔', cost: 60000.0, currency: 'KRW', payer: '철수'),
      ];
      final participants = ['철수', '영희', '민수'];

      final summary = ExpenseCalculator.calculateSettlements(participants, items, baseCurrency: 'KRW');

      expect(summary.totalInBase, 60000.0);
      expect(summary.participantCount, 3);
      expect(summary.settlements.length, 2);

      final totalTransferred = summary.settlements.fold(0.0, (acc, s) => acc + s.amount);
      expect(totalTransferred, 40000.0);

      // 송금 대상은 모두 철수여야 함
      for (final s in summary.settlements) {
        expect(s.to, '철수');
        expect(s.amount, 20000.0);
      }
    });

    test('단일 참가자 또는 경비 0원 시 송금 내역 0건', () {
      final items = [
        const TripItem(id: '1', day: 1, title: '식사', cost: 15000.0, currency: 'KRW', payer: '나홀로'),
      ];
      final singleSummary = ExpenseCalculator.calculateSettlements(['나홀로'], items, baseCurrency: 'KRW');
      expect(singleSummary.settlements, isEmpty);

      final zeroSummary = ExpenseCalculator.calculateSettlements(['A', 'B'], [], baseCurrency: 'KRW');
      expect(zeroSummary.settlements, isEmpty);
    });
  });

  group('ExpenseCalculator - 포맷팅 (formatAmount)', () {
    test('통화별 금액 문자열 포맷팅 검증', () {
      expect(ExpenseCalculator.formatAmount(15000.0, 'KRW'), '15,000원');
      expect(ExpenseCalculator.formatAmount(3000.0, 'JPY'), '3,000엔');
      expect(ExpenseCalculator.formatAmount(12.5, 'USD'), '\$12.50');
      expect(ExpenseCalculator.formatAmount(45.0, 'EUR'), '€45,00');
    });
  });
}
