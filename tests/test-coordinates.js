/**
 * @intent 구글맵 좌표 복사 붙여넣기 및 파싱, forms.js 렌더링 단위 테스트
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

const assert = require('assert');
const path = require('path');

const TripForms = require(path.join(__dirname, '../js/forms.js'));
const { parseCoordinates, formManager } = TripForms;

console.log('--- [구글맵 좌표 파싱 엔진 정밀 단위 테스트] ---');

// 1. 기본 쉼표+공백 형식
{
  const res = parseCoordinates('35.6585805, 139.7454329');
  assert.ok(res, '기본 좌표 파싱 성공해야 함');
  assert.strictEqual(res.lat, 35.6585805);
  assert.strictEqual(res.lng, 139.7454329);
  console.log('[PASS] 1. 쉼표+공백 형식 파싱 (35.6585805, 139.7454329)');
}

// 2. 공백만 있는 형식
{
  const res = parseCoordinates('35.6585 139.7454');
  assert.ok(res, '공백 구분 파싱 성공해야 함');
  assert.strictEqual(res.lat, 35.6585);
  assert.strictEqual(res.lng, 139.7454);
  console.log('[PASS] 2. 공백 구분 형식 파싱 (35.6585 139.7454)');
}

// 3. 괄호 포함 형식
{
  const res = parseCoordinates('(35.6585, 139.7454)');
  assert.ok(res, '괄호 포함 파싱 성공해야 함');
  assert.strictEqual(res.lat, 35.6585);
  assert.strictEqual(res.lng, 139.7454);
  console.log('[PASS] 3. 괄호 포함 형식 파싱 ((35.6585, 139.7454))');
}

// 4. 슬래시 구분 형식
{
  const res = parseCoordinates('37.5665 / 126.9780');
  assert.ok(res, '슬래시 구분 파싱 성공해야 함');
  assert.strictEqual(res.lat, 37.5665);
  assert.strictEqual(res.lng, 126.9780);
  console.log('[PASS] 4. 슬래시 구분 형식 파싱 (37.5665 / 126.9780)');
}

// 5. 음수 좌표 (남반구/서반구)
{
  const res = parseCoordinates('-33.8688, 151.2093');
  assert.ok(res, '음수 위도 파싱 성공해야 함');
  assert.strictEqual(res.lat, -33.8688);
  assert.strictEqual(res.lng, 151.2093);
  console.log('[PASS] 5. 음수 위도 파싱 (-33.8688, 151.2093)');
}

// 6. 유효 범위 초과 (위도 > 90, 경도 > 180)
{
  assert.strictEqual(parseCoordinates('95.1234, 120.0000'), null, '위도 > 90은 null이어야 함');
  assert.strictEqual(parseCoordinates('35.0000, 195.0000'), null, '경도 > 180은 null이어야 함');
  assert.strictEqual(parseCoordinates('-91.0000, 120.0000'), null, '위도 < -90은 null이어야 함');
  assert.strictEqual(parseCoordinates('35.0000, -185.0000'), null, '경도 < -180은 null이어야 함');
  console.log('[PASS] 6. 유효 범위 초과 좌표 방어');
}

// 7. 빈 문자열 및 잘못된 텍스트 방어
{
  assert.strictEqual(parseCoordinates(''), null);
  assert.strictEqual(parseCoordinates(null), null);
  assert.strictEqual(parseCoordinates('도쿄 타워'), null);
  assert.strictEqual(parseCoordinates('abc, def'), null);
  console.log('[PASS] 7. 빈 문자열 및 비정상 입력 방어');
}

// 8. forms.js 렌더링 HTML 검증
{
  const htmlWithCoord = formManager.renderFormHtml({ lat: 35.65858, lng: 139.74543 });
  assert.ok(htmlWithCoord.includes('id="coord-paste-input"'), 'coord-paste-input 필드가 존재해야 함');
  assert.ok(htmlWithCoord.includes('id="btn-apply-coord-paste"'), 'btn-apply-coord-paste 버튼이 존재해야 함');
  assert.ok(htmlWithCoord.includes('id="item-lat"'), 'item-lat 필드가 존재해야 함');
  assert.ok(htmlWithCoord.includes('id="item-lng"'), 'item-lng 필드가 존재해야 함');
  assert.ok(htmlWithCoord.includes('id="btn-pick-on-map"'), 'btn-pick-on-map 버튼이 존재해야 함');
  assert.ok(htmlWithCoord.includes('id="btn-clear-location"'), 'btn-clear-location 버튼이 존재해야 함');
  assert.ok(htmlWithCoord.includes('35.658580, 139.745430'), '기존 좌표가 coord-paste-input에 포맷팅되어 표시되어야 함');
  console.log('[PASS] 8. forms.js 구글맵 좌표 및 직접 입력 UI 마크업 렌더링 검증');
}

console.log('[V] All coordinate parsing and form rendering tests passed successfully!');
