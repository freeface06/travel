/**
 * @intent 6대 카테고리(비행기, 공항, 숙소, 명소, 식당, 교통) 동적 폼 및 입력 검증 모듈
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripForms = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * XSS 방지를 위한 HTML 이스케이프 유틸리티
   */
  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * 카테고리별 메타 정보
   */
  const CATEGORIES = {
    FLIGHT: { label: '비행기', icon: 'FLIGHT', color: '#2563eb' },
    AIRPORT: { label: '공항', icon: 'AIRPORT', color: '#0891b2' },
    HOTEL: { label: '숙소', icon: 'HOTEL', color: '#7c3aed' },
    ATTRACTION: { label: '관광명소', icon: 'ATTRACTION', color: '#059669' },
    DINING: { label: '식당/카페', icon: 'DINING', color: '#d97706' },
    TRANSIT: { label: '교통/이동', icon: 'TRANSIT', color: '#4b5563' }
  };

  /**
   * 동적 폼 렌더러
   */
  class FormManager {
    constructor() {
      this.currentCategory = 'ATTRACTION';
      this.editingItemId = null;
      this.uploadedPhotoDataUrl = null;
      this.uploadedPhotoId = null;
    }

    /**
     * 모달 폼 필드 HTML 생성 (카테고리별 세부 필드 포함)
     * @param {object|null} initialData - 수정 시 기존 데이터
     * @param {Array<string>} participants - 참가자 목록
     * @returns {string} 폼 HTML
     */
    renderFormHtml(initialData = null, participants = []) {
      const data = initialData || {};
      const cat = data.category || this.currentCategory || 'ATTRACTION';
      this.currentCategory = cat;
      this.editingItemId = data.id || null;
      this.uploadedPhotoId = data.photoId || null;
      this.uploadedPhotoDataUrl = data.photoDataUrl || null;

      const payerOptions = participants.map((p) => {
        const selected = (data.payer || '') === p ? ' selected' : '';
        return `<option value="${escapeHtml(p)}"${selected}>${escapeHtml(p)}</option>`;
      }).join('');

      return `
        <form id="item-editor-form" class="editor-form" novalidate>
          <input type="hidden" name="itemId" value="${escapeHtml(data.id || '')}" />
          
          <!-- 카테고리 탭 선택기 -->
          <div class="form-group">
            <label class="form-label">카테고리 선택</label>
            <div class="category-pill-group" id="category-selector">
              ${Object.keys(CATEGORIES).map((key) => {
                const c = CATEGORIES[key];
                const active = key === cat ? ' active' : '';
                return `
                  <button type="button" class="category-pill${active}" data-category="${key}">
                    ${typeof Icons !== 'undefined' ? Icons.getIcon(c.icon, { size: 16 }) : ''}
                    <span>${c.label}</span>
                  </button>
                `;
              }).join('')}
            </div>
            <input type="hidden" name="category" id="input-category" value="${cat}" />
          </div>

          <!-- 공통 기본 정보 -->
          <div class="form-row">
            <div class="form-group flex-2">
              <label class="form-label" for="item-title">일정 / 장소명 <span class="required">*</span></label>
              <input type="text" id="item-title" name="title" class="form-control" required 
                     placeholder="예: 센소지, 도쿄타워, 나리타 익스프레스" value="${escapeHtml(data.title || '')}" />
            </div>
            <div class="form-group flex-1">
              <label class="form-label" for="item-day">일차 (Day)</label>
              <input type="number" id="item-day" name="day" class="form-control" min="1" max="99" 
                     value="${escapeHtml(data.day || 1)}" />
            </div>
          </div>

          <!-- 카테고리별 특화 필드 섹션 -->
          <div id="dynamic-category-fields">
            ${this.renderCategorySpecificFields(cat, data)}
          </div>

          <!-- 위치 검색 및 좌표 지정 섹션 -->
          <div class="form-group location-section">
            <label class="form-label">위치 좌표 설정 (지도 표시)</label>
            <div class="location-search-box">
              <input type="text" id="place-search-input" class="form-control" 
                     placeholder="주소나 장소 검색 (Nominatim OpenStreetMap)" autocomplete="off" />
              <button type="button" id="btn-search-place" class="btn btn-secondary">
                ${typeof Icons !== 'undefined' ? Icons.getIcon('SEARCH', { size: 16 }) : ''}
                <span>검색</span>
              </button>
              <button type="button" id="btn-pick-on-map" class="btn btn-outline" title="지도에서 직접 클릭하여 위치 선택">
                ${typeof Icons !== 'undefined' ? Icons.getIcon('LOCATION_TARGET', { size: 16 }) : ''}
                <span>지도 핀 지정</span>
              </button>
            </div>
            <div id="search-results-dropdown" class="search-dropdown hidden"></div>

            <div class="form-row coords-row">
              <div class="form-group flex-1">
                <input type="number" step="any" id="item-lat" name="lat" class="form-control text-sm" 
                       placeholder="위도(Lat)" value="${data.lat !== undefined ? data.lat : ''}" />
              </div>
              <div class="form-group flex-1">
                <input type="number" step="any" id="item-lng" name="lng" class="form-control text-sm" 
                       placeholder="경도(Lng)" value="${data.lng !== undefined ? data.lng : ''}" />
              </div>
            </div>
          </div>

          <!-- 비용 및 결제자 정보 -->
          <div class="form-row expense-row">
            <div class="form-group flex-2">
              <label class="form-label" for="item-cost">비용 / 지출액</label>
              <input type="number" id="item-cost" name="cost" class="form-control" min="0" step="any" 
                     placeholder="0" value="${escapeHtml(data.cost || '')}" />
            </div>
            <div class="form-group flex-1">
              <label class="form-label" for="item-currency">통화</label>
              <select id="item-currency" name="currency" class="form-control">
                <option value="KRW"${(data.currency || 'KRW') === 'KRW' ? ' selected' : ''}>KRW (원)</option>
                <option value="JPY"${(data.currency || '') === 'JPY' ? ' selected' : ''}>JPY (엔)</option>
                <option value="USD"${(data.currency || '') === 'USD' ? ' selected' : ''}>USD ($)</option>
                <option value="EUR"${(data.currency || '') === 'EUR' ? ' selected' : ''}>EUR (€)</option>
                <option value="CNY"${(data.currency || '') === 'CNY' ? ' selected' : ''}>CNY (위안)</option>
              </select>
            </div>
            <div class="form-group flex-1">
              <label class="form-label" for="item-payer">결제자</label>
              <select id="item-payer" name="payer" class="form-control">
                ${payerOptions}
                <option value="공통"${(data.payer || '') === '공통' ? ' selected' : ''}>공통 회비</option>
              </select>
            </div>
          </div>

          <!-- 사진 첨부 (E-티켓, 영수증, 명소 사진) -->
          <div class="form-group photo-upload-group">
            <label class="form-label">사진 첨부 (티켓/바우처/현장 사진)</label>
            <div class="photo-upload-container">
              <input type="file" id="item-photo-input" accept="image/*" class="hidden-file-input" />
              <button type="button" id="btn-trigger-photo" class="btn btn-outline">
                ${typeof Icons !== 'undefined' ? Icons.getIcon('IMAGE', { size: 16 }) : ''}
                <span>사진 선택 (최대 1200px 자동 압축)</span>
              </button>
              <div id="photo-preview-wrapper" class="photo-preview-wrapper ${this.uploadedPhotoDataUrl ? '' : 'hidden'}">
                <img id="photo-preview-img" src="${escapeHtml(this.uploadedPhotoDataUrl || '')}" alt="미리보기" />
                <button type="button" id="btn-remove-photo" class="btn-remove-photo" title="사진 삭제">
                  ${typeof Icons !== 'undefined' ? Icons.getIcon('CLOSE', { size: 14 }) : 'X'}
                </button>
              </div>
            </div>
          </div>

          <!-- 메모 및 관람 팁 -->
          <div class="form-group">
            <label class="form-label" for="item-memo">상세 메모 & 팁</label>
            <textarea id="item-memo" name="memo" class="form-control" rows="2" 
                      placeholder="준비물, 주의사항, 환승 팁 등 자유 기록">${escapeHtml(data.memo || '')}</textarea>
          </div>

          <!-- 하단 버튼 -->
          <div class="modal-form-actions">
            <button type="button" id="btn-modal-cancel" class="btn btn-secondary">취소</button>
            <button type="submit" class="btn btn-primary">
              ${typeof Icons !== 'undefined' ? Icons.getIcon('CHECK', { size: 16 }) : ''}
              <span>${data.id ? '수정 완료' : '일정에 추가'}</span>
            </button>
          </div>
        </form>
      `;
    }

    /**
     * 카테고리별 세부 전용 필드 렌더링
     */
    renderCategorySpecificFields(category, data = {}) {
      switch (category) {
        case 'FLIGHT':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">항공사</label>
                  <input type="text" name="airline" class="form-control" placeholder="예: 대한항공, 아시아나" value="${escapeHtml(data.airline || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">편명</label>
                  <input type="text" name="flightNo" class="form-control" placeholder="예: KE703, OZ102" value="${escapeHtml(data.flightNo || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">출발 공항 (IATA)</label>
                  <input type="text" name="departureAirport" class="form-control" placeholder="예: ICN" maxlength="4" value="${escapeHtml(data.departureAirport || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">도착 공항 (IATA)</label>
                  <input type="text" name="arrivalAirport" class="form-control" placeholder="예: NRT, HND" maxlength="4" value="${escapeHtml(data.arrivalAirport || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">출발 시각</label>
                  <input type="time" name="departureTime" class="form-control" value="${escapeHtml(data.departureTime || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">도착 시각</label>
                  <input type="time" name="arrivalTime" class="form-control" value="${escapeHtml(data.arrivalTime || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">터미널 / 게이트</label>
                  <input type="text" name="terminalGate" class="form-control" placeholder="예: T2 240번" value="${escapeHtml(data.terminalGate || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">좌석 번호</label>
                  <input type="text" name="seat" class="form-control" placeholder="예: 28A, 28B" value="${escapeHtml(data.seat || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">예약 번호 (PNR)</label>
                  <input type="text" name="bookingRef" class="form-control" placeholder="예: QX81K2" value="${escapeHtml(data.bookingRef || '')}" />
                </div>
              </div>
            </div>
          `;

        case 'AIRPORT':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">수하물 수취대 (Carousel)</label>
                  <input type="text" name="baggageClaim" class="form-control" placeholder="예: 수취대 7번" value="${escapeHtml(data.baggageClaim || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">시내 환승 수단</label>
                  <input type="text" name="transitToCity" class="form-control" placeholder="예: 공항철도, 리무진 버스" value="${escapeHtml(data.transitToCity || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">픽업 위치 / 탑승 시각</label>
                  <input type="text" name="pickupInfo" class="form-control" placeholder="예: 1층 4번 승차홈 (14:30)" value="${escapeHtml(data.pickupInfo || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">입국 / 세관 메모</label>
                  <input type="text" name="customsMemo" class="form-control" placeholder="예: 전자세관신고 QR 사전 준비" value="${escapeHtml(data.customsMemo || '')}" />
                </div>
              </div>
            </div>
          `;

        case 'HOTEL':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">체크인 시간</label>
                  <input type="text" name="checkInTime" class="form-control" placeholder="예: 15:00" value="${escapeHtml(data.checkInTime || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">체크아웃 시간</label>
                  <input type="text" name="checkOutTime" class="form-control" placeholder="예: 11:00" value="${escapeHtml(data.checkOutTime || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">예약 바우처 번호</label>
                  <input type="text" name="voucherNo" class="form-control" placeholder="예: AGODA-99381" value="${escapeHtml(data.voucherNo || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">도어락 / 키박스 비밀번호</label>
                  <input type="text" name="passcode" class="form-control" placeholder="예: 1045#" value="${escapeHtml(data.passcode || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-2">
                  <label class="form-label">호텔 상세 주소</label>
                  <input type="text" name="address" class="form-control" placeholder="영문 또는 현지 주소" value="${escapeHtml(data.address || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">짐 보관 여부</label>
                  <input type="text" name="luggageStorage" class="form-control" placeholder="예: 체크인 전 무료 가능" value="${escapeHtml(data.luggageStorage || '')}" />
                </div>
              </div>
            </div>
          `;

        case 'ATTRACTION':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">방문 예정 시간</label>
                  <input type="time" name="time" class="form-control" value="${escapeHtml(data.time || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">운영 시간</label>
                  <input type="text" name="openingHours" class="form-control" placeholder="예: 09:00 - 18:00" value="${escapeHtml(data.openingHours || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">예약 상태</label>
                  <input type="text" name="bookingStatus" class="form-control" placeholder="예: 사전 예매 완료, 현장 구매" value="${escapeHtml(data.bookingStatus || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">1인당 입장료</label>
                  <input type="number" name="ticketCostPerPerson" class="form-control" placeholder="0" value="${escapeHtml(data.ticketCostPerPerson || '')}" />
                </div>
              </div>
              <div class="form-group">
                <label class="form-label">관람 꿀팁</label>
                <input type="text" name="tips" class="form-control" placeholder="예: 야경 명당, 일몰 30분 전 입장 추천" value="${escapeHtml(data.tips || '')}" />
              </div>
            </div>
          `;

        case 'DINING':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">식사 분류</label>
                  <select name="mealType" class="form-control">
                    <option value="조식"${(data.mealType || '') === '조식' ? ' selected' : ''}>조식</option>
                    <option value="중식"${(data.mealType || '') === '중식' ? ' selected' : ''}>중식</option>
                    <option value="석식"${(data.mealType || '') === '석식' ? ' selected' : ''}>석식</option>
                    <option value="카페/디저트"${(data.mealType || '') === '카페/디저트' ? ' selected' : ''}>카페 / 디저트</option>
                    <option value="바/주점"${(data.mealType || '') === '바/주점' ? ' selected' : ''}>바 / 이자카야</option>
                  </select>
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">결제 수단</label>
                  <select name="paymentMethod" class="form-control">
                    <option value="카드"${(data.paymentMethod || '') === '카드' ? ' selected' : ''}>신용/체크카드</option>
                    <option value="현금"${(data.paymentMethod || '') === '현금' ? ' selected' : ''}>현금 (Cash)</option>
                    <option value="페이/모바일"${(data.paymentMethod || '') === '페이/모바일' ? ' selected' : ''}>모바일 페이 / 교통카드</option>
                  </select>
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">예약 시간 / 예약자명</label>
                  <input type="text" name="reservedFor" class="form-control" placeholder="예: 18:30 (예약자: 민우)" value="${escapeHtml(data.reservedFor || '')}" />
                </div>
                <div class="form-group flex-2">
                  <label class="form-label">추천 메뉴</label>
                  <input type="text" name="menuRecommendation" class="form-control" placeholder="예: 특상 와규 세트, 말차 파르페" value="${escapeHtml(data.menuRecommendation || '')}" />
                </div>
              </div>
            </div>
          `;

        case 'TRANSIT':
          return `
            <div class="category-field-box">
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">이동 수단</label>
                  <select name="transitMode" class="form-control">
                    <option value="전철/지하철"${(data.transitMode || '') === '전철/지하철' ? ' selected' : ''}>전철 / 지하철</option>
                    <option value="기차 (KTX/신칸센)"${(data.transitMode || '') === '기차 (KTX/신칸센)' ? ' selected' : ''}>기차 / 특급열차</option>
                    <option value="버스"${(data.transitMode || '') === '버스' ? ' selected' : ''}>시내버스 / 고속버스</option>
                    <option value="택시"${(data.transitMode || '') === '택시' ? ' selected' : ''}>택시 / 우버</option>
                    <option value="페리/선박"${(data.transitMode || '') === '페리/선박' ? ' selected' : ''}>페리 / 유람선</option>
                    <option value="도보"${(data.transitMode || '') === '도보' ? ' selected' : ''}>도보</option>
                  </select>
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">탑승 시간</label>
                  <input type="time" name="time" class="form-control" value="${escapeHtml(data.time || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">소요 시간</label>
                  <input type="text" name="duration" class="form-control" placeholder="예: 35분" value="${escapeHtml(data.duration || '')}" />
                </div>
              </div>
              <div class="form-row">
                <div class="form-group flex-1">
                  <label class="form-label">출발지 (역/정류장)</label>
                  <input type="text" name="origin" class="form-control" placeholder="예: 신주쿠역" value="${escapeHtml(data.origin || '')}" />
                </div>
                <div class="form-group flex-1">
                  <label class="form-label">도착지 (역/정류장)</label>
                  <input type="text" name="destination" class="form-control" placeholder="예: 도쿄역" value="${escapeHtml(data.destination || '')}" />
                </div>
              </div>
              <div class="form-group">
                <label class="form-label">플랫폼 / 환승 메모</label>
                <input type="text" name="platformMemo" class="form-control" placeholder="예: 2번 승강장 야마노테선 방면, 환승 1회" value="${escapeHtml(data.platformMemo || '')}" />
              </div>
            </div>
          `;

        default:
          return '';
      }
    }

    /**
     * 폼 제출 데이터 수집 및 객체 생성
     * @param {HTMLFormElement} form 
     * @returns {object} 수집된 일정 객체
     */
    extractFormData(form) {
      const formData = new FormData(form);
      const result = {};

      for (const [key, value] of formData.entries()) {
        const trimmed = typeof value === 'string' ? value.trim() : value;
        if (key === 'cost' || key === 'ticketCostPerPerson') {
          result[key] = trimmed ? Number(trimmed) : 0;
        } else if (key === 'day') {
          result[key] = Math.max(1, Number(trimmed) || 1);
        } else if (key === 'lat' || key === 'lng') {
          result[key] = trimmed ? parseFloat(trimmed) : null;
        } else {
          result[key] = trimmed;
        }
      }

      if (this.uploadedPhotoId) {
        result.photoId = this.uploadedPhotoId;
      }
      if (this.uploadedPhotoDataUrl) {
        result.photoDataUrl = this.uploadedPhotoDataUrl;
      }

      return result;
    }
  }

  const formManager = new FormManager();

  return {
    CATEGORIES,
    FormManager,
    formManager,
    escapeHtml
  };
});
