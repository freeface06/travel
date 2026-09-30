/// @intent 다중 통화 환율 환산, 지출 집계, 1/N 분담 및 그리디 최소 송금 횟수 정산 계산 엔진
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:math';
import 'package:intl/intl.dart';
import '../models/trip_item.dart';
import '../models/expense_models.dart';

class ExpenseCalculator {
  static const Map<String, double> defaultRates = {
    'KRW': 1.0,
    'USD': 1350.0,
    'JPY': 9.2,
    'EUR': 1460.0,
    'CNY': 185.0,
    'GBP': 1720.0,
  };

  /// 통화 환산 (KRW/JPY 정수 반올림, 외화 소수점 둘째 자리 반올림)
  static double convertCurrency(
    double amount, {
    String fromCurrency = 'KRW',
    String toCurrency = 'KRW',
    Map<String, double> customRates = const {},
  }) {
    if (amount == 0.0) return 0.0;

    final from = fromCurrency.toUpperCase().trim();
    final to = toCurrency.toUpperCase().trim();
    if (from == to) {
      return amount.roundToDouble();
    }

    final rates = Map<String, double>.from(defaultRates)..addAll(customRates);
    final fromRate = rates[from] ?? 1.0;
    final toRate = rates[to] ?? 1.0;

    final inKRW = amount * fromRate;
    final converted = inKRW / toRate;

    if (to == 'KRW' || to == 'JPY') {
      return converted.roundToDouble();
    }
    return (converted * 100).round() / 100.0;
  }

  /// 전체 여행 지출 집계 요약 계산
  static ExpenseSummary calculateExpenseSummary(
    List<TripItem> items,
    List<String> participants, {
    String baseCurrency = 'KRW',
    Map<String, double> customRates = const {},
  }) {
    final members = participants.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final baseCurr = baseCurrency.toUpperCase().trim();

    double totalInBase = 0.0;
    final Map<String, double> byCategory = {};
    final Map<String, double> byCurrency = {};
    final Map<String, double> paidByMember = {};

    for (final m in members) {
      paidByMember[m] = 0.0;
    }

    for (final item in items) {
      final rawCost = item.cost;
      if (rawCost <= 0) continue;

      final currency = (item.currency.isNotEmpty ? item.currency : baseCurr).toUpperCase();
      final payer = item.payer.trim().isNotEmpty
          ? item.payer.trim()
          : (members.isNotEmpty ? members.first : '공통');
      final category = (item.category.isNotEmpty ? item.category : 'OTHER').toUpperCase();

      final costInBase = convertCurrency(
        rawCost,
        fromCurrency: currency,
        toCurrency: baseCurr,
        customRates: customRates,
      );

      totalInBase += costInBase;
      byCategory[category] = (byCategory[category] ?? 0.0) + costInBase;
      byCurrency[currency] = (byCurrency[currency] ?? 0.0) + rawCost;
      paidByMember[payer] = (paidByMember[payer] ?? 0.0) + costInBase;
    }

    totalInBase = totalInBase.roundToDouble();

    // 카테고리별 및 지불인별 반올림 정돈
    byCategory.updateAll((key, val) => val.roundToDouble());
    byCurrency.updateAll((key, val) => val.roundToDouble());
    paidByMember.updateAll((key, val) => val.roundToDouble());

    return ExpenseSummary(
      totalInBase: totalInBase,
      baseCurrency: baseCurr,
      byCategory: byCategory,
      byCurrency: byCurrency,
      paidByMember: paidByMember,
      participantCount: members.length,
    );
  }

  /// 1/N 분담금 및 잔여 단수 분배
  static Map<String, double> calculateIndividualShares(
    double totalAmount,
    List<String> participants, {
    String currency = 'KRW',
  }) {
    final Map<String, double> shares = {};
    final members = participants.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final n = members.length;
    if (n == 0) return shares;

    if (totalAmount <= 0) {
      for (final m in members) {
        shares[m] = 0.0;
      }
      return shares;
    }

    final curr = currency.toUpperCase().trim();
    final isIntegerCurrency = curr == 'KRW' || curr == 'JPY';

    if (isIntegerCurrency) {
      final total = totalAmount.round();
      final baseShare = total ~/ n;
      final remainder = total - (baseShare * n);

      for (int i = 0; i < n; i++) {
        final m = members[i];
        if (i < remainder) {
          shares[m] = (baseShare + 1).toDouble();
        } else {
          shares[m] = baseShare.toDouble();
        }
      }
    } else {
      final totalCents = (totalAmount * 100).round();
      final baseCent = totalCents ~/ n;
      final remCent = totalCents - (baseCent * n);

      for (int i = 0; i < n; i++) {
        final m = members[i];
        final memberCents = i < remCent ? baseCent + 1 : baseCent;
        shares[m] = memberCents / 100.0;
      }
    }

    return shares;
  }

