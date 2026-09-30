/// @intent 여행 단위 도메인 모델(Trip: metadata + items) 및 직렬화/역직렬화 지원
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'trip_metadata.dart';
import 'trip_item.dart';

class Trip {
  final TripMetadata metadata;
  final List<TripItem> items;

  const Trip({
    required this.metadata,
    this.items = const [],
  });

  Trip copyWith({
    TripMetadata? metadata,
    List<TripItem>? items,
  }) {
    return Trip(
      metadata: metadata ?? this.metadata,
      items: items ?? List<TripItem>.from(this.items),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metadata': metadata.toJson(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['metadata'];
    final metaJson = rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : <String, dynamic>{};
    final rawItems = json['items'] as List<dynamic>? ?? [];

    return Trip(
      metadata: TripMetadata.fromJson(metaJson),
      items: rawItems
          .whereType<Map>()
          .map((itemMap) => TripItem.fromJson(Map<String, dynamic>.from(itemMap)))
          .toList(),
    );
  }

  static Trip defaultTrip() {
    return const Trip(
      metadata: TripMetadata(
        id: 'trip-my-first-trip',
        title: '나의 여행 계획',
        startDate: '',
        endDate: '',
        participants: ['신랑', '신부'],
        baseCurrency: 'KRW',
        customRates: {
          'KRW': 1.0,
          'USD': 1350.0,
          'JPY': 9.2,
          'EUR': 1460.0,
          'CNY': 185.0,
          'GBP': 1720.0,
        },
      ),
      items: [],
    );
  }
}
