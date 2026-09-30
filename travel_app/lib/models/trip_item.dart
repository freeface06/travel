/// @intent 일정 아이템(TripItem) 도메인 모델 및 카테고리별 특화 필드 직렬화/역직렬화 정의 (Modified: photos 필드를 웹/Supabase Storage 규격인 객체 배열 및 photoDataUrl과 100% 호환되도록 toJson 직렬화 강화)
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

class TripItem {
  // 공통 기본 필드
  final String id;
  final int day;
  final String title;
  final String category;
  final double? lat;
  final double? lng;
  final String address;
  final double cost;
  final String currency;
  final String payer;
  final String memo;
  final String time;
  final List<String> photos;
  final String locationUrl;

  // 카테고리: FLIGHT
  final String flightType; // 'DEPARTURE' | 'ARRIVAL'
  final String airline;
  final String flightNo;
  final String airport;
  final String terminalGate;
  final String seat;
  final String bookingRef;

  // 카테고리: AIRPORT
  final String baggageClaim;
  final String transitToCity;
  final String pickupInfo;
  final String customsMemo;

  // 카테고리: HOTEL
  final String checkOutTime;
  final String voucherNo;
  final String passcode;
  final String luggageStorage;

  // 카테고리: ATTRACTION
  final String openingHours;
  final String bookingStatus;
  final double ticketCostPerPerson;
  final String tips;

  // 카테고리: DINING
  final String mealType;
  final String paymentMethod;
  final String reservedFor;
  final String menuRecommendation;

  // 카테고리: TRANSIT
  final String transitMode;
  final String departureStation;
  final String arrivalStation;
  final String transitLine;
  final String ticketOrSeat;
  final String transferMemo;

  const TripItem({
    required this.id,
    required this.day,
    required this.title,
    this.category = 'ATTRACTION',
    this.lat,
    this.lng,
    this.address = '',
    this.cost = 0.0,
    this.currency = 'KRW',
    this.payer = '공통',
    this.memo = '',
    this.time = '',
    this.photos = const [],
    this.locationUrl = '',
    this.flightType = 'DEPARTURE',
    this.airline = '',
    this.flightNo = '',
    this.airport = '',
    this.terminalGate = '',
    this.seat = '',
    this.bookingRef = '',
    this.baggageClaim = '',
    this.transitToCity = '',
    this.pickupInfo = '',
    this.customsMemo = '',
    this.checkOutTime = '',
    this.voucherNo = '',
    this.passcode = '',
    this.luggageStorage = '',
    this.openingHours = '',
    this.bookingStatus = '',
    this.ticketCostPerPerson = 0.0,
    this.tips = '',
    this.mealType = '',
    this.paymentMethod = '',
    this.reservedFor = '',
    this.menuRecommendation = '',
    this.transitMode = '',
    this.departureStation = '',
    this.arrivalStation = '',
    this.transitLine = '',
    this.ticketOrSeat = '',
    this.transferMemo = '',
  });

  bool get hasCoordinates => lat != null && lng != null;

  TripItem copyWith({
    String? id,
    int? day,
    String? title,
    String? category,
    double? lat,
    double? lng,
    String? address,
    double? cost,
    String? currency,
    String? payer,
    String? memo,
    String? time,
    List<String>? photos,
    String? locationUrl,
    String? flightType,
    String? airline,
    String? flightNo,
    String? airport,
    String? terminalGate,
    String? seat,
    String? bookingRef,
    String? baggageClaim,
    String? transitToCity,
    String? pickupInfo,
    String? customsMemo,
    String? checkOutTime,
    String? voucherNo,
    String? passcode,
    String? luggageStorage,
    String? openingHours,
    String? bookingStatus,
    double? ticketCostPerPerson,
    String? tips,
    String? mealType,
    String? paymentMethod,
    String? reservedFor,
    String? menuRecommendation,
    String? transitMode,
    String? departureStation,
    String? arrivalStation,
    String? transitLine,
    String? ticketOrSeat,
    String? transferMemo,
  }) {
    return TripItem(
      id: id ?? this.id,
      day: day ?? this.day,
      title: title ?? this.title,
      category: category ?? this.category,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      cost: cost ?? this.cost,
      currency: currency ?? this.currency,
      payer: payer ?? this.payer,
      memo: memo ?? this.memo,
      time: time ?? this.time,
      photos: photos ?? List<String>.from(this.photos),
      locationUrl: locationUrl ?? this.locationUrl,
      flightType: flightType ?? this.flightType,
      airline: airline ?? this.airline,
      flightNo: flightNo ?? this.flightNo,
      airport: airport ?? this.airport,
      terminalGate: terminalGate ?? this.terminalGate,
      seat: seat ?? this.seat,
      bookingRef: bookingRef ?? this.bookingRef,
      baggageClaim: baggageClaim ?? this.baggageClaim,
      transitToCity: transitToCity ?? this.transitToCity,
      pickupInfo: pickupInfo ?? this.pickupInfo,
      customsMemo: customsMemo ?? this.customsMemo,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      voucherNo: voucherNo ?? this.voucherNo,
      passcode: passcode ?? this.passcode,
      luggageStorage: luggageStorage ?? this.luggageStorage,
      openingHours: openingHours ?? this.openingHours,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      ticketCostPerPerson: ticketCostPerPerson ?? this.ticketCostPerPerson,
      tips: tips ?? this.tips,
      mealType: mealType ?? this.mealType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reservedFor: reservedFor ?? this.reservedFor,
      menuRecommendation: menuRecommendation ?? this.menuRecommendation,
      transitMode: transitMode ?? this.transitMode,
      departureStation: departureStation ?? this.departureStation,
      arrivalStation: arrivalStation ?? this.arrivalStation,
      transitLine: transitLine ?? this.transitLine,
      ticketOrSeat: ticketOrSeat ?? this.ticketOrSeat,
      transferMemo: transferMemo ?? this.transferMemo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'day': day,
      'title': title,
      'category': category,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'address': address,
      'cost': cost,
      'currency': currency,
      'payer': payer,
      'memo': memo,
      'time': time,
      'photos': photos
          .map((p) => {
                'id': 'photo-${photos.indexOf(p) + 1}',
                'dataUrl': p,
                'url': p,
                'filename': 'photo.jpg',
              })
          .toList(),
      if (photos.isNotEmpty) 'photoDataUrl': photos.first,
      if (photos.isNotEmpty) 'photoId': 'photo-1',
      if (locationUrl.isNotEmpty) 'locationUrl': locationUrl,
      'flightType': flightType,
      'airline': airline,
      'flightNo': flightNo,
      'airport': airport,
      'terminalGate': terminalGate,
      'seat': seat,
      'bookingRef': bookingRef,
      'baggageClaim': baggageClaim,
      'transitToCity': transitToCity,
      'pickupInfo': pickupInfo,
      'customsMemo': customsMemo,
      'checkOutTime': checkOutTime,
      'voucherNo': voucherNo,
      'passcode': passcode,
      'luggageStorage': luggageStorage,
      'openingHours': openingHours,
      'bookingStatus': bookingStatus,
      'ticketCostPerPerson': ticketCostPerPerson,
      'tips': tips,
      'mealType': mealType,
      'paymentMethod': paymentMethod,
      'reservedFor': reservedFor,
      'menuRecommendation': menuRecommendation,
      'transitMode': transitMode,
      'departureStation': departureStation,
      'arrivalStation': arrivalStation,
      'transitLine': transitLine,
      'ticketOrSeat': ticketOrSeat,
      'transferMemo': transferMemo,
    };
  }

