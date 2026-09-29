/**
 * @intent 6대 카테고리 동적 폼 및 다중 사진(사진 배열) 첨부/관리 지원 모듈
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
      this.uploadedPhotos = [];
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

      if (Array.isArray(data.photos) && data.photos.length > 0) {
        this.uploadedPhotos = [...data.photos];
      } else if (data.photoDataUrl) {
        this.uploadedPhotos = [{ id: data.photoId || 'photo-1', dataUrl: data.photoDataUrl, filename: 'photo' }];
      } else {
        this.uploadedPhotos = [];
      }
      this.uploadedPhotoId = this.uploadedPhotos.length > 0 ? this.uploadedPhotos[0].id : null;
      this.uploadedPhotoDataUrl = this.uploadedPhotos.length > 0 ? this.uploadedPhotos[0].dataUrl : null;

      const hasCoord = (data.lat !== undefined && data.lat !== null && data.lat !== '' && !isNaN(Number(data.lat))) &&
                       (data.lng !== undefined && data.lng !== null && data.lng !== '' && !isNaN(Number(data.lng)));

      const formattedCost = (data.cost !== undefined && data.cost !== null && data.cost !== '' && !isNaN(Number(data.cost)))
        ? Math.round(Number(data.cost)).toLocaleString('ko-KR')
        : '';

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

          <!-- 위치 지정 (구글맵 장소 검색 & 좌표 입력) -->
          <div class="form-group location-section">
            <div class="location-section-header">
              <label class="form-label" style="margin-bottom:0;">위치 지정 (구글맵 장소 검색 & 좌표)</label>
              <span class="location-section-tip">장소를 검색하면 이름과 좌표가 자동으로 입력됩니다.</span>
            </div>

            <!-- 1. 구글맵 장소 실시간 검색창 -->
            <div class="place-search-wrap">
              <div class="input-with-icon">
                <span class="input-prefix-icon">
                  ${typeof Icons !== 'undefined' ? Icons.getIcon('SEARCH', { size: 16 }) : ''}
                </span>
                <input type="text" id="place-search-input" class="form-control place-search-input" 
                       placeholder="장소명 또는 주소 검색 (예: 도쿄 타워, 센소지, 신라호텔)" 
                       value="${escapeHtml(data.address || data.title || '')}" autocomplete="off" />
                <button type="button" id="btn-clear-place-search" class="btn-clear-input ${data.address || data.title ? '' : 'hidden'}" title="검색어 지우기">
                  ${typeof Icons !== 'undefined' ? Icons.getIcon('CLOSE', { size: 12 }) : 'X'}
                </button>
              </div>
              <!-- 실시간 자동완성 드롭다운 -->
              <div id="place-search-dropdown" class="place-search-dropdown hidden"></div>
            </div>

            <!-- 2. 구글맵 좌표 한 줄 붙여넣기 입력창 -->
            <div class="coord-paste-wrap">
              <div class="coord-paste-input-box">
                <span class="coord-paste-icon">
                  ${typeof Icons !== 'undefined' ? Icons.getIcon('LOCATION_TARGET', { size: 16 }) : ''}
                </span>
                <input type="text" id="coord-paste-input" class="form-control coord-paste-input" 
                       placeholder="구글맵 좌표 붙여넣기 (예: 35.6585, 139.7454)" 
                       value="${hasCoord ? `${Number(data.lat).toFixed(6)}, ${Number(data.lng).toFixed(6)}` : ''}" />
                <button type="button" id="btn-apply-coord-paste" class="btn btn-secondary btn-sm" title="좌표 즉시 적용">
                  <span>적용</span>
                </button>
              </div>
            </div>

            <!-- 3. 위도 및 경도 2열 직접 입력창 + 지도 핀 찍기/초기화 -->
            <div class="coord-inputs-grid">
              <div class="coord-input-item">
                <label class="coord-sublabel" for="item-lat">위도 (Latitude)</label>
                <input type="number" step="any" id="item-lat" name="lat" class="form-control" 
                       placeholder="예: 35.65858" value="${escapeHtml(data.lat !== undefined && data.lat !== '' && data.lat !== null ? String(data.lat) : '')}" />
              </div>
              <div class="coord-input-item">
                <label class="coord-sublabel" for="item-lng">경도 (Longitude)</label>
                <input type="number" step="any" id="item-lng" name="lng" class="form-control" 
                       placeholder="예: 139.74543" value="${escapeHtml(data.lng !== undefined && data.lng !== '' && data.lng !== null ? String(data.lng) : '')}" />
              </div>
              <div class="coord-actions-box">
                <button type="button" id="btn-pick-on-map" class="btn btn-outline btn-pick-on-map" title="지도에서 클릭하여 핀 지정">
                  ${typeof Icons !== 'undefined' ? Icons.getIcon('MAP', { size: 14 }) : ''}
                  <span>지도 핀 찍기</span>
                </button>
                <button type="button" id="btn-clear-location" class="btn btn-outline btn-clear-location ${hasCoord ? '' : 'hidden'}" title="좌표 초기화">
                  <span>초기화</span>
                </button>
              </div>
            </div>
          </div>

          <!-- 비용 (공동 결제, KRW 원화 고정) -->
          <div class="form-group expense-section">
            <label class="form-label" for="item-cost">비용 / 지출액</label>
            <div class="input-with-unit">
              <input type="text" id="item-cost" name="cost" class="form-control" inputmode="numeric" 
                     placeholder="0 (금액 입력)" value="${formattedCost}" />
              <span class="input-unit-badge">원</span>
            </div>
            <input type="hidden" id="item-currency" name="currency" value="KRW" />
            <input type="hidden" id="item-payer" name="payer" value="공동" />
          </div>

          <!-- 사진 첨부 (E-티켓, 영수증, 명소 사진 - 여러 장 지원) -->
          <div class="form-group photo-upload-group">
            <label class="form-label">사진 첨부 (티켓/바우처/현장 사진)</label>
            <div class="photo-upload-container">
              <input type="file" id="item-photo-input" accept="image/*" multiple class="hidden-file-input" />
              <button type="button" id="btn-trigger-photo" class="btn btn-outline">
                ${typeof Icons !== 'undefined' ? Icons.getIcon('IMAGE', { size: 16 }) : ''}
                <span>사진 추가 (여러 장 선택 가능)</span>
              </button>
              <div id="photo-preview-section" class="photo-preview-section ${this.uploadedPhotos.length > 0 ? '' : 'hidden'}">
                <div class="photo-preview-header">
                  <span class="photo-preview-count" id="photo-preview-count">첨부된 사진 (${this.uploadedPhotos.length}장)</span>
                  <button type="button" id="btn-clear-all-photos" class="btn-clear-photos-text">전체 삭제</button>
                </div>
                <div id="photos-preview-grid" class="photos-preview-grid">
                  ${this.renderPhotosPreviewGridHtml()}
                </div>
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
          const formattedTicketCost = (data.ticketCostPerPerson !== undefined && data.ticketCostPerPerson !== null && data.ticketCostPerPerson !== '' && !isNaN(Number(data.ticketCostPerPerson)))
            ? Math.round(Number(data.ticketCostPerPerson)).toLocaleString('ko-KR')
            : '';
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
                  <input type="text" id="item-ticket-cost" name="ticketCostPerPerson" class="form-control" inputmode="numeric" placeholder="0 (금액 입력)" value="${formattedTicketCost}" />
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
     * @intent 첨부된 사진들의 그리드 미리보기 HTML 생성 (인라인 SVG 닫기 아이콘 적용)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {string} 그리드 내부 HTML
     */
    renderPhotosPreviewGridHtml() {
      return (this.uploadedPhotos || []).map((p, idx) => `
        <div class="photo-preview-item" data-index="${idx}">
          <img src="${escapeHtml(p.dataUrl)}" alt="사진 ${idx + 1}" />
          <button type="button" class="btn-remove-single-photo" data-index="${idx}" title="사진 삭제">
            ${typeof Icons !== 'undefined' ? Icons.getIcon('CLOSE', { size: 12 }) : 'X'}
          </button>
        </div>
      `).join('');
    }

    /**
     * @intent 폼 제출 데이터 수집 및 천 단위 콤마 제거/정수 정제 보장
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {HTMLFormElement} form 
     * @returns {object} 수집된 일정 객체
     */
    extractFormData(form) {
      const formData = new FormData(form);
      const result = {};

      for (const [key, value] of formData.entries()) {
        const trimmed = typeof value === 'string' ? value.trim() : value;
        if (key === 'cost' || key === 'ticketCostPerPerson') {
          const rawNumberStr = String(trimmed).replace(/,/g, '');
          const num = Number(rawNumberStr);
          result[key] = (rawNumberStr && !isNaN(num)) ? Math.round(num) : 0;
        } else if (key === 'day') {
          result[key] = Math.max(1, Number(trimmed) || 1);
        } else if (key === 'lat' || key === 'lng') {
          result[key] = trimmed ? parseFloat(trimmed) : null;
        } else {
          result[key] = trimmed;
        }
      }

      result.photos = this.uploadedPhotos;
      if (this.uploadedPhotos && this.uploadedPhotos.length > 0) {
        result.photoId = this.uploadedPhotos[0].id;
        result.photoDataUrl = this.uploadedPhotos[0].dataUrl;
      } else {
        result.photoId = null;
        result.photoDataUrl = null;
      }

      return result;
    }

    /**
     * @intent Supabase 클라우드 동기화 모달 뷰 마크업 생성 (도메인/키 수동 입력 폼 완전 제거 및 내장 자동 동기화 상태 표기)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {{ url: string, anonKey: string }} _config
     * @param {{ status: 'connected' | 'unconfigured' | 'error', message?: string }} statusState
     * @param {string} sqlScript
     * @returns {string} HTML 마크업
     */
    renderCloudSyncModalHtml(_config = { url: '', anonKey: '' }, statusState = { status: 'connected' }, sqlScript = '') {
      let badgeClass = 'status-connected';
      let statusLabel = 'Supabase 클라우드 실시간 자동 연동 중';

      if (statusState && statusState.status === 'error') {
        badgeClass = 'status-error';
        statusLabel = statusState.message || '클라우드 일시 지연 (로컬 보관 중)';
      }

      return `
        <div class="supabase-modal-box">
          <div class="cloud-header-banner">
            <div class="cloud-status-badge ${badgeClass}" id="cloud-status-badge">
              <span class="status-indicator-dot"></span>
              <span class="status-indicator-text">${escapeHtml(statusLabel)}</span>
            </div>
            <p class="cloud-subtext">
              프로젝트에 내장된 Supabase 클라우드로 모든 여행 일정과 사진이 실시간 자동 저장되고 있습니다. 브라우저 기록이나 캐시를 지우셔도 언제든지 안전하게 복원됩니다.
            </p>
          </div>

          <div class="cloud-data-actions-section">
            <h4 class="cloud-section-title">데이터 동기화 및 복원</h4>
            <div class="cloud-data-buttons-grid">
              <button type="button" id="btn-cloud-upload-all" class="btn-sync-action">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
                  <path d="M9 16h6v-6h4l-7-7-7 7h4zm-4 2h14v2H5z"/>
                </svg>
                <div class="sync-action-text">
                  <strong>로컬 데이터를 클라우드로 즉시 업로드</strong>
                  <small>현재 기기의 모든 여행 계획을 Supabase로 일괄 백업합니다.</small>
                </div>
              </button>
              <button type="button" id="btn-cloud-import" class="btn-sync-action">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
                  <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
                </svg>
                <div class="sync-action-text">
                  <strong>클라우드에서 최신 데이터 가져오기</strong>
                  <small>기록 삭제 후에도 클라우드에 보관된 여행 데이터를 1초 만에 복원합니다.</small>
                </div>
              </button>
            </div>
          </div>

          <div class="cloud-guide-accordion">
            <details class="cloud-sql-details">
              <summary class="cloud-sql-summary">
                <span>Supabase 1분 무료 설정 가이드 &amp; SQL 스크립트</span>
                <svg class="summary-arrow" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
                  <path d="M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6 1.41-1.41z"/>
                </svg>
              </summary>
              <div class="cloud-guide-content">
                <ol class="cloud-guide-steps">
                  <li><strong>supabase.com</strong>에서 무료 프로젝트를 생성합니다.</li>
                  <li>좌측 메뉴 <strong>[SQL Editor]</strong>에 아래 SQL 스크립트를 붙여넣고 <strong>[Run]</strong>을 클릭하여 테이블 및 스토리지를 구성합니다.</li>
                </ol>
                <div class="sql-box-header">
                  <span>SQL 원클릭 스크립트 (trips 테이블 + trip-photos 버킷 생성)</span>
                  <button type="button" id="btn-copy-setup-sql" class="btn-copy-sql">
                    SQL 복사
                  </button>
                </div>
                <pre class="sql-code-snippet"><code id="sql-code-target">${escapeHtml(sqlScript)}</code></pre>
              </div>
            </details>
          </div>
        </div>
      `;
    }
  }

  /**
   * @intent 구글맵 좌표 문자열(위도, 경도) 파싱 유틸리티 - 다양한 구분자(쉼표, 공백, 슬래시, 괄호) 및 유효 범위(-90~90, -180~180) 검증
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} str - 구글맵 복사 좌표 문자열
   * @returns {{lat: number, lng: number}|null} 파싱된 좌표 객체 또는 null
   */
  function parseCoordinates(str) {
    if (!str) return null;
    // '35.6585805, 139.7454329' 또는 '35.6585 139.7454' 또는 '(35.6585, 139.7454)' 등 다양한 형식 지원
    const clean = str.replace(/[()]/g, '').trim();
    const match = clean.match(/^(-?\d+(?:\.\d+)?)[,\s/]+(-?\d+(?:\.\d+)?)$/);
    if (!match) return null;
    const lat = parseFloat(match[1]);
    const lng = parseFloat(match[2]);
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return { lat, lng };
  }

  const formManager = new FormManager();

  return {
    CATEGORIES,
    FormManager,
    formManager,
    parseCoordinates,
    escapeHtml
  };
});
