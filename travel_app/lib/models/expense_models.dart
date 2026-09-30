/// @intent 여행 경비 집계 및 1/N 정산 결과 데이터 모델 정의
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

class Settlement {
  final String from;
  final String to;
  final double amount;
  final String currency;

  const Settlement({
    required this.from,
    required this.to,
    required this.amount,
    required this.currency,
  });

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'amount': amount,
      'currency': currency,
    };
  }

  factory Settlement.fromJson(Map<String, dynamic> json) {
    return Settlement(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'KRW',
    );
  }
}

class MemberBalance {
  final String member;
  final double paid;
  final double share;
  final double net;

  const MemberBalance({
    required this.member,
    required this.paid,
    required this.share,
    required this.net,
  });

  Map<String, dynamic> toJson() {
    return {
      'member': member,
      'paid': paid,
      'share': share,
      'net': net,
    };
  }

  factory MemberBalance.fromJson(Map<String, dynamic> json) {
    return MemberBalance(
      member: json['member'] as String? ?? '',
      paid: (json['paid'] as num?)?.toDouble() ?? 0.0,
      share: (json['share'] as num?)?.toDouble() ?? 0.0,
      net: (json['net'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ExpenseSummary {
  final double totalInBase;
  final String baseCurrency;
  final Map<String, double> byCategory;
  final Map<String, double> byCurrency;
  final Map<String, double> paidByMember;
  final int participantCount;
  final List<MemberBalance> balances;
  final List<Settlement> settlements;

  const ExpenseSummary({
    required this.totalInBase,
    required this.baseCurrency,
    required this.byCategory,
    required this.byCurrency,
    required this.paidByMember,
    required this.participantCount,
    this.balances = const [],
    this.settlements = const [],
  });

  factory ExpenseSummary.empty([String baseCurrency = 'KRW']) {
    return ExpenseSummary(
      totalInBase: 0.0,
      baseCurrency: baseCurrency,
      byCategory: {},
      byCurrency: {},
      paidByMember: {},
      participantCount: 0,
      balances: [],
      settlements: [],
    );
  }
}
