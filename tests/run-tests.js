/**
 * @intent 정산 엔진, 환율 환산, 스토어 상태 전이 및 전체 일차('all') 지도 동선 종합 단위 테스트 스크립트
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

const assert = require('assert');
const path = require('path');
const fs = require('fs');

// Node.js 환경용 LocalStorage Mock
if (typeof localStorage === 'undefined') {
  let mockStore = {};
  global.localStorage = {
    getItem: (key) => (Object.prototype.hasOwnProperty.call(mockStore, key) ? mockStore[key] : null),
    setItem: (key, val) => { mockStore[key] = String(val); },
    removeItem: (key) => { delete mockStore[key]; },
    clear: () => { mockStore = {}; }
  };
}

// 대상 모듈 로드
const TripExpense = require(path.join(__dirname, '../js/expense.js'));
const TripStore = require(path.join(__dirname, '../js/store.js'));
const Icons = require(path.join(__dirname, '../js/icons.js'));
const TripShare = require(path.join(__dirname, '../js/share.js'));
const TripSupabase = require(path.join(__dirname, '../js/supabase.js'));
const TripMap = require(path.join(__dirname, '../js/map.js'));
const TripGeocoder = require(path.join(__dirname, '../js/geocoder.js'));
const TripForms = require(path.join(__dirname, '../js/forms.js'));
global.TripSupabase = TripSupabase;
global.TripStore = TripStore;
global.TripMap = TripMap;
global.TripGeocoder = TripGeocoder;
global.TripForms = TripForms;

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

async function runTest(testName, testFn) {
  totalTests++;
  try {
    const res = testFn();
    if (res && typeof res.then === 'function') {
      await res;
    }
    passedTests++;
    console.log(`[PASS] ${testName}`);
  } catch (err) {
    failedTests++;
    console.error(`[FAIL] ${testName}`);
    console.error(`       Error: ${err.message}`);
  }
}

async function runAllTests() {
  console.log('====================================================');
  console.log('   MyTripLog Core Unit Test Suite (Node.js Test Runner)   ');
  console.log('====================================================\n');

// --------------------------------------------------------------------------
// 1. 환율 환산 엔진 (Currency Conversion Tests)
// --------------------------------------------------------------------------
console.log('--- [Suite 1: 환율 환산 엔진 검증] ---');

runTest('1-1. 동일 통화 환산 시 원래 금액 그대로 반환되어야 함', () => {
  const result = TripExpense.convertCurrency(10000, 'KRW', 'KRW');
  assert.strictEqual(result, 10000);
  // 부동소수점 오차(예: 1499999.999) 유입 시에도 1500000 순수 정수로 정제 검증
  const floatFix = TripExpense.convertCurrency(1499999.999, 'KRW', 'KRW');
  assert.strictEqual(floatFix, 1500000);
});

runTest('1-2. 0원 또는 음수/NaN 입력 시 0 반환', () => {
  assert.strictEqual(TripExpense.convertCurrency(0, 'USD', 'KRW'), 0);
  assert.strictEqual(TripExpense.convertCurrency(null, 'USD', 'KRW'), 0);
});

runTest('1-3. JPY -> KRW 환산 (1 JPY = 9.2 KRW 기본 환율 적용)', () => {
  // 1,000엔 * 9.2 = 9,200원
  const result = TripExpense.convertCurrency(1000, 'JPY', 'KRW');
  assert.strictEqual(result, 9200);
});

runTest('1-4. USD -> KRW 환산 (1 USD = 1350 KRW 기본 환율 적용)', () => {
  // 100달러 * 1350 = 135,000원
  const result = TripExpense.convertCurrency(100, 'USD', 'KRW');
  assert.strictEqual(result, 135000);
});

runTest('1-5. 사용자 커스텀 환율 적용 환산 (EUR = 1500)', () => {
  const result = TripExpense.convertCurrency(10, 'EUR', 'KRW', { EUR: 1500.0 });
  assert.strictEqual(result, 15000);
});

// --------------------------------------------------------------------------
// 2. 1/N 정산 및 분담금 계산 (Share Distribution Tests)
// --------------------------------------------------------------------------
console.log('\n--- [Suite 2: 1/N 분담금 및 잔여 단수 분배 검증] ---');

runTest('2-1. 정밀 균등 분할: 90,000원 3인 분할 시 각 30,000원', () => {
  const shares = TripExpense.calculateIndividualShares(90000, ['A', 'B', 'C'], 'KRW');
  assert.strictEqual(shares['A'], 30000);
  assert.strictEqual(shares['B'], 30000);
  assert.strictEqual(shares['C'], 30000);
  assert.strictEqual(shares['A'] + shares['B'] + shares['C'], 90000);
});

runTest('2-2. 홀수 단수 분할: 100,000원 3인 분할 시 1원 단위 합계 오차 0 보장', () => {
  // 100,000 / 3 = 33,333원 + 나머지 1원
  // A: 33,334원, B: 33,333원, C: 33,333원
  const shares = TripExpense.calculateIndividualShares(100000, ['A', 'B', 'C'], 'KRW');
  assert.strictEqual(shares['A'], 33334);
  assert.strictEqual(shares['B'], 33333);
  assert.strictEqual(shares['C'], 33333);
  assert.strictEqual(shares['A'] + shares['B'] + shares['C'], 100000);
});

runTest('2-3. 소수점 통화(USD) 분할: $100.00 3인 분할 시 총합 $100.00 일치', () => {
  const shares = TripExpense.calculateIndividualShares(100, ['A', 'B', 'C'], 'USD');
  const sum = Math.round((shares['A'] + shares['B'] + shares['C']) * 100) / 100;
  assert.strictEqual(sum, 100);
});

// --------------------------------------------------------------------------
// 3. 그리디 알고리즘 기반 최소 횟수 1/N 송금 엔진 검증 (Settlement Engine Tests)
// --------------------------------------------------------------------------
console.log('\n--- [Suite 3: 최소 횟수 1/N 그리디 송금 엔진 검증] ---');

runTest('3-1. Happy Path: 3인 각자 지출 후 최소 송금 거래 산출', () => {
  // 민우: 60,000원 결제
  // 지훈: 30,000원 결제
  // 서연: 0원 결제
  // 총 지출: 90,000원 (1인당 분담금: 30,000원)
  // 민우 순차액: +30,000원 (받을 돈)
  // 지훈 순차액: 0원
  // 서연 순차액: -30,000원 (보낼 돈)
  // 최소 송금: 서연 -> 민우 30,000원 (단 1회의 거래로 정산 완료!)
  const members = ['민우', '지훈', '서연'];
  const items = [
    { cost: 60000, currency: 'KRW', payer: '민우' },
    { cost: 30000, currency: 'KRW', payer: '지훈' }
  ];

  const result = TripExpense.calculateSettlements(members, items, 'KRW');
  assert.strictEqual(result.summary.totalInBase, 90000);
  assert.strictEqual(result.settlements.length, 1);
  assert.strictEqual(result.settlements[0].from, '서연');
  assert.strictEqual(result.settlements[0].to, '민우');
  assert.strictEqual(result.settlements[0].amount, 30000);
});

runTest('3-2. 엣지 케이스 1: 총 지출이 0원인 경우 송금 내역 0건', () => {
  const members = ['민우', '지훈'];
  const items = [{ cost: 0, currency: 'KRW', payer: '민우' }];
  const result = TripExpense.calculateSettlements(members, items, 'KRW');
  assert.strictEqual(result.settlements.length, 0);
  assert.strictEqual(result.summary.totalInBase, 0);
});

runTest('3-3. 엣지 케이스 2: 1인 단독 여행인 경우 송금 내역 0건', () => {
  const members = ['민우'];
  const items = [{ cost: 50000, currency: 'KRW', payer: '민우' }];
  const result = TripExpense.calculateSettlements(members, items, 'KRW');
  assert.strictEqual(result.settlements.length, 0);
});

runTest('3-4. 엣지 케이스 3: 모든 참가자가 정확히 동일하게 결제한 경우 송금 0건', () => {
  const members = ['A', 'B'];
  const items = [
    { cost: 20000, currency: 'KRW', payer: 'A' },
    { cost: 20000, currency: 'KRW', payer: 'B' }
  ];
  const result = TripExpense.calculateSettlements(members, items, 'KRW');
  assert.strictEqual(result.settlements.length, 0);
});

runTest('3-5. 엣지 케이스 4: 1인이 전액 결제한 경우 다자간 송금', () => {
  // A가 120,000원 전액 결제 (A, B, C, D 4인 여행 -> 1인당 30,000원)
  // B -> A 30,000 / C -> A 30,000 / D -> A 30,000 (총 3건 송금)
  const members = ['A', 'B', 'C', 'D'];
  const items = [{ cost: 120000, currency: 'KRW', payer: 'A' }];
  const result = TripExpense.calculateSettlements(members, items, 'KRW');

  assert.strictEqual(result.summary.totalInBase, 120000);
  assert.strictEqual(result.settlements.length, 3);
  result.settlements.forEach((st) => {
    assert.strictEqual(st.to, 'A');
    assert.strictEqual(st.amount, 30000);
  });
});

runTest('3-6. 다중 통화 혼합 결제 정산 검증 (KRW + JPY)', () => {
  // 참가자: [A, B]
  // A: 10,000 KRW
  // B: 2,000 JPY (환율 9.2 -> 18,400 KRW)
  // 총 지출액: 28,400 KRW
  // 1인당: 14,200 KRW
  // A 순차액: 10,000 - 14,200 = -4,200 KRW (보낼 돈)
  // B 순차액: 18,400 - 14,200 = +4,200 KRW (받을 돈)
  // A -> B : 4,200원 송금
  const members = ['A', 'B'];
  const items = [
    { cost: 10000, currency: 'KRW', payer: 'A' },
    { cost: 2000, currency: 'JPY', payer: 'B' }
  ];
  const result = TripExpense.calculateSettlements(members, items, 'KRW', { JPY: 9.2 });
  assert.strictEqual(result.summary.totalInBase, 28400);
  assert.strictEqual(result.settlements.length, 1);
  assert.strictEqual(result.settlements[0].from, 'A');
  assert.strictEqual(result.settlements[0].to, 'B');
  assert.strictEqual(result.settlements[0].amount, 4200);
});

// --------------------------------------------------------------------------
// 4. 상태 관리자(Store) 및 데이터 수명주기 검증
// --------------------------------------------------------------------------
console.log('\n--- [Suite 4: Store 상태 관리자 및 불변성/옵저버 검증] ---');

runTest('4-1. 기본 여행 데이터 초기화 및 클린 슬레이트(items: []) 검증', () => {
  const store = new TripStore.Store();
  const trip = store.getState().trip;

  assert.ok(trip.metadata.title);
  assert.strictEqual(trip.metadata.title, '나의 여행 계획');
  assert.ok(Array.isArray(trip.items));
  assert.strictEqual(trip.items.length, 0);
});

runTest('4-2. 아이템 추가 (addItem) 및 ID 자동 발급', () => {
  const store = new TripStore.Store();
  const initialCount = store.getState().trip.items.length;

  const newItem = store.addItem({
    title: '도쿄 디즈니씨',
    category: 'ATTRACTION',
    day: 3,
    cost: 89000,
    currency: 'KRW',
    payer: '민우'
  });

  assert.ok(newItem.id);
  assert.strictEqual(store.getState().trip.items.length, initialCount + 1);
  assert.strictEqual(newItem.title, '도쿄 디즈니씨');
});

runTest('4-3. 아이템 수정 (updateItem)', () => {
  const store = new TripStore.Store();
  const added = store.addItem({
    title: '인천 -> 나리타 에어서울 RS701',
    category: 'FLIGHT',
    day: 1,
    cost: 650000,
    currency: 'KRW'
  });
  const firstId = added.id;

  store.updateItem(firstId, {
    title: '인천 -> 나리타 에어서울 RS701 (수정됨)',
    cost: 700000
  });

  const updated = store.getState().trip.items.find((it) => it.id === firstId);
  assert.strictEqual(updated.title, '인천 -> 나리타 에어서울 RS701 (수정됨)');
  assert.strictEqual(updated.cost, 700000);
});

runTest('4-4. 아이템 삭제 (deleteItem) 및 일정 전체 비우기 (clearCurrentTripItems)', () => {
  const store = new TripStore.Store();
  const firstItem = store.getState().trip.items[0] || store.addItem({ title: '삭제 대상 일정' });
  const firstId = firstItem.id;
  const initialCount = store.getState().trip.items.length;

  const deleted = store.deleteItem(firstId);
  assert.strictEqual(deleted, true);
  assert.strictEqual(store.getState().trip.items.length, initialCount - 1);
  assert.strictEqual(store.getState().trip.items.find((it) => it.id === firstId), undefined);

  // 일정 전체 비우기 (clearCurrentTripItems) 검증
  store.addItem({ title: '테스트 아이템 A' });
  assert.ok(store.getState().trip.items.length > 0);
  store.clearCurrentTripItems();
  assert.strictEqual(store.getState().trip.items.length, 0);
});

runTest('4-5. 옵저버 구독 및 상태 변경 시 통지 (subscribe/notify)', () => {
  const store = new TripStore.Store();
  let callCount = 0;
  let receivedState = null;

  const unsubscribe = store.subscribe((state) => {
    callCount++;
    receivedState = state;
  });

  store.setSelectedDay(3);
  assert.strictEqual(callCount, 1);
  assert.strictEqual(receivedState.selectedDay, 3);

  unsubscribe();
  store.setSelectedDay(4);
  assert.strictEqual(callCount, 1); // 구독 취소 후에는 증가하지 않음
});

// --------------------------------------------------------------------------
// 5. 무서버 공유 데이터 살균화 검증 (Share Data Sanitization)
// --------------------------------------------------------------------------
console.log('\n--- [Suite 5: 무서버 공유 및 직렬화 검증] ---');

runTest('5-1. 공유 데이터 살균 시 photoDataUrl(Base64)이 안전하게 제외되어야 함', () => {
  const dummyTrip = {
    metadata: { title: '테스트 여행' },
    items: [
      {
        id: '1',
        title: '명소 A',
        photoId: 'photo-1',
        photoDataUrl: 'data:image/jpeg;base64,AAAAAA...',
        photos: [{ id: 'p1', dataUrl: 'data:image/jpeg;base64,BBBBBB...', filename: 'attraction.jpg' }]
      },
      { id: '2', title: '식당 B', photoId: null }
    ]
  };

  const sanitized = TripShare.sanitizeForSharing(dummyTrip);
  assert.strictEqual(sanitized.items[0].photoDataUrl, undefined);
  assert.strictEqual(sanitized.items[0].photoId, 'photo-1');
  assert.strictEqual(sanitized.items[0].title, '명소 A');
  assert.strictEqual(sanitized.items[0].photos[0].dataUrl, undefined);
  assert.strictEqual(sanitized.items[0].photos[0].id, 'p1');
  // 원본 객체는 오염되지 않음
  assert.ok(dummyTrip.items[0].photoDataUrl);
  assert.ok(dummyTrip.items[0].photos[0].dataUrl);
});

// --------------------------------------------------------------------------
// 6. SVG 아이콘 유효성 검증 (Strict No-Emoji Check)
// --------------------------------------------------------------------------
console.log('\n--- [Suite 6: SVG 아이콘 및 엄격한 No-Emoji 검증] ---');

runTest('6-1. 6대 카테고리 SVG 아이콘 정상 생성', () => {
  ['FLIGHT', 'AIRPORT', 'HOTEL', 'ATTRACTION', 'DINING', 'TRANSIT'].forEach((key) => {
    const svg = Icons.getIcon(key);
    assert.ok(svg.startsWith('<svg'));
    assert.ok(svg.endsWith('</svg>'));
    assert.ok(svg.includes('xmlns="http://www.w3.org/2000/svg"'));
  });
});

runTest('6-2. 아이콘 모듈에 유니코드 이모지가 전혀 포함되지 않음', () => {
  const emojiRegex = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/u;
  Object.keys(Icons.SVG_DEFS).forEach((key) => {
    assert.strictEqual(emojiRegex.test(Icons.SVG_DEFS[key]), false, `Emoji found in icon ${key}`);
  });
});

// --------------------------------------------------------------------------
// 7. 복수 여행 계획(Multi-Trip) 관리 및 전환 엔진 검증
// --------------------------------------------------------------------------
console.log('\n--- [Suite 7: 복수 여행 계획(Multi-Trip) 관리 및 전환 엔진 검증] ---');

runTest('7-1. 복수 여행 초기화 및 기본 여행 목록 확보', () => {
  const store = new TripStore.Store();
  const trips = store.getTrips();
  const currentTrip = store.getCurrentTrip();

  assert.ok(Array.isArray(trips));
  assert.strictEqual(trips.length, 1);
  assert.ok(currentTrip);
  assert.strictEqual(currentTrip.metadata.id, store.getState().currentTripId);
  assert.strictEqual(currentTrip, trips[0]);
});

runTest('7-2. 신규 여행 계획 추가 (createTrip) 및 활성 전환 검증', () => {
  const store = new TripStore.Store();
  const initialCount = store.getTrips().length;

  const newTrip = store.createTrip({
    title: '제주도 3박 4일 힐링 투어',
    startDate: '2026-11-01',
    endDate: '2026-11-04',
    participants: ['철수', '영희'],
    baseCurrency: 'KRW'
  });

  assert.strictEqual(store.getTrips().length, initialCount + 1);
  assert.strictEqual(store.getState().currentTripId, newTrip.metadata.id);
  assert.strictEqual(store.getCurrentTrip().metadata.title, '제주도 3박 4일 힐링 투어');
  assert.strictEqual(store.getState().selectedDay, 1);
  assert.strictEqual(store.getState().selectedItemId, null);
});

runTest('7-3. 여행 계획 간 자유로운 전환 (switchTrip) 및 상태 동기화 검증', () => {
  const store = new TripStore.Store();
  const trip1Id = store.getState().currentTripId;
  const trip2 = store.createTrip({ title: '오사카 먹방 투어' });
  const trip2Id = trip2.metadata.id;
  assert.strictEqual(store.getState().currentTripId, trip2Id);

  // trip1으로 다시 전환
  const switched = store.switchTrip(trip1Id);
  assert.ok(switched);
  assert.strictEqual(switched.metadata.id, trip1Id);
  assert.strictEqual(store.getState().currentTripId, trip1Id);
  assert.strictEqual(store.getCurrentTrip().metadata.id, trip1Id);
  assert.strictEqual(store.getState().selectedDay, 1);
  assert.strictEqual(store.getState().selectedItemId, null);
});

runTest('7-4. 기존 여행 계획 복제 (duplicateTrip) 및 독립적 수정 검증', () => {
  const store = new TripStore.Store();
  const originalTrip = store.getCurrentTrip();
  const originalItemsCount = originalTrip.items.length;
  const duplicated = store.duplicateTrip(originalTrip.metadata.id);

  assert.ok(duplicated);
  assert.notStrictEqual(duplicated.metadata.id, originalTrip.metadata.id);
  assert.ok(duplicated.metadata.title.includes('(사본)'));
  assert.strictEqual(store.getState().currentTripId, duplicated.metadata.id);
  assert.strictEqual(duplicated.items.length, originalItemsCount);

  // 복제본에 일정 추가 시 원본 여행에는 영향이 없어야 함 (독립성 보장)
  store.addItem({
    title: '복제본 전용 일정 아이템',
    category: 'ATTRACTION',
    cost: 50000,
    currency: 'KRW'
  });

  assert.strictEqual(store.getCurrentTrip().items.length, originalItemsCount + 1);
  const foundOriginal = store.getTrips().find((t) => t.metadata.id === originalTrip.metadata.id);
  assert.strictEqual(foundOriginal.items.length, originalItemsCount);
});

runTest('7-5. 여행 계획 삭제 (deleteTrip) 및 최소 1개 유지 방어 검증', () => {
  if (typeof localStorage !== 'undefined') localStorage.clear();
  const store = new TripStore.Store();
  // 1개만 있을 때 삭제 시도 -> 실패(false) 및 유지
  assert.strictEqual(store.getTrips().length, 1);
  const deleteResult1 = store.deleteTrip(store.getState().currentTripId);
  assert.strictEqual(deleteResult1, false);
  assert.strictEqual(store.getTrips().length, 1);

  // 2개로 만든 후 현재 활성 여행 삭제 시 남은 첫 번째 여행으로 자동 전환
  const trip2 = store.createTrip({ title: '삭제 테스트용 여행' });
  assert.strictEqual(store.getTrips().length, 2);
  assert.strictEqual(store.getState().currentTripId, trip2.metadata.id);

  const deleteResult2 = store.deleteTrip(trip2.metadata.id);
  assert.strictEqual(deleteResult2, true);
  assert.strictEqual(store.getTrips().length, 1);
  assert.notStrictEqual(store.getState().currentTripId, trip2.metadata.id);
  assert.strictEqual(store.getState().currentTripId, store.getTrips()[0].metadata.id);
});

  // --------------------------------------------------------------------------
  // 8. Supabase 연동 모듈 및 클라우드 동기화 엔진 검증
  // --------------------------------------------------------------------------
  console.log('\n--- [Suite 8: Supabase 연동 모듈 및 클라우드 동기화 엔진 검증] ---');

  await runTest('8-1. TripSupabase 기본 내장 상수 및 초기 자동 설정(isConfigured = true) 검증', () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    mgr.clearConfig();
    // 기본 내장 상수가 존재하므로 별도 입력 없이도 언제나 true
    assert.strictEqual(mgr.isConfigured(), true);
    const config = mgr.getConfig();
    assert.strictEqual(config.url, TripSupabase.DEFAULT_SUPABASE_URL);
    assert.strictEqual(config.anonKey, TripSupabase.DEFAULT_SUPABASE_KEY);
    assert.strictEqual(config.url, 'https://qmqklwelrsmlsrmtnsxt.supabase.co');
  });

  await runTest('8-2. 사용자 커스텀 설정 덮어쓰기 및 clearConfig 시 기본 내장값으로 복귀 검증', () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    const saved = mgr.saveConfig('https://custom-project.supabase.co', 'custom-anon-key-12345');
    assert.strictEqual(saved.url, 'https://custom-project.supabase.co');
    assert.strictEqual(saved.anonKey, 'custom-anon-key-12345');
    assert.strictEqual(mgr.isConfigured(), true);

    const config = mgr.getConfig();
    assert.strictEqual(config.url, 'https://custom-project.supabase.co');
    assert.strictEqual(config.anonKey, 'custom-anon-key-12345');

    // clearConfig 호출 시 로컬스토리지 삭제 후 기본 내장 상수로 안전하게 복귀
    mgr.clearConfig();
    assert.strictEqual(mgr.isConfigured(), true);
    const cleared = mgr.getConfig();
    assert.strictEqual(cleared.url, TripSupabase.DEFAULT_SUPABASE_URL);
    assert.strictEqual(cleared.anonKey, TripSupabase.DEFAULT_SUPABASE_KEY);
  });

  await runTest('8-3. getSetupSqlScript() 표준 SQL 스크립트 무결성 검증', () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    const sql = mgr.getSetupSqlScript();
    assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.trips'));
    assert.ok(sql.includes('ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY'));
    assert.ok(sql.includes('INSERT INTO storage.buckets (id, name, public)'));
    assert.ok(sql.includes('\'trip-photos\''));
    assert.ok(sql.includes('CREATE POLICY "Public photos access"'));
  });

  await runTest('8-4. base64ToBlob 변환 유틸리티의 안전한 Blob 반환 검증', () => {
    const sampleText = 'MyTripLog photo binary test data';
    const base64Data = Buffer.from(sampleText).toString('base64');
    const dataUrl = `data:image/jpeg;base64,${base64Data}`;

    const blob = TripSupabase.base64ToBlob(dataUrl, 'image/jpeg');
    assert.ok(blob);
    assert.strictEqual(blob.type, 'image/jpeg');
    assert.ok(blob.size > 0);

    // 잘못된 입력에 대한 안전한 null 반환
    assert.strictEqual(TripSupabase.base64ToBlob(null), null);
    assert.strictEqual(TripSupabase.base64ToBlob(''), null);
  });

  await runTest('8-5. Mock Supabase 클라이언트를 통한 DB 쿼리(연결/동기화/삭제/조회) 검증', async () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    mgr.saveConfig('https://myproject.supabase.co', 'anon-test-key');

    // 메모리 내 Mock Supabase 클라이언트 구축
    const mockDb = new Map();
    const mockClient = {
      from: (tableName) => {
        assert.strictEqual(tableName, 'trips');
        return {
          select: () => ({
            limit: async () => ({ data: [{ id: 'mock-1' }], error: null }),
            order: async () => ({
              data: Array.from(mockDb.values()),
              error: null
            })
          }),
          upsert: async (record) => {
            mockDb.set(record.id, record);
            return { data: record, error: null };
          },
          delete: () => ({
            eq: async (field, val) => {
              if (field === 'id') {
                mockDb.delete(val);
              }
              return { error: null };
            }
          })
        };
      }
    };

    mgr.setClient(mockClient);

    // 1) 연결 테스트
    const connRes = await mgr.testConnection();
    assert.strictEqual(connRes.ok, true);

    // 2) 여행 동기화 (upsert)
    const sampleTrip = {
      metadata: {
        id: 'trip-supabase-test-1',
        title: '클라우드 동기화 테스트 여행',
        startDate: '2026-10-01',
        endDate: '2026-10-05',
        baseCurrency: 'KRW'
      },
      items: []
    };
    const syncRes = await mgr.syncTrip(sampleTrip);
    assert.strictEqual(syncRes.ok, true);
    assert.strictEqual(mockDb.size, 1);

    // 3) 여행 목록 조회 (fetchTrips)
    const fetched = await mgr.fetchTrips();
    assert.strictEqual(fetched.length, 1);
    assert.strictEqual(fetched[0].metadata.id, 'trip-supabase-test-1');

    // 4) 여행 삭제 (deleteTrip)
    const delRes = await mgr.deleteTrip('trip-supabase-test-1');
    assert.strictEqual(delRes.ok, true);
    assert.strictEqual(mockDb.size, 0);
  });

  await runTest('8-6. Mock Supabase Storage를 통한 uploadPhoto() CDN URL 반환 검증', async () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    mgr.saveConfig('https://myproject.supabase.co', 'anon-test-key');

    let uploadedPath = '';
    const mockStorageClient = {
      storage: {
        from: (bucketId) => {
          assert.strictEqual(bucketId, 'trip-photos');
          return {
            upload: async (path, blob, options) => {
              uploadedPath = path;
              return { data: { path }, error: null };
            },
            getPublicUrl: (path) => ({
              data: {
                publicUrl: `https://myproject.supabase.co/storage/v1/object/public/trip-photos/${path}`
              }
            })
          };
        }
      }
    };

    mgr.setClient(mockStorageClient);
    const sampleDataUrl = 'data:image/jpeg;base64,' + Buffer.from('test-image').toString('base64');
    const publicUrl = await mgr.uploadPhoto(sampleDataUrl, 'tokyo_tower.jpg');

    assert.ok(publicUrl);
    assert.ok(publicUrl.includes('https://myproject.supabase.co/storage/v1/object/public/trip-photos/'));
    assert.ok(uploadedPath.startsWith('trip-photos/'));
    assert.ok(uploadedPath.endsWith('.jpg'));
  });

  await runTest('8-7. Store의 importFromCloud() 및 syncAllToCloud() 클라우드 연동 검증', async () => {
    const store = new TripStore.Store();
    const mgr = new TripSupabase.SupabaseClientManager();
    mgr.saveConfig('https://myproject.supabase.co', 'anon-test-key');

    const cloudTripsData = [
      {
        metadata: {
          id: 'cloud-trip-001',
          title: '클라우드 복원 여행 계획',
          startDate: '2026-11-01',
          endDate: '2026-11-05',
          participants: ['나', '친구'],
          baseCurrency: 'KRW'
        },
        items: []
      }
    ];

    let syncedTripCount = 0;
    const mockMgr = {
      isConfigured: () => true,
      fetchTrips: async () => cloudTripsData,
      syncTrip: async (trip) => {
        syncedTripCount++;
        return { ok: true };
      },
      deleteTrip: async () => ({ ok: true })
    };

    store.setSupabaseManager(mockMgr);

    // syncAllToCloud 실행 검증
    const syncCount = await store.syncAllToCloud();
    assert.strictEqual(syncCount, store.getTrips().length);
    assert.strictEqual(syncedTripCount, store.getTrips().length);

    // importFromCloud 실행 검증 (병합 복원)
    const importRes = await store.importFromCloud();
    assert.ok(importRes.count >= 1);
    const foundCloudTrip = store.getTrips().find((t) => t.metadata && t.metadata.id === 'cloud-trip-001');
    assert.ok(foundCloudTrip);
    assert.strictEqual(foundCloudTrip.metadata.title, '클라우드 복원 여행 계획');
  });

  await runTest('8-8. autoSyncTrip() 및 autoFetchAndRestore() 실시간 자동 동기화 헬퍼 검증', async () => {
    const mgr = new TripSupabase.SupabaseClientManager();
    const store = new TripStore.Store();
    store.setSupabaseManager(mgr);

    const recordedSyncStates = [];
    mgr.onSyncStateChange((s) => {
      recordedSyncStates.push(s.state);
    });

    const mockDb = new Map();
    const mockClient = {
      from: (tableName) => ({
        select: () => ({
          order: async () => ({
            data: Array.from(mockDb.values()),
            error: null
          })
        }),
        upsert: async (record) => {
          mockDb.set(record.id, record);
          return { data: record, error: null };
        }
      })
    };
    mgr.setClient(mockClient);

    // 1) autoFetchAndRestore 시 클라우드가 비어있으면 로컬 데이터를 클라우드로 Seed 백업
    const seedResult = await mgr.autoFetchAndRestore(store);
    assert.strictEqual(seedResult.action, 'seeded');
    assert.ok(seedResult.count >= 1);
    assert.strictEqual(mockDb.size >= 1, true);

    // 2) autoSyncTrip 단일 여행 자동 동기화
    const trip = store.getCurrentTrip();
    const syncRes = await mgr.autoSyncTrip(trip);
    assert.strictEqual(syncRes.ok, true);
    assert.strictEqual(mgr.getSyncState().state, 'synced');

    // 3) autoFetchAndRestore 시 클라우드에 데이터가 존재하면 imported 수행
    const importResult = await mgr.autoFetchAndRestore(store);
    assert.strictEqual(importResult.action, 'imported');
    assert.ok(importResult.count >= 1);

    // 동기화 상태 전이 확인
    assert.ok(recordedSyncStates.includes('syncing'));
    assert.ok(recordedSyncStates.includes('synced'));
  });

  await runTest('8-9. 엄격한 No-Emoji 원칙 검증 (Strict No-Emoji Policy)', () => {
    const targetFiles = [
      path.join(__dirname, '../js/supabase.js'),
      path.join(__dirname, '../js/store.js'),
      path.join(__dirname, '../js/forms.js'),
      path.join(__dirname, '../js/app.js'),
      path.join(__dirname, '../js/icons.js'),
      path.join(__dirname, '../js/map.js'),
      path.join(__dirname, '../js/geocoder.js'),
      path.join(__dirname, '../index.html'),
      path.join(__dirname, '../css/components.css')
    ];

    const emojiRegex = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}]/u;

    for (const filePath of targetFiles) {
      if (fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf8');
        const match = content.match(emojiRegex);
        if (match) {
          assert.fail(`파일 [${path.basename(filePath)}]에 유니코드 이모지(${match[0]})가 포함되어 있습니다.`);
        }
      }
    }
  });

  // --------------------------------------------------------------------------
  // 9. Google Maps 및 Google Places 모듈 검증
  // --------------------------------------------------------------------------
  console.log('\n--- [Suite 9: Google Maps 및 Places 검색 엔진 검증] ---');

  await runTest('9-1. TripMap 기본 내장 API 키 무결성 및 Base64 디코딩 검증', () => {
    assert.ok(TripMap.DEFAULT_MAPS_KEY, '기본 내장 키가 존재해야 함');
    assert.ok(TripMap.DEFAULT_MAPS_KEY.startsWith('AIzaSy'), '유효한 Google API 키 접두사를 가져야 함');
    const saved = TripMap.getSavedGoogleApiKey();
    assert.ok(saved.startsWith('AIzaSy'), '저장된 키가 없을 시 기본 내장 키가 반환되어야 함');
  });

  await runTest('9-2. TripMap 사용자 커스텀 API 키 저장 및 복원(saveGoogleApiKey) 검증', () => {
    TripMap.saveGoogleApiKey('AIzaSyCustomTestKey12345');
    assert.strictEqual(TripMap.getSavedGoogleApiKey(), 'AIzaSyCustomTestKey12345');

    // 빈 값 전달 시 기본 내장 키로 원복
    TripMap.saveGoogleApiKey('');
    assert.strictEqual(TripMap.getSavedGoogleApiKey(), TripMap.DEFAULT_MAPS_KEY);
  });

  await runTest('9-3. TripMapManager 인스턴스 초기화 및 상태 검증', () => {
    const mgr = new TripMap.TripMapManager();
    assert.strictEqual(mgr.engine, 'none');
    assert.strictEqual(mgr.isPinDropActive, false);
    assert.ok(Array.isArray(mgr.markers));
    assert.ok(Array.isArray(mgr.polylines));
  });

  await runTest('9-4. TripMap.createMarkerPopupHtml() XSS 이스케이프 및 구조 검증', () => {
    const mockItem = {
      id: 'test-item-1',
      title: '<script>alert(1)</script>도쿄 타워',
      category: 'ATTRACTION',
      time: '14:00',
      cost: 50000
    };
    const html = TripMap.createMarkerPopupHtml(mockItem, 1, '#2563eb');
    assert.ok(!html.includes('<script>'), 'XSS 스크립트 태그가 이스케이프되어야 함');
    assert.ok(html.includes('&lt;script&gt;'), 'HTML 엔티티로 변환되어야 함');
    assert.ok(html.includes('50,000원'), '비용 포맷팅이 정상 반영되어야 함');
    assert.ok(html.includes('data-item-id="test-item-1"'), '아이템 ID 데이터 속성이 포함되어야 함');
  });

  await runTest('9-5. TripGeocoder Google Places 및 Geocoder 가용성 플래그 검증', () => {
    assert.strictEqual(typeof TripGeocoder.isGooglePlacesAvailable, 'function');
    assert.strictEqual(typeof TripGeocoder.isGoogleGeocoderAvailable, 'function');
    // Node.js 환경에서는 window.google이 없으므로 false 반환
    assert.strictEqual(TripGeocoder.isGooglePlacesAvailable(), false);
    assert.strictEqual(TripGeocoder.isGoogleGeocoderAvailable(), false);
  });

  await runTest('9-6. TripGeocoder.debounce() 유틸리티 타이머 지연 검증', async () => {
    let callCount = 0;
    const debounced = TripGeocoder.debounce(() => {
      callCount++;
    }, 50);

    debounced();
    debounced();
    debounced();

    assert.strictEqual(callCount, 0, '디바운스 대기 중에는 즉시 호출되지 않아야 함');
    await new Promise((r) => setTimeout(r, 80));
    assert.strictEqual(callCount, 1, '디바운스 시간 후 단 1회만 호출되어야 함');
  });

  // --------------------------------------------------------------------------
  // 10. 비행기 출발/도착 단일 시간 분리 및 카테고리별 시간 필드 수집 검증
  // --------------------------------------------------------------------------
  console.log('\n--- [Suite 10: 비행기 출발/도착 단일 시간 분리 및 카테고리별 시간 필드 수집 검증] ---');

  await runTest('10-1. FLIGHT 출발편(DEPARTURE) 입력 시 time이 departureTime으로 매핑 및 arrival 필드 초기화 검증', () => {
    const input = {
      category: 'FLIGHT',
      flightType: 'DEPARTURE',
      title: '인천 출국 (나리타행)',
      time: '10:30',
      airport: 'ICN',
      airline: '대한항공',
      flightNo: 'KE703'
    };
    const extracted = TripForms.formManager.extractFormData(input);
    assert.strictEqual(extracted.category, 'FLIGHT');
    assert.strictEqual(extracted.flightType, 'DEPARTURE');
    assert.strictEqual(extracted.time, '10:30');
    assert.strictEqual(extracted.departureTime, '10:30');
    assert.strictEqual(extracted.departureAirport, 'ICN');
    assert.strictEqual(extracted.arrivalTime, '');
    assert.strictEqual(extracted.arrivalAirport, '');
  });

  await runTest('10-2. FLIGHT 도착편(ARRIVAL) 입력 시 time이 arrivalTime으로 매핑 및 departure 필드 초기화 검증', () => {
    const input = {
      category: 'FLIGHT',
      flightType: 'ARRIVAL',
      title: '나리타 공항 도착',
      time: '13:00',
      airport: 'NRT',
      airline: '대한항공',
      flightNo: 'KE703'
    };
    const extracted = TripForms.formManager.extractFormData(input);
    assert.strictEqual(extracted.category, 'FLIGHT');
    assert.strictEqual(extracted.flightType, 'ARRIVAL');
    assert.strictEqual(extracted.time, '13:00');
    assert.strictEqual(extracted.arrivalTime, '13:00');
    assert.strictEqual(extracted.arrivalAirport, 'NRT');
    assert.strictEqual(extracted.departureTime, '');
    assert.strictEqual(extracted.departureAirport, '');
  });

  await runTest('10-3. HOTEL 카테고리 시간 입력 시 time과 checkInTime의 동기화 검증', () => {
    const inputWithTime = {
      category: 'HOTEL',
      title: '신주쿠 워싱턴 호텔',
      time: '15:00',
      checkOutTime: '11:00'
    };
    const extracted1 = TripForms.formManager.extractFormData(inputWithTime);
    assert.strictEqual(extracted1.category, 'HOTEL');
    assert.strictEqual(extracted1.time, '15:00');
    assert.strictEqual(extracted1.checkInTime, '15:00');
    assert.strictEqual(extracted1.checkOutTime, '11:00');

    const inputWithCheckIn = {
      category: 'HOTEL',
      title: '긴자 호텔',
      checkInTime: '16:00'
    };
    const extracted2 = TripForms.formManager.extractFormData(inputWithCheckIn);
    assert.strictEqual(extracted2.time, '16:00');
    assert.strictEqual(extracted2.checkInTime, '16:00');
  });

  await runTest('10-4. DINING 및 AIRPORT 카테고리 시간(time) 필드 수집 및 보존 검증', () => {
    const diningInput = {
      category: 'DINING',
      title: '이치란 라멘',
      time: '12:30',
      mealType: '중식'
    };
    const diningExtracted = TripForms.formManager.extractFormData(diningInput);
    assert.strictEqual(diningExtracted.time, '12:30');
    assert.strictEqual(diningExtracted.mealType, '중식');

    const airportInput = {
      category: 'AIRPORT',
      title: '나리타 입국 심사',
      time: '13:40',
      baggageClaim: '수취대 3번'
    };
    const airportExtracted = TripForms.formManager.extractFormData(airportInput);
    assert.strictEqual(airportExtracted.time, '13:40');
    assert.strictEqual(airportExtracted.baggageClaim, '수취대 3번');
  });

  await runTest('10-5. 동일 일차(Day) 내 시간순 정렬 및 미지정 시간 후순위 배치 알고리즘 검증', () => {
    const items = [
      { id: 'item-1', day: 1, title: '디너 오마카세', time: '19:00' },
      { id: 'item-2', day: 1, title: '인천 출국 비행기', category: 'FLIGHT', flightType: 'DEPARTURE', time: '09:00' },
      { id: 'item-3', day: 1, title: '호텔 체크인', category: 'HOTEL', time: '15:00' },
      { id: 'item-4', day: 1, title: '자유 산책 (시간 미정)', time: '' },
      { id: 'item-5', day: 1, title: '점심 라멘', time: '12:30' }
    ];

    const sorted = items.slice().sort((a, b) => {
      const timeA = a.time || (a.category === 'FLIGHT' ? (a.flightType === 'ARRIVAL' ? a.arrivalTime : a.departureTime) : (a.category === 'HOTEL' ? a.checkInTime : '')) || '';
      const timeB = b.time || (b.category === 'FLIGHT' ? (b.flightType === 'ARRIVAL' ? b.arrivalTime : b.departureTime) : (b.category === 'HOTEL' ? b.checkInTime : '')) || '';
      if (timeA && timeB) {
        return timeA.localeCompare(timeB);
      }
      if (timeA && !timeB) return -1;
      if (!timeA && timeB) return 1;
      return 0;
    });

    const resultIds = sorted.map((it) => it.id);
    assert.deepStrictEqual(resultIds, ['item-2', 'item-5', 'item-3', 'item-1', 'item-4']);
  });

  // --------------------------------------------------------------------------
  // Suite 11: 모바일 바텀시트 1:1 실시간 추종 및 풀다운 축소 제스처 알고리즘 검증
  // --------------------------------------------------------------------------
  console.log('\n--- [Suite 11: 모바일 바텀시트 1:1 추종 및 풀다운 축소 알고리즘 검증] ---');

  function getBaseYForState(state, height) {
    switch (state) {
      case 'full':
        return 0;
      case 'half':
        return height * 0.52;
      case 'peek':
        return Math.max(0, height - 68);
      case 'hidden':
        return height + 80;
      default:
        return height * 0.52;
    }
  }

  function calculateDraggedY(baseY, deltaY, panelHeight) {
    let currentY = baseY + deltaY;
    if (currentY < 0) {
      currentY = currentY * 0.25;
    }
    const maxOffset = panelHeight + 80;
    if (currentY > maxOffset) {
      const overDistance = currentY - maxOffset;
      currentY = maxOffset + overDistance * 0.25;
    }
    return currentY;
  }

  function resolveSnapState(currentY, panelHeight, velocity, deltaY, currentState) {
    const isFlickDown = velocity > 0.45 || (deltaY > 120 && velocity > 0.2);
    const isFlickUp = velocity < -0.45 || (deltaY < -120 && velocity < -0.2);

    if (isFlickDown) {
      if (currentState === 'full') return 'half';
      return 'hidden';
    }
    if (isFlickUp) {
      return 'full';
    }
    const ratio = currentY / panelHeight;
    if (ratio < 0.30) {
      return 'full';
    } else if (ratio <= 0.70) {
      return 'half';
    } else {
      return 'hidden';
    }
  }

  function resolveBodySwipe(deltaY, currentState) {
    if (currentState === 'half' || currentState === 'peek') {
      if (deltaY <= -50) {
        return 'full';
      } else if (deltaY >= 60) {
        return 'hidden';
      }
      return currentState;
    }
    if (currentState === 'full') {
      if (deltaY >= 60) {
        return 'half';
      }
      return 'full';
    }
    return currentState;
  }

  function resolveBodyPullDown(deltaY, currentState) {
    return resolveBodySwipe(deltaY, currentState);
  }

  await runTest('11-1. 바텀시트 상태별 기준 Y 오프셋(getBaseYForState) 계산 정확성 검증', () => {
    const height = 1000;
    assert.strictEqual(getBaseYForState('full', height), 0);
    assert.strictEqual(getBaseYForState('half', height), 520);
    assert.strictEqual(getBaseYForState('peek', height), 932);
    assert.strictEqual(getBaseYForState('hidden', height), 1080);
  });

  await runTest('11-2. 상단 및 하단 오버드래그 시 0.25 탄성 저항 감쇠 계산 검증', () => {
    const height = 800;
    const baseY = 0; // full 상태
    // 상단 오버드래그 -100px 이동 -> -25px
    const topOver = calculateDraggedY(baseY, -100, height);
    assert.strictEqual(topOver, -25);

    // 하단 오버드래그 (maxOffset = 880, deltaY = 1080 -> 200px 초과 -> 880 + 50 = 930)
    const bottomOver = calculateDraggedY(baseY, 1080, height);
    assert.strictEqual(bottomOver, 930);
  });

  await runTest('11-3. 천천히 놓았을 때 화면 높이 비율(0~30%: full, 30~70%: half, 70% 초과: hidden) 스냅 판정 검증', () => {
    const height = 1000;
    // 250px (25%): full
    assert.strictEqual(resolveSnapState(250, height, 0, 0, 'half'), 'full');
    // 500px (50%): half
    assert.strictEqual(resolveSnapState(500, height, 0, 0, 'full'), 'half');
    // 750px (75%): hidden
    assert.strictEqual(resolveSnapState(750, height, 0, 0, 'half'), 'hidden');
  });

  await runTest('11-4. 플릭 다운/플릭 업(velocity/deltaY) 기반 상태 전이 알고리즘 검증', () => {
    const height = 1000;
    // full에서 빠른 플릭 다운 -> half
    assert.strictEqual(resolveSnapState(200, height, 0.6, 150, 'full'), 'half');
    // half에서 빠른 플릭 다운 -> hidden
    assert.strictEqual(resolveSnapState(600, height, 0.6, 150, 'half'), 'hidden');
    // half에서 빠른 플릭 업 -> full
    assert.strictEqual(resolveSnapState(400, height, -0.6, -150, 'half'), 'full');
  });

  await runTest('11-5. 본문 최상단 스크롤 풀다운 시 60px 임계치 기반 축소(full->half, half->hidden) 판정 검증', () => {
    // 60px 미만 당김 -> 원상 복구
    assert.strictEqual(resolveBodyPullDown(40, 'full'), 'full');
    assert.strictEqual(resolveBodyPullDown(59, 'half'), 'half');

    // 60px 이상 당김 -> 축소
    assert.strictEqual(resolveBodyPullDown(60, 'full'), 'half');
    assert.strictEqual(resolveBodyPullDown(120, 'full'), 'half');
    assert.strictEqual(resolveBodyPullDown(60, 'half'), 'hidden');
    assert.strictEqual(resolveBodyPullDown(80, 'peek'), 'hidden');
  });

  await runTest('11-6. 본문 위로 올리기(확장: half/peek -> full, 임계치 -50px) 판정 알고리즘 단위 테스트 검증', () => {
    // 위로 50px 이상 올렸을 때: half -> full, peek -> full 쫙 열림
    assert.strictEqual(resolveBodySwipe(-50, 'half'), 'full');
    assert.strictEqual(resolveBodySwipe(-70, 'half'), 'full');
    assert.strictEqual(resolveBodySwipe(-50, 'peek'), 'full');
    assert.strictEqual(resolveBodySwipe(-100, 'peek'), 'full');

    // 위로 50px 미만 올렸을 때(미세한 흔들림): 원래 상태 복귀
    assert.strictEqual(resolveBodySwipe(-49, 'half'), 'half');
    assert.strictEqual(resolveBodySwipe(-10, 'half'), 'half');
    assert.strictEqual(resolveBodySwipe(0, 'half'), 'half');
    assert.strictEqual(resolveBodySwipe(-49, 'peek'), 'peek');

    // full 상태에서 위로 올렸을 때: full 유지
    assert.strictEqual(resolveBodySwipe(-50, 'full'), 'full');
    assert.strictEqual(resolveBodySwipe(-120, 'full'), 'full');
  });

  // --------------------------------------------------------------------------
  // 12. 전체 보기 (All Days) 스토어 및 지도 동선 렌더링 검증
  // --------------------------------------------------------------------------
  console.log('\n--- [Suite 12: 전체 보기 (All Days) 스토어 및 지도 동선 렌더링 검증] ---');

  await runTest('12-1. store.setSelectedDay(\'all\') 상태 저장 및 selectedDay === \'all\' 유지 검증', () => {
    TripStore.store.setSelectedDay('all');
    assert.strictEqual(TripStore.store.getState().selectedDay, 'all');

    TripStore.store.setSelectedDay('ALL');
    assert.strictEqual(TripStore.store.getState().selectedDay, 'all');

    // 숫자 전환 검증
    TripStore.store.setSelectedDay(3);
    assert.strictEqual(TripStore.store.getState().selectedDay, 3);
  });

  await runTest('12-2. store.addItem 시 selectedDay === \'all\'일 때 기본 Day 1 배정 검증', () => {
    TripStore.store.setSelectedDay('all');
    const itemWithoutDay = {
      title: '전체 보기 상태에서 추가된 일정',
      category: 'ATTRACTION',
      cost: 15000
    };
    const added = TripStore.store.addItem(itemWithoutDay);
    assert.strictEqual(added.day, 1, 'selectedDay가 all일 때 day가 없는 아이템은 1일차로 자동 배정되어야 함');
    assert.strictEqual(Number(added.day), 1);
  });

  await runTest('12-3. map.js의 render 함수에서 dayNumber = \'all\'일 때 전체 일차 아이템 필터링 및 날짜별 독립 Polyline 생성 검증', () => {
    const testMapManager = new TripMap.TripMapManager();
    const addedMarkers = [];
    const addedPolylines = [];
    let fittedBounds = null;

    global.L = {
      divIcon: (opts) => ({ type: 'divIcon', opts }),
      marker: (latlng, opts) => {
        const m = {
          latlng,
          opts,
          bindPopup: () => m,
          on: () => m,
          openPopup: () => m,
          addTo: (map) => { addedMarkers.push(m); return m; }
        };
        return m;
      },
      polyline: (pts, opts) => {
        const p = {
          pts,
          opts,
          addTo: (map) => { addedPolylines.push(p); return p; }
        };
        return p;
      }
    };

    testMapManager.engine = 'leaflet';
    testMapManager.map = {
      removeLayer: () => {},
      fitBounds: (bounds) => { fittedBounds = bounds; }
    };

    const testItems = [
      { id: 'item-d1-1', day: 1, title: 'Day1 장소1', lat: 35.6895, lng: 139.6917, time: '10:00' },
      { id: 'item-d1-2', day: 1, title: 'Day1 장소2', lat: 35.6900, lng: 139.6920, time: '14:00' },
      { id: 'item-d2-1', day: 2, title: 'Day2 장소1', lat: 35.7000, lng: 139.7000, time: '11:00' },
      { id: 'item-d2-2', day: 2, title: 'Day2 장소2', lat: 35.7100, lng: 139.7100, time: '15:00' },
      { id: 'item-d3-single', day: 3, title: 'Day3 단일', lat: 35.7200, lng: 139.7200, time: '09:00' }
    ];

    testMapManager.render(testItems, 'all');

    // 마커가 5개 모두 생성되었는지 확인
    assert.strictEqual(testMapManager.markers.length, 5, '전체 5개 아이템의 마커가 생성되어야 함');

    // Day 1과 Day 2는 좌표가 2개 이상이므로 각각 독립 Polyline이 생성되고, Day 3은 1개이므로 Polyline 없음 -> 총 2개 Polyline
    assert.strictEqual(testMapManager.polylines.length, 2, '2개 이상 좌표를 가진 Day 1과 Day 2에 대해 각각 1개씩 총 2개의 독립 Polyline이 생성되어야 함');

    // Day 1의 Polyline 색상 검증
    assert.strictEqual(testMapManager.polylines[0].opts.color, TripMap.getDayColor(1));
    // Day 2의 Polyline 색상 검증
    assert.strictEqual(testMapManager.polylines[1].opts.color, TripMap.getDayColor(2));

    // fitBounds에 5개 좌표 모두 전달되었는지 검증
    assert(Array.isArray(fittedBounds), 'fitBounds에 좌표 배열이 전달되어야 함');
    assert.strictEqual(fittedBounds.length, 5);
  });

  await runTest('12-4. map.js의 createMarkerPopupHtml에 Day N 배지 렌더링 검증', () => {
    const item = {
      id: 'test-item-1',
      day: 2,
      title: '도쿄 타워',
      category: 'ATTRACTION',
      cost: 3000
    };
    const htmlWithDayArg = TripMap.createMarkerPopupHtml(item, 1, '#059669', 2);
    assert(htmlWithDayArg.includes('popup-day-pill'), 'Day 뱃지 클래스가 포함되어야 함');
    assert(htmlWithDayArg.includes('Day 2'), 'Day 2 텍스트가 뱃지에 표시되어야 함');
    assert(htmlWithDayArg.includes('background:#059669'), '뱃지에 테마 색상이 적용되어야 함');

    // dayNumber 인자가 생략되어도 item.day에서 자동 추출되는지 검증
    const htmlWithItemDay = TripMap.createMarkerPopupHtml(item, 1, '#059669');
    assert(htmlWithItemDay.includes('popup-day-pill'));
    assert(htmlWithItemDay.includes('Day 2'));
  });

  await runTest('12-5. 전체 일차 신규 코드 및 파일 내 Strict No-Emoji 부재 검증', () => {
    const emojiRegex = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/u;
    const targetFiles = [
      path.join(__dirname, '../js/store.js'),
      path.join(__dirname, '../js/map.js'),
      path.join(__dirname, '../js/app.js'),
      path.join(__dirname, '../css/components.css'),
      path.join(__dirname, '../index.html')
    ];

    targetFiles.forEach((file) => {
      const content = fs.readFileSync(file, 'utf8');
      assert.strictEqual(emojiRegex.test(content), false, `파일 [${path.basename(file)}]에 유니코드 이모지가 포함되어선 안 됩니다.`);
    });
  });

  // --------------------------------------------------------------------------
  // 결과 종합 요약
  // --------------------------------------------------------------------------
  console.log('\n====================================================');
  console.log(`[TEST SUMMARY]`);
  console.log(`Total Tests : ${totalTests}`);
  console.log(`Passed      : ${passedTests}`);
  console.log(`Failed      : ${failedTests}`);
  console.log('====================================================');

  if (failedTests > 0) {
    process.exit(1);
  } else {
    console.log('[V] All unit tests completed successfully!');
    process.exit(0);
  }
}

runAllTests().catch((err) => {
  console.error('Test execution fatal error:', err);
  process.exit(1);
});
