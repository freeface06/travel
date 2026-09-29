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

  const STORAGE_KEY_V2 = 'mytriplog_trips_data_v2';
  const STORAGE_KEY_LEGACY = 'mytriplog_trip_data_v1';

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
    /**
     * @intent Multi-Trip 상태 관리자 인스턴스 초기화 및 영구 데이터 로드
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    constructor() {
      this.listeners = [];
      const initialData = this.loadInitialData();
      this.state = {
        trips: initialData.trips,
        currentTripId: initialData.currentTripId,
        trip: initialData.trip,
        selectedDay: 1,
        selectedItemId: null,
        activeTab: 'timeline',
        pinDropMode: false
      };
    }

    /**
     * @intent LocalStorage 데이터 로드 (v2 우선 및 v1 레거시 자동 마이그레이션)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    loadInitialData() {
      const defaultTrip = clone(DEFAULT_TRIP);
      const fallback = {
        trips: [defaultTrip],
        currentTripId: defaultTrip.metadata.id,
        trip: defaultTrip
      };

      if (typeof localStorage === 'undefined') {
        return fallback;
      }

      try {
        // 1. V2 복수 여행 데이터 로드 시도
        const rawV2 = localStorage.getItem(STORAGE_KEY_V2);
        if (rawV2) {
          const parsedV2 = JSON.parse(rawV2);
          if (parsedV2 && Array.isArray(parsedV2.trips) && parsedV2.trips.length > 0) {
            const validTrips = parsedV2.trips.map((t) => {
              if (t.metadata && (t.metadata.title === '도쿄 3박 4일 감성 힐링 여행' ||
                  (Array.isArray(t.metadata.participants) && t.metadata.participants.includes('민우')))) {
                return clone(DEFAULT_TRIP);
              }
              if (!t.metadata || !t.metadata.id) {
                t.metadata = Object.assign({}, t.metadata, {
                  id: 'trip-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6)
                });
              }
              return t;
            });

            let currentId = parsedV2.currentTripId;
            let currentTrip = validTrips.find((t) => t.metadata && t.metadata.id === currentId);
            if (!currentTrip) {
              currentTrip = validTrips[0];
              currentId = currentTrip.metadata.id;
            }

            return {
              trips: validTrips,
              currentTripId: currentId,
              trip: currentTrip
            };
          }
        }

        // 2. V1 단일 여행 레거시 데이터 로드 및 마이그레이션
        const rawV1 = localStorage.getItem(STORAGE_KEY_LEGACY);
        if (rawV1) {
          const parsedV1 = JSON.parse(rawV1);
          if (parsedV1 && parsedV1.metadata && Array.isArray(parsedV1.items)) {
            let legacyTrip = parsedV1;
            if (legacyTrip.metadata.title === '도쿄 3박 4일 감성 힐링 여행' ||
                (Array.isArray(legacyTrip.metadata.participants) && legacyTrip.metadata.participants.includes('민우'))) {
              legacyTrip = clone(DEFAULT_TRIP);
            }
            if (!legacyTrip.metadata.id) {
              legacyTrip.metadata.id = 'trip-legacy-v1';
            }
            return {
              trips: [legacyTrip],
              currentTripId: legacyTrip.metadata.id,
              trip: legacyTrip
            };
          }
        }
      } catch (e) {
        console.warn('Failed to load trips from LocalStorage:', e);
      }

      return fallback;
    }

    /**
     * @intent 레거시 호환용 loadPersistedTrip 메서드
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    loadPersistedTrip() {
      return this.state ? this.state.trip : clone(DEFAULT_TRIP);
    }

    /**
     * @intent LocalStorage 데이터 영구 저장 (V2 저장 및 V1 레거시 동시 미러링)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    persist() {
      if (typeof localStorage === 'undefined') return;
      try {
        localStorage.setItem(STORAGE_KEY_V2, JSON.stringify({
          trips: this.state.trips,
          currentTripId: this.state.currentTripId
        }));
        if (this.state.trip) {
          localStorage.setItem(STORAGE_KEY_LEGACY, JSON.stringify(this.state.trip));
        }
      } catch (e) {
        console.error('Failed to persist trips to LocalStorage:', e);
      }
    }

    /**
     * @intent 현재 스토어 전체 상태 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    getState() {
      return this.state;
    }

    /**
     * @intent 상태 변경 옵저버 등록
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    subscribe(listener) {
      if (typeof listener === 'function') {
        this.listeners.push(listener);
      }
      return () => {
        this.listeners = this.listeners.filter((l) => l !== listener);
      };
    }

    /**
     * @intent 등록된 모든 옵저버에게 최신 상태 통지
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
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

    /**
     * @intent 전체 여행 계획 목록 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Array} 전체 여행 계획 배열
     */
    getTrips() {
      return this.state.trips;
    }

    /**
     * @intent 현재 활성화된 여행 계획 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {object} 활성 여행 객체
     */
    getCurrentTrip() {
      return this.state.trip;
    }

    /**
     * @intent 활성 여행 계획 전환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string} tripId - 전환할 여행 ID
     * @returns {object|null} 전환된 여행 객체
     */
    switchTrip(tripId) {
      const target = this.state.trips.find((t) => t.metadata && t.metadata.id === tripId);
      if (!target) return null;

      this.state.currentTripId = target.metadata.id;
      this.state.trip = target;
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
      return target;
    }

    /**
     * @intent 신규 여행 계획 생성 및 활성 전환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object} metadata - 여행 메타데이터
     * @param {Array} initialItems - 초기 일정 아이템 목록
     * @returns {object} 생성된 여행 객체
     */
    createTrip(metadata = {}, initialItems = []) {
      const newId = metadata.id || ('trip-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6));
      const newTrip = {
        metadata: Object.assign({
          id: newId,
          title: '새로운 여행 계획',
          startDate: '',
          endDate: '',
          participants: ['신랑', '신부'],
          baseCurrency: 'KRW',
          customRates: {
            KRW: 1.0,
            JPY: 9.2,
            USD: 1350.0,
            EUR: 1460.0
          }
        }, metadata, { id: newId }),
        items: Array.isArray(initialItems) ? clone(initialItems) : []
      };

      this.state.trips.push(newTrip);
      this.state.currentTripId = newId;
      this.state.trip = newTrip;
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
      return newTrip;
    }

    /**
     * @intent 기존 여행 계획 복제하여 사본 생성 및 활성 전환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string} tripId - 복제 대상 여행 ID
     * @returns {object|null} 복제 생성된 여행 객체
     */
    duplicateTrip(tripId) {
      const source = this.state.trips.find((t) => t.metadata && t.metadata.id === tripId);
      if (!source) return null;

      const copied = clone(source);
      const newId = 'trip-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6);
      copied.metadata.id = newId;
      copied.metadata.title = `${source.metadata.title || '여행 계획'} (사본)`;

      // 아이템 ID 충돌 방지를 위해 복제본 아이템 ID 재발급
      if (Array.isArray(copied.items)) {
        copied.items = copied.items.map((item, idx) => ({
          ...item,
          id: 'item-' + Date.now() + '-' + idx + '-' + Math.random().toString(36).substring(2, 6)
        }));
      }

      this.state.trips.push(copied);
      this.state.currentTripId = newId;
      this.state.trip = copied;
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
      return copied;
    }

    /**
     * @intent 여행 계획 삭제 (최소 1개 계획 방어 및 첫 번째 계획으로 자동 전환)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string} tripId - 삭제 대상 여행 ID
     * @returns {boolean} 삭제 성공 여부
     */
    deleteTrip(tripId) {
      if (this.state.trips.length <= 1) {
        return false;
      }

      const idx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === tripId);
      if (idx === -1) return false;

      this.state.trips.splice(idx, 1);

      if (this.state.currentTripId === tripId) {
        const nextTrip = this.state.trips[0];
        this.state.currentTripId = nextTrip.metadata.id;
        this.state.trip = nextTrip;
        this.state.selectedDay = 1;
        this.state.selectedItemId = null;
      }

      this.persist();
      this.notify();
      return true;
    }

    /**
     * @intent 일차(Day) 선택 변경
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    setSelectedDay(day) {
      this.state.selectedDay = Number(day) || 1;
      this.notify();
    }

    /**
     * @intent 선택된 일정 아이템 ID 변경
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    setSelectedItemId(id) {
      this.state.selectedItemId = id;
      this.notify();
    }

    /**
     * @intent 활성 메인 패널 탭 변경
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    setActiveTab(tab) {
      this.state.activeTab = tab;
      this.notify();
    }

    /**
     * @intent 지도 핀 직접 지정 모드 토글
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    setPinDropMode(enabled) {
      this.state.pinDropMode = Boolean(enabled);
      this.notify();
    }

    /**
     * @intent 여행 메타데이터 업데이트 (활성 여행 및 trips 배열 동시 동기화)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    updateMetadata(patch) {
      this.state.trip.metadata = Object.assign({}, this.state.trip.metadata, patch);
      const idx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (idx !== -1) {
        this.state.trips[idx] = this.state.trip;
      }
      this.persist();
      this.notify();
    }

    /**
     * @intent 일정 아이템 추가 (활성 여행 및 trips 배열 동시 동기화)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
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
      const idx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (idx !== -1) {
        this.state.trips[idx] = this.state.trip;
      }
      this.persist();
      this.notify();
      return newItem;
    }

    /**
     * @intent 일정 아이템 수정 (활성 여행 및 trips 배열 동시 동기화)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    updateItem(id, patch) {
      const idx = this.state.trip.items.findIndex((item) => item.id === id);
      if (idx !== -1) {
        this.state.trip.items[idx] = Object.assign({}, this.state.trip.items[idx], patch);
        const tripIdx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
        if (tripIdx !== -1) {
          this.state.trips[tripIdx] = this.state.trip;
        }
        this.persist();
        this.notify();
        return this.state.trip.items[idx];
      }
      return null;
    }

    /**
     * @intent 일정 아이템 삭제 (활성 여행 및 trips 배열 동시 동기화)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    deleteItem(id) {
      const initialLen = this.state.trip.items.length;
      this.state.trip.items = this.state.trip.items.filter((item) => item.id !== id);
      if (this.state.selectedItemId === id) {
        this.state.selectedItemId = null;
      }
      const tripIdx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (tripIdx !== -1) {
        this.state.trips[tripIdx] = this.state.trip;
      }
      this.persist();
      this.notify();
      return initialLen !== this.state.trip.items.length;
    }

    /**
     * @intent 전체 여행 데이터 교체 (가져오기 및 복원용)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    replaceTrip(newTrip) {
      if (!newTrip || !newTrip.metadata || !Array.isArray(newTrip.items)) {
        throw new Error('Invalid trip data structure');
      }
      if (!newTrip.metadata.id) {
        newTrip.metadata.id = 'trip-' + Date.now();
      }
      const cloned = clone(newTrip);
      const idx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (idx !== -1) {
        this.state.trips[idx] = cloned;
      } else {
        this.state.trips.push(cloned);
      }
      this.state.trip = cloned;
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;
      this.persist();
      this.notify();
    }

    /**
     * @intent 기본 샘플 여행으로 초기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    resetToDefault() {
      const defaultTrip = clone(DEFAULT_TRIP);
      this.state.trips = [defaultTrip];
      this.state.currentTripId = defaultTrip.metadata.id;
      this.state.trip = defaultTrip;
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
    STORAGE_KEY_V2,
    STORAGE_KEY_LEGACY,
    store: storeInstance
  };
});
