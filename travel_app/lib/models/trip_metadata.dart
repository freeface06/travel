/// @intent 여행 메타데이터 도메인 모델 정의 및 직렬화/역직렬화 지원
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

class TripMetadata {
  final String id;
  final String title;
  final String startDate;
  final String endDate;
  final List<String> participants;
  final String baseCurrency;
  final Map<String, double> customRates;

  const TripMetadata({
    required this.id,
    required this.title,
    this.startDate = '',
    this.endDate = '',
    this.participants = const ['신랑', '신부'],
    this.baseCurrency = 'KRW',
    this.customRates = const {
      'KRW': 1.0,
      'USD': 1350.0,
      'JPY': 9.2,
      'EUR': 1460.0,
      'CNY': 185.0,
      'GBP': 1720.0,
    },
  });

  TripMetadata copyWith({
    String? id,
    String? title,
    String? startDate,
    String? endDate,
    List<String>? participants,
    String? baseCurrency,
    Map<String, double>? customRates,
  }) {
    return TripMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      participants: participants ?? List<String>.from(this.participants),
      baseCurrency: baseCurrency ?? this.baseCurrency,
      customRates: customRates ?? Map<String, double>.from(this.customRates),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDate': startDate,
      'endDate': endDate,
      'participants': participants,
      'baseCurrency': baseCurrency,
      'customRates': customRates,
    };
  }

  factory TripMetadata.fromJson(Map<String, dynamic> json) {
    final rawRates = json['customRates'];
    final Map<String, double> parsedRates = {
      'KRW': 1.0,
      'USD': 1350.0,
      'JPY': 9.2,
      'EUR': 1460.0,
      'CNY': 185.0,
      'GBP': 1720.0,
    };

    if (rawRates is Map) {
      rawRates.forEach((k, v) {
        if (v is num) {
          parsedRates[k.toString().toUpperCase()] = v.toDouble();
        }
      });
    }

    final rawParticipants = json['participants'];
    List<String> parsedParticipants = ['신랑', '신부'];
    if (rawParticipants is List) {
      final list = rawParticipants.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (list.isNotEmpty) {
        parsedParticipants = list;
      }
    }

    return TripMetadata(
      id: json['id'] as String? ?? 'trip-my-first-trip',
      title: json['title'] as String? ?? '나의 여행 계획',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      participants: parsedParticipants,
      baseCurrency: (json['baseCurrency'] as String? ?? 'KRW').toUpperCase(),
      customRates: parsedRates,
    );
  }
}
