/**
 * @intent 중앙 상태 관리자(Store) - 옵저버 패턴 및 LocalStorage 영구 동기화
 *         - 전체 일차('all') 선택 상태 지원 및 신규 일정 추가 시 1일차 안전 기본 배정
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

  // 클린 슬레이트(Clean Slate) 기본 여행 객체 (더미 일정 0건)
  const DEFAULT_TRIP = {
    metadata: {
      id: 'trip-my-first-trip',
      title: '나의 여행 계획',
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
    },
    items: []
  };

  // 과거 레거시 더미 데이터 식별자 세트
  const DUMMY_ITEM_IDS = new Set([
    'item-001', 'item-002', 'item-003', 'item-004',
    'item-005', 'item-006', 'item-007', 'item-008'
  ]);

  /**
   * Safe Clone 헬퍼
   */
  function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
  }

  /**
   * @intent 더미 데이터 및 레거시 데이터 검출 및 클린 슬레이트 정제(Sanitize)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip 
   * @returns {{ trip: object, changed: boolean }}
   */
  function sanitizeTripData(trip) {
    if (!trip || !trip.metadata) return { trip: clone(DEFAULT_TRIP), changed: true };
    let changed = false;
    const cloned = clone(trip);

    // 1. 메타데이터 레거시/더미 감지
    const legacyTitles = ['우리의 로맨틱 신혼여행', '도쿄 3박 4일 감성 힐링 여행'];
    if (cloned.metadata.id === 'trip-honeymoon-2026' || legacyTitles.includes(cloned.metadata.title)) {
      cloned.metadata.id = 'trip-my-first-trip';
      cloned.metadata.title = '나의 여행 계획';
      cloned.metadata.startDate = '';
      cloned.metadata.endDate = '';
      cloned.items = [];
      return { trip: cloned, changed: true };
    }

    // 2. 더미 아이템 필터링 (item-001 ~ item-008 등)
    if (Array.isArray(cloned.items)) {
      const originalLen = cloned.items.length;
      cloned.items = cloned.items.filter((item) => {
        if (!item || !item.id) return false;
        if (DUMMY_ITEM_IDS.has(item.id)) return false;
        if (typeof item.title === 'string' && (item.title.includes('에어서울 RS701') || item.title.includes('나리타 국제공항'))) {
          return false;
        }
        return true;
      });
      if (cloned.items.length !== originalLen) {
        changed = true;
      }
    } else {
      cloned.items = [];
      changed = true;
    }

    if (!cloned.metadata.id) {
      cloned.metadata.id = 'trip-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6);
      changed = true;
    }

    return { trip: cloned, changed };
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
     * @intent LocalStorage 데이터 로드 (v2 우선 및 v1 레거시 자동 마이그레이션 및 더미 데이터 클린 슬레이트 정제)
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
        let needsPersist = false;

        // 1. V2 복수 여행 데이터 로드 시도
        const rawV2 = localStorage.getItem(STORAGE_KEY_V2);
        if (rawV2) {
          const parsedV2 = JSON.parse(rawV2);
          if (parsedV2 && Array.isArray(parsedV2.trips) && parsedV2.trips.length > 0) {
            const validTrips = parsedV2.trips.map((t) => {
              const { trip: sanitized, changed } = sanitizeTripData(t);
              if (changed) needsPersist = true;
              return sanitized;
            });

            let currentId = parsedV2.currentTripId;
            if (currentId === 'trip-honeymoon-2026') {
              currentId = 'trip-my-first-trip';
              needsPersist = true;
            }

            let currentTrip = validTrips.find((t) => t.metadata && t.metadata.id === currentId);
            if (!currentTrip) {
              currentTrip = validTrips[0];
              currentId = currentTrip.metadata.id;
              needsPersist = true;
            }

            if (needsPersist) {
              try {
                localStorage.setItem(STORAGE_KEY_V2, JSON.stringify({
                  trips: validTrips,
                  currentTripId: currentId
                }));
                localStorage.setItem(STORAGE_KEY_LEGACY, JSON.stringify(currentTrip));
              } catch (err) {
                console.warn('Failed to sanitize localStorage:', err);
              }
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
            const { trip: sanitizedLegacy } = sanitizeTripData(parsedV1);
            if (!sanitizedLegacy.metadata.id) {
              sanitizedLegacy.metadata.id = 'trip-legacy-v1';
            }
            try {
              localStorage.setItem(STORAGE_KEY_V2, JSON.stringify({
                trips: [sanitizedLegacy],
                currentTripId: sanitizedLegacy.metadata.id
              }));
              localStorage.setItem(STORAGE_KEY_LEGACY, JSON.stringify(sanitizedLegacy));
            } catch (err) {
              console.warn('Failed to persist migrated legacy trip:', err);
            }
            return {
              trips: [sanitizedLegacy],
              currentTripId: sanitizedLegacy.metadata.id,
              trip: sanitizedLegacy
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
     * @intent LocalStorage 데이터 영구 저장 및 Supabase 클라우드 백그라운드 동기화
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

      // Supabase 클라우드 실시간 백그라운드 동기화
      this.syncCurrentTripToCloud();
    }

    /**
     * @intent 상태 영구 저장 및 클라우드 동기화 트리거
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    saveState() {
      this.persist();
    }

    /**
     * @intent Supabase 관리자 인스턴스 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {object|null}
     */
    getSupabaseManager() {
      if (this.customSupabaseManager) {
        return this.customSupabaseManager;
      }
      if (typeof TripSupabase !== 'undefined' && TripSupabase.supabaseManager) {
        return TripSupabase.supabaseManager;
      }
      if (typeof window !== 'undefined' && window.TripSupabase && window.TripSupabase.supabaseManager) {
        return window.TripSupabase.supabaseManager;
      }
      return null;
    }

    /**
     * @intent 의존성 주입 및 단위 테스트용 Supabase 매니저 등록
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object|null} manager
     */
    setSupabaseManager(manager) {
      this.customSupabaseManager = manager;
    }

    /**
     * @intent 현재 활성 여행 계획을 Supabase 클라우드에 백그라운드 비동기 동기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Promise<boolean>}
     */
    async syncCurrentTripToCloud() {
      try {
        const mgr = this.getSupabaseManager();
        if (mgr && typeof mgr.isConfigured === 'function' && mgr.isConfigured() && this.state.trip) {
          if (typeof mgr.autoSyncTrip === 'function') {
            await mgr.autoSyncTrip(this.state.trip);
          } else {
            await mgr.syncTrip(this.state.trip);
          }
          return true;
        }
      } catch (err) {
        console.warn('Background Supabase sync failed (offline or network error):', err);
      }
      return false;
    }

    /**
     * @intent Supabase 클라우드에서 전체 여행 목록을 조회하여 로컬 스토어에 병합 및 복원
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Promise<{ count: number, trips: Array<object> }>}
     */
    async importFromCloud() {
      const mgr = this.getSupabaseManager();
      if (!mgr || typeof mgr.isConfigured !== 'function' || !mgr.isConfigured()) {
        throw new Error('Supabase 클라우드 설정이 완료되지 않았습니다.');
      }

      const cloudTrips = await mgr.fetchTrips();
      if (!cloudTrips || cloudTrips.length === 0) {
        return { count: 0, trips: this.state.trips };
      }

      const tripMap = new Map();
      this.state.trips.forEach((t) => {
        if (t && t.metadata && t.metadata.id) {
          tripMap.set(t.metadata.id, t);
        }
      });

      cloudTrips.forEach((cloudTrip) => {
        if (cloudTrip && cloudTrip.metadata && cloudTrip.metadata.id) {
          const sanitized = sanitizeTripData(cloudTrip).trip;
          tripMap.set(sanitized.metadata.id, sanitized);
        }
      });

      this.state.trips = Array.from(tripMap.values());
      const hasCurrent = this.state.trips.some((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (!hasCurrent && this.state.trips.length > 0) {
        this.state.currentTripId = this.state.trips[0].metadata.id;
      }
      this.state.trip = this.state.trips.find((t) => t.metadata && t.metadata.id === this.state.currentTripId) || this.state.trips[0];
      this.state.selectedDay = 1;
      this.state.selectedItemId = null;

      this.persist();
      this.notify();

      return { count: cloudTrips.length, trips: this.state.trips };
    }

    /**
     * @intent 로컬에 보관된 모든 여행 계획을 Supabase 클라우드로 즉시 일괄 업로드 동기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Promise<number>}
     */
    async syncAllToCloud() {
      const mgr = this.getSupabaseManager();
      if (!mgr || typeof mgr.isConfigured !== 'function' || !mgr.isConfigured()) {
        throw new Error('Supabase 클라우드 설정이 완료되지 않았습니다.');
      }

      let count = 0;
      for (const t of this.state.trips) {
        if (t && t.metadata && t.metadata.id) {
          await mgr.syncTrip(t);
          count++;
        }
      }
      return count;
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

      // Supabase 클라우드 삭제 비동기 전파
      const mgr = this.getSupabaseManager();
      if (mgr && typeof mgr.isConfigured === 'function' && mgr.isConfigured()) {
        mgr.deleteTrip(tripId).catch((err) => {
          console.warn('Supabase deleteTrip sync failed:', err);
        });
      }

      return true;
    }

    /**
     * @intent 일차(Day) 선택 변경 - 특정 일차(숫자) 또는 전체 보기('all') 지원
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    setSelectedDay(day) {
      if (day === 'all' || day === 'ALL') {
        this.state.selectedDay = 'all';
      } else {
        this.state.selectedDay = Number(day) || 1;
      }
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
     * @intent 일정 아이템 추가 (활성 여행 및 trips 배열 동시 동기화, selectedDay가 'all'일 때 1일차 안전 배정)
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
        newItem.day = (this.state.selectedDay === 'all' || this.state.selectedDay === 'ALL' ? 1 : this.state.selectedDay) || 1;
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
     * @intent 현재 활성화된 여행 계획의 모든 일정을 즉시 비우고(Clean slate) 스토리지 및 옵저버 동기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    clearCurrentTripItems() {
      this.state.trip.items = [];
      const idx = this.state.trips.findIndex((t) => t.metadata && t.metadata.id === this.state.currentTripId);
      if (idx !== -1) {
        this.state.trips[idx].items = [];
      }
      this.state.selectedItemId = null;
      this.persist();
      this.notify('trip_cleared', { trip: this.state.trip });
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