  /// 그리디 알고리즘 기반 최소 횟수 1/N 정산 송금 내역 산출
  static ExpenseSummary calculateSettlements(
    List<String> participants,
    List<TripItem> items, {
    String baseCurrency = 'KRW',
    Map<String, double> customRates = const {},
  }) {
    final distinctMembers = participants
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    final baseCurr = baseCurrency.toUpperCase().trim();
    final summary = calculateExpenseSummary(
      items,
      distinctMembers,
      baseCurrency: baseCurr,
      customRates: customRates,
    );

    if (distinctMembers.length <= 1 || summary.totalInBase <= 0) {
      final balances = distinctMembers.map((m) {
        final paid = summary.paidByMember[m] ?? 0.0;
        return MemberBalance(
          member: m,
          paid: paid,
          share: summary.totalInBase,
          net: 0.0,
        );
      }).toList();

      return ExpenseSummary(
        totalInBase: summary.totalInBase,
        baseCurrency: baseCurr,
        byCategory: summary.byCategory,
        byCurrency: summary.byCurrency,
        paidByMember: summary.paidByMember,
        participantCount: distinctMembers.length,
        balances: balances,
        settlements: const [],
      );
    }

    final shares = calculateIndividualShares(
      summary.totalInBase,
      distinctMembers,
      currency: baseCurr,
    );

    final List<MemberBalance> balances = distinctMembers.map((m) {
      final paid = summary.paidByMember[m] ?? 0.0;
      final share = shares[m] ?? 0.0;
      final net = paid - share;
      return MemberBalance(
        member: m,
        paid: paid,
        share: share,
        net: net,
      );
    }).toList();

    final List<_SettlementParty> debtors = [];
    final List<_SettlementParty> creditors = [];

    for (final b in balances) {
      if (b.net < -0.001) {
        debtors.add(_SettlementParty(member: b.member, amount: -b.net));
      } else if (b.net > 0.001) {
        creditors.add(_SettlementParty(member: b.member, amount: b.net));
      }
    }

    final List<Settlement> settlements = [];
    final isInteger = baseCurr == 'KRW' || baseCurr == 'JPY';

    while (debtors.isNotEmpty && creditors.isNotEmpty) {
      debtors.sort((a, b) => b.amount.compareTo(a.amount));
      creditors.sort((a, b) => b.amount.compareTo(a.amount));

      final debtor = debtors.first;
      final creditor = creditors.first;

      final transferAmount = min(debtor.amount, creditor.amount);
      final roundedAmount = isInteger
          ? transferAmount.roundToDouble()
          : (transferAmount * 100).round() / 100.0;

      if (roundedAmount > 0) {
        settlements.add(Settlement(
          from: debtor.member,
          to: creditor.member,
          amount: roundedAmount,
          currency: baseCurr,
        ));
      }

      debtor.amount -= transferAmount;
      creditor.amount -= transferAmount;

      if (debtor.amount <= 0.001) {
        debtors.removeAt(0);
      }
      if (creditor.amount <= 0.001) {
        creditors.removeAt(0);
      }
    }

    return ExpenseSummary(
      totalInBase: summary.totalInBase,
      baseCurrency: baseCurr,
      byCategory: summary.byCategory,
      byCurrency: summary.byCurrency,
      paidByMember: summary.paidByMember,
      participantCount: distinctMembers.length,
      balances: balances,
      settlements: settlements,
    );
  }

  /// 금액 포맷팅 문자열 생성
  static String formatAmount(double amount, [String currency = 'KRW']) {
    final curr = currency.toUpperCase().trim();
    if (curr == 'KRW') {
      final formatter = NumberFormat('#,###', 'ko_KR');
      return '${formatter.format(amount.round())}원';
    }
    if (curr == 'JPY') {
      final formatter = NumberFormat('#,###', 'ja_JP');
      return '${formatter.format(amount.round())}엔';
    }
    if (curr == 'USD') {
      final formatter = NumberFormat('#,##0.00', 'en_US');
      return '\$${formatter.format(amount)}';
    }
    if (curr == 'EUR') {
      final formatter = NumberFormat('#,##0.00', 'de_DE');
      return '€${formatter.format(amount)}';
    }
    final formatter = NumberFormat('#,##0.##');
    return '${formatter.format(amount)} $curr';
  }
}

class _SettlementParty {
  final String member;
  double amount;

  _SettlementParty({required this.member, required this.amount});
}
