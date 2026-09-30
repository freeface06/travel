/// @intent 여행 모델(Trip, TripMetadata, TripItem)의 직렬화/역직렬화 및 카테고리 특화 필드 정합성 테스트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip.dart';
import 'package:travel_app/models/trip_item.dart';
import 'package:travel_app/models/trip_metadata.dart';

void main() {
  group('TripMetadata Model Test', () {
    test('TripMetadata toJson 및 fromJson 정합성 검증', () {
      const meta = TripMetadata(
        id: 'trip-101',
        title: '도쿄 힐링 여행',
        startDate: '2026-10-01',
        endDate: '2026-10-04',
        participants: ['민우', '수진'],
        baseCurrency: 'JPY',
        customRates: {'KRW': 1.0, 'JPY': 9.5},
      );

      final json = meta.toJson();
      final restored = TripMetadata.fromJson(json);

      expect(restored.id, meta.id);
      expect(restored.title, meta.title);
      expect(restored.startDate, meta.startDate);
      expect(restored.endDate, meta.endDate);
      expect(restored.participants, meta.participants);
      expect(restored.baseCurrency, meta.baseCurrency);
      expect(restored.customRates['JPY'], 9.5);
    });

    test('TripMetadata copyWith 불변 업데이트 검증', () {
      const meta = TripMetadata(id: '1', title: '원래 제목');
      final updated = meta.copyWith(title: '수정된 제목', baseCurrency: 'USD');

      expect(updated.id, '1');
      expect(updated.title, '수정된 제목');
      expect(updated.baseCurrency, 'USD');
      expect(meta.title, '원래 제목');
    });
  });

  group('TripItem Model Test - 6대 카테고리 특화 필드', () {
    test('FLIGHT 카테고리 특화 필드 직렬화/역직렬화', () {
      const item = TripItem(
        id: 'flight-1',
        day: 1,
        title: '도쿄행 비행기',
        category: 'FLIGHT',
        flightType: 'DEPARTURE',
        airline: '대한항공',
        flightNo: 'KE703',
        airport: 'ICN',
        terminalGate: 'T2 240번',
        seat: '28A',
        bookingRef: 'ABC1234',
        cost: 350000.0,
      );

      final json = item.toJson();
      final restored = TripItem.fromJson(json);

      expect(restored.airline, '대한항공');
      expect(restored.flightNo, 'KE703');
      expect(restored.airport, 'ICN');
      expect(restored.seat, '28A');
      expect(restored.bookingRef, 'ABC1234');
      expect(restored.cost, 350000.0);
    });

    test('HOTEL 카테고리 특화 필드 직렬화/역직렬화', () {
      const item = TripItem(
        id: 'hotel-1',
        day: 1,
        title: '신주쿠 프린스 호텔',
        category: 'HOTEL',
        checkOutTime: '11:00',
        voucherNo: 'AGODA-7788',
        passcode: '1234#',
        luggageStorage: '체크인 전 무료 가능',
      );

      final json = item.toJson();
      final restored = TripItem.fromJson(json);

      expect(restored.checkOutTime, '11:00');
      expect(restored.voucherNo, 'AGODA-7788');
      expect(restored.passcode, '1234#');
      expect(restored.luggageStorage, '체크인 전 무료 가능');
    });

    test('ATTRACTION, DINING, TRANSIT, AIRPORT 카테고리 특화 필드 검증', () {
      const attraction = TripItem(
        id: 'attr-1',
        day: 2,
        title: '시부야 스카이',
        category: 'ATTRACTION',
        openingHours: '10:00 - 22:00',
        bookingStatus: '사전 예매 완료',
        ticketCostPerPerson: 2200.0,
        tips: '일몰 30분 전 입장 추천',
      );
      final attrRestored = TripItem.fromJson(attraction.toJson());
      expect(attrRestored.openingHours, '10:00 - 22:00');
      expect(attrRestored.ticketCostPerPerson, 2200.0);
      expect(attrRestored.tips, '일몰 30분 전 입장 추천');

      const dining = TripItem(
        id: 'dining-1',
        day: 2,
        title: '이치란 라멘',
        category: 'DINING',
        mealType: '중식',
        paymentMethod: '현금',
        menuRecommendation: '돈코츠 라멘 기본',
      );
      final diningRestored = TripItem.fromJson(dining.toJson());
      expect(diningRestored.mealType, '중식');
      expect(diningRestored.paymentMethod, '현금');
      expect(diningRestored.menuRecommendation, '돈코츠 라멘 기본');

      const transit = TripItem(
        id: 'transit-1',
        day: 3,
        title: '신칸센 이동',
        category: 'TRANSIT',
        transitMode: '기차 (KTX/신칸센)',
        departureStation: '도쿄역',
        arrivalStation: '교토역',
        transitLine: '도카이도 신칸센 노조미',
        ticketOrSeat: '3호차 5B',
      );
      final transitRestored = TripItem.fromJson(transit.toJson());
      expect(transitRestored.departureStation, '도쿄역');
      expect(transitRestored.arrivalStation, '교토역');
      expect(transitRestored.ticketOrSeat, '3호차 5B');
    });

    test('TripItem 사진(photos) 필드 직렬화 및 웹 규격 상호 호환성 검증', () {
      const itemWithPhotos = TripItem(
        id: 'photo-item-1',
        day: 2,
        title: '발리 해변 카페',
        photos: [
          'https://qmqklwelrsmlsrmtnsxt.supabase.co/storage/v1/object/public/trip-photos/789.jpg',
          'data:image/jpeg;base64,/9j/4AAQSkZJRg...',
        ],
      );

      final json = itemWithPhotos.toJson();
      expect(json['photos'], isA<List>());
      expect((json['photos'] as List).length, 2);
      expect((json['photos'] as List)[0]['dataUrl'], 'https://qmqklwelrsmlsrmtnsxt.supabase.co/storage/v1/object/public/trip-photos/789.jpg');
      expect(json['photoDataUrl'], 'https://qmqklwelrsmlsrmtnsxt.supabase.co/storage/v1/object/public/trip-photos/789.jpg');

      final restored = TripItem.fromJson(json);
      expect(restored.photos.length, 2);
      expect(restored.photos[0], 'https://qmqklwelrsmlsrmtnsxt.supabase.co/storage/v1/object/public/trip-photos/789.jpg');
      expect(restored.photos[1], 'data:image/jpeg;base64,/9j/4AAQSkZJRg...');
    });
  });

  group('Trip Model Test', () {
    test('Trip.defaultTrip 기본 상태 검증', () {
      final trip = Trip.defaultTrip();
      expect(trip.metadata.title, '나의 여행 계획');
      expect(trip.items, isEmpty);
    });

    test('Trip 전체 직렬화 및 역직렬화', () {
      final trip = Trip(
        metadata: const TripMetadata(id: 'trip-main', title: '메인 여행'),
        items: const [
          TripItem(id: 'item-1', day: 1, title: '도착'),
          TripItem(id: 'item-2', day: 2, title: '관광'),
        ],
      );

      final json = trip.toJson();
      final restored = Trip.fromJson(json);

      expect(restored.metadata.id, 'trip-main');
      expect(restored.items.length, 2);
      expect(restored.items[0].title, '도착');
      expect(restored.items[1].title, '관광');
    });
  });
}
