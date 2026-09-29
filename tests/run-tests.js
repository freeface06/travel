/**
 * @intent 정산 엔진, 환율 환산, 스토어 상태 전이 종합 단위 테스트 스크립트
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
global.TripSupabase = TripSupabase;
global.TripStore = TripStore;

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