  factory TripItem.fromJson(Map<String, dynamic> json) {
    double? parseCoord(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String && value.trim().isNotEmpty) {
        return double.tryParse(value.trim());
      }
      return null;
    }

    double parseAmount(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        final cleaned = value.replaceAll(',', '').trim();
        return double.tryParse(cleaned) ?? 0.0;
      }
      return 0.0;
    }

    List<String> parsePhotos(dynamic value, dynamic singleUrl) {
      final List<String> list = [];
      if (value is List) {
        for (final e in value) {
          if (e is Map) {
            final url = e['dataUrl'] ?? e['url'];
            if (url != null && url.toString().isNotEmpty) {
              list.add(url.toString());
            }
          } else if (e is String && e.isNotEmpty) {
            list.add(e);
          }
        }
      }
      if (list.isEmpty && singleUrl != null && singleUrl.toString().isNotEmpty) {
        list.add(singleUrl.toString());
      }
      return list;
    }

    return TripItem(
      id: json['id'] as String? ?? 'item-${DateTime.now().millisecondsSinceEpoch}',
      day: (json['day'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      category: (json['category'] as String? ?? 'ATTRACTION').toUpperCase(),
      lat: parseCoord(json['lat']),
      lng: parseCoord(json['lng']),
      address: json['address'] as String? ?? '',
      cost: parseAmount(json['cost']),
      currency: (json['currency'] as String? ?? 'KRW').toUpperCase(),
      payer: (json['payer'] as String?)?.trim() ?? '공통',
      memo: json['memo'] as String? ?? '',
      time: json['time'] as String? ?? '',
      photos: parsePhotos(json['photos'], json['photoDataUrl']),
      locationUrl: json['locationUrl'] as String? ?? json['link'] as String? ?? '',
      flightType: json['flightType'] as String? ?? 'DEPARTURE',
      airline: json['airline'] as String? ?? '',
      flightNo: json['flightNo'] as String? ?? '',
      airport: json['airport'] as String? ?? '',
      terminalGate: json['terminalGate'] as String? ?? '',
      seat: json['seat'] as String? ?? '',
      bookingRef: json['bookingRef'] as String? ?? '',
      baggageClaim: json['baggageClaim'] as String? ?? '',
      transitToCity: json['transitToCity'] as String? ?? '',
      pickupInfo: json['pickupInfo'] as String? ?? '',
      customsMemo: json['customsMemo'] as String? ?? '',
      checkOutTime: json['checkOutTime'] as String? ?? '',
      voucherNo: json['voucherNo'] as String? ?? '',
      passcode: json['passcode'] as String? ?? '',
      luggageStorage: json['luggageStorage'] as String? ?? '',
      openingHours: json['openingHours'] as String? ?? '',
      bookingStatus: json['bookingStatus'] as String? ?? '',
      ticketCostPerPerson: parseAmount(json['ticketCostPerPerson']),
      tips: json['tips'] as String? ?? '',
      mealType: json['mealType'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? '',
      reservedFor: json['reservedFor'] as String? ?? '',
      menuRecommendation: json['menuRecommendation'] as String? ?? '',
      transitMode: json['transitMode'] as String? ?? '',
      departureStation: json['departureStation'] as String? ?? '',
      arrivalStation: json['arrivalStation'] as String? ?? '',
      transitLine: json['transitLine'] as String? ?? '',
      ticketOrSeat: json['ticketOrSeat'] as String? ?? '',
      transferMemo: json['transferMemo'] as String? ?? '',
    );
  }
}
