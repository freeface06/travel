/**
 * @intent 중앙 상태 관리자(Store) - 옵저버 패턴 및 LocalStorage 영구 동기화
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripStore = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const STORAGE_KEY = 'mytriplog_trip_data_v1';

  // 6대 카테고리가 모두 포함된 신혼여행(Honeymoon) 초기 기본 샘플 일정
  const DEFAULT_TRIP = {
    metadata: {
      id: 'trip-honeymoon-2026',
      title: '우리의 로맨틱 신혼여행',
      startDate: '2026-10-15',
      endDate: '2026-10-20',
      participants: ['신랑', '신부'],
      baseCurrency: 'KRW',
      customRates: {
        KRW: 1.0,
        JPY: 9.2,
        USD: 1350.0,
        EUR: 1460.0
      }
    },
    items: [
      // Day 1: 비행기, 공항, 교통, 숙소, 식당
      {
        id: 'item-001',
        day: 1,
        category: 'FLIGHT',
        title: '인천 -> 나리타 에어서울 RS701',
        airline: '에어서울 (Air Seoul)',
        flightNo: 'RS701',
        departureAirport: 'ICN',
        arrivalAirport: 'NRT',
        departureTime: '08:40',
        arrivalTime: '11:15',
        terminalGate: 'T1 게이트 32',
        seat: '14A, 14B (신혼 커플석)',
        bookingRef: 'RS-998241',
        cost: 650000,
        currency: 'KRW',
        payer: '신랑',
        lat: 37.4602,
        lng: 126.4407,
        destLat: 35.7720,
        destLng: 140.3929,
        memo: '기내 반입 액체류 100ml 규정 준수 및 면세점 커플 링 수령'
      },
      {
        id: 'item-002',
        day: 1,
        category: 'AIRPORT',
        title: '나리타 국제공항 제1터미널',
        customsMemo: 'Visit Japan Web QR 코드 사전 준비 완료',
        baggageClaim: '수하물 수취대 6번',
        transitToCity: '스카이라이너 (Skyliner)',
        pickupInfo: '지하 1층 게이세이 티켓 창구 앞 (12:10 탑승)',
        cost: 0,
        currency: 'JPY',
        payer: '신부',
        lat: 35.7720,
        lng: 140.3929,
        memo: '스이카(Suica) 교통카드 모바일 충전 확인'
      },
      {
        id: 'item-003',
        day: 1,
        category: 'TRANSIT',
        title: '나리타공항 -> 닛포리역 스카이라이너',
        transitMode: '기차 (특급열차)',
        origin: '나리타공항 제1터미널역',
        destination: '닛포리역',
        time: '12:20',
        duration: '36분',
        platformMemo: '1번 승강장 4호차 커플석',
        cost: 5000,
        currency: 'JPY',
        payer: '공통',
        lat: 35.7278,
        lng: 139.7710,
        memo: '지정석 티켓 사전 교환 완료'
      },
      {
        id: 'item-004',
        day: 1,
        category: 'HOTEL',
        title: '호텔 그레이서리 신주쿠 (허니문 룸)',
        checkInTime: '15:00',
        checkOutTime: '11:00',
        address: '도쿄도 신주쿠구 카부키초 1-19-1 (호텔 그레이서리 신주쿠)',
        voucherNo: 'AGODA-771829',
        passcode: '키박스 4022#',
        luggageStorage: '체크인 전 무료 짐 보관 가능',
        cost: 420000,
        currency: 'KRW',
        payer: '공통',
        lat: 35.6953,
        lng: 139.7020,
        memo: '허니문 웰컴 과일 및 고층 시티뷰 배정 확인'
      },
      {
        id: 'item-005',
        day: 1,
        category: 'DINING',
        title: '이치란 라멘 신주쿠중앙원통로점',
        mealType: '석식',
        reservedFor: '현장 키오스크 발권',
        menuRecommendation: '천연 돈코츠 라멘 + 반숙란 + 차슈 추가',
        cost: 3200,
        currency: 'JPY',
        payer: '신랑',
        paymentMethod: '카드',
        lat: 35.6917,
        lng: 139.7032,
        memo: '신혼여행 첫날 저녁 식사, 둘이 함께 든든하게 즐기기'
      },

      // Day 2: 관광명소, 식당, 카페
      {
        id: 'item-006',
        day: 2,
        category: 'ATTRACTION',
        title: '메이지 신궁 & 요요기 공원 산책',
        time: '09:30',
        openingHours: '06:00 - 16:30',
        bookingStatus: '자유 관람 (입장료 무료)',
        ticketCostPerPerson: 0,
        tips: '아침 일찍 방문 시 울창한 삼나무 숲 피톤치드 둘만의 산책로 최고',
        cost: 0,
        currency: 'JPY',
        payer: '공통',
        lat: 35.6764,
        lng: 139.6993,
        memo: '신혼부부 소원 부적(에마) 구매 및 기념 촬영'
      },
      {
        id: 'item-007',
        day: 2,
        category: 'DINING',
        title: '오모테산도 우카이테이 (철판요리)',
        mealType: '중식',
        reservedFor: '허니문 런치 (12:30 예약)',
        menuRecommendation: '와규 안심 스페셜 런치 코스',
        cost: 28000,
        currency: 'JPY',
        payer: '신부',
        paymentMethod: '카드',
        lat: 35.6669,
        lng: 139.7065,
        memo: '창가 예약석, 허니문 디저트 플레이팅 요청 완료'
      },
      {
        id: 'item-008',
        day: 2,
        category: 'ATTRACTION',
        title: '시부야 스카이 (SHIBUYA SKY)',
        time: '17:30',
        openingHours: '10:00 - 22:30',
        bookingStatus: '일몰 타임 사전 예약 완료',
        ticketCostPerPerson: 2200,
        tips: '스카이 엣지 코너 포토 스팟은 대기열이 있으니 일몰 30분 전 도착 요망',
        cost: 4400,
        currency: 'JPY',
        payer: '공통',
        lat: 35.6591,
        lng: 139.7027,
        memo: '도쿄 야경을 배경으로 로맨틱 커플 사진 촬영'
      }
    ]
  };

  /**
   * Safe Clone 헬퍼
   */
  function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
  }

  class Store {
    constructor() {
      this.listeners = [];
      this.state = {
        trip: this.loadPersistedTrip() || clone(DEFAULT_TRIP),
        selectedDay: 1,
        selectedItemId: null,
        activeTab: 'timeline', // 'timeline', 'expense', 'share'
        pinDropMode: false
      };
    }

    /**
     * LocalStorage 데이터 로드
     */
    loadPersistedTrip() {
      if (typeof localStorage === 'undefined') return null;
      try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) {
          const parsed = JSON.parse(raw);
          if (parsed && parsed.metadata && Array.isArray(parsed.items)) {
            // 과거 민우, 지훈, 서연 더미 데이터가 남아있는 경우 신혼여행 기본값으로 자동 교체/마이그레이션
            if (parsed.metadata.title === '도쿄 3박 4일 감성 힐링 여행' || 
                (Array.isArray(parsed.metadata.participants) && parsed.metadata.participants.includes('민우'))) {
              return clone(DEFAULT_TRIP);
            }
            return parsed;
          }
        }
      } catch (e) {
        console.warn('Failed to load trip from LocalStorage:', e);
      }
      return null;
    }

    /**
     * LocalStorage 데이터 영구 저장
     */
    persist() {
      if (typeof localStorage === 'undefined') return;
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(this.state.trip));
      } catch (e) {
        console.error('Failed to persist trip to LocalStorage:', e);
      }
    }

    getState() {
      return this.state;
    }

    subscribe(listener) {
      if (typeof listener === 'function') {
        this.listeners.push(listener);
      }
      return () => {
        this.listeners = this.listeners.filter((l) => l !== listener);
      };
    }

    notify() {
      const state = this.getState();
      this.listeners.forEach((listener) => {
        try {
          listener(state);
        } catch (err) {
          console.error('Error in Store subscriber:', err);
        }
      });
    }

    setSelectedDay(day) {
      this.state.selectedDay = Number(day) || 1;
      this.notify();
    }

    setSelectedItemId(id) {
      this.state.selectedItemId = id;
      this.notify();
    }

    setActiveTab(tab) {
      this.state.activeTab = tab;
      this.notify();
    }

    setPinDropMode(enabled) {
      this.state.pinDropMode = Boolean(enabled);
      this.notify();
    }

    /**
     * 메타데이터 업데이트
     */
    updateMetadata(patch) {
      this.state.trip.metadata = Object.assign({}, this.state.trip.metadata, patch);
      this.persist();
      this.notify();
    }

    /**
     * 일정 아이템 추가
     */
    addItem(item) {
      const newItem = Object.assign({}, item);
      if (!newItem.id) {
        newItem.id = 'item-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6);
      }
      if (!newItem.day) {
        newItem.day = this.state.selectedDay || 1;
      }
      this.state.trip.items.push(newItem);
      this.persist();
      this.notify();
      return newItem;
    }

    /**
     * 일정 아이템 수정
     */
    updateItem(id, patch) {
      const idx = this.state.trip.items.findIndex((item) => item.id === id);
      if (idx !== -1) {
        this.state.trip.items[idx] = Object.assign({}, this.state.trip.items[idx], patch);
        this.persist();
        this.notify();
        return this.state.trip.items[idx];
      }
      return null;
    }

    /**
     * 일정 아이템 삭제
     */
    deleteItem(id) {
      const initialLen = this.state.trip.items.length;
      this.state.trip.items = this.state.trip.items.filter((item) => item.id !== id);
      if (this.state.selectedItemId === id) {
        this.state.selectedItemId = null;
      }
      this.persist();
      this.notify();
      return initialLen !== this.state.trip.items.length;
    }

    /**
     * 전체 여행 데이터 교체 (가져오기 및 복원용)
     */
    replaceTrip(newTrip) {
      if (!newTrip || !newTrip.metadata || !Array.isArray(newTrip.items)) {
        throw new Error('Invalid trip data structure');
      }
      this.state.trip = clone(newTrip);
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
    }

    /**
     * 기본 샘플 여행으로 초기화
     */
    resetToDefault() {
      this.state.trip = clone(DEFAULT_TRIP);
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
    }
  }

  // 싱글톤 인스턴스 생성
  const storeInstance = new Store();

  return {
    Store,
    DEFAULT_TRIP,
    store: storeInstance
  };
});
