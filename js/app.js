/**
 * @intent 메인 애플리케이션 진입점 및 전역 이벤트 오케스트레이터
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function () {
  'use strict';

  const { store } = TripStore;
  const { mapManager } = TripMap;
  const { formManager, escapeHtml, CATEGORIES } = TripForms;
  const { calculateSettlements, formatAmount } = TripExpense;
  const { generateShareUrl, parseShareHash, exportTripAsJson, importTripFromJsonFile, copyToClipboard } = TripShare;
  const { resizeImage, savePhoto, getPhoto } = TripDB;
  const { getIcon } = Icons;

  // DOM 요소 캐시
  const dom = {
    // 헤더 요소
    tripTitle: document.getElementById('trip-title'),
    tripPeriod: document.getElementById('trip-period'),
    btnEditTrip: document.getElementById('btn-edit-trip'),

    // 내비게이션 탭
    tabTimeline: document.getElementById('tab-timeline'),
    tabExpense: document.getElementById('tab-expense'),
    tabShare: document.getElementById('tab-share'),
    daySelectorBar: document.getElementById('day-selector-bar'),
    dayChipSliderWrapper: document.getElementById('day-chip-slider-wrapper'),

    // 컨텐츠 패널
    panelContentArea: document.getElementById('panel-content-area'),
    sidePanel: document.getElementById('side-panel'),
    bottomSheetHandle: document.getElementById('bottom-sheet-handle'),
    btnSheetClose: document.getElementById('btn-sheet-close'),

    // 모바일 전용 하단 내비게이션 요소
    mobileBottomNav: document.getElementById('mobile-bottom-nav'),
    mNavMap: document.getElementById('m-nav-map'),
    mNavTimeline: document.getElementById('m-nav-timeline'),
    mNavAdd: document.getElementById('m-nav-add'),
    mNavExpense: document.getElementById('m-nav-expense'),
    mNavShare: document.getElementById('m-nav-share'),

    // 지도 컨트롤
    btnPinDropToggle: document.getElementById('btn-pin-drop-toggle'),
    btnAddItemFloating: document.getElementById('btn-add-item-floating'),

    // 모달 및 오버레이
    modalOverlay: document.getElementById('modal-overlay'),
    modalTitle: document.getElementById('modal-title'),
    modalContainer: document.getElementById('modal-container'),
    modalCloseBtn: document.getElementById('modal-close-btn'),

    // 라이트박스
    lightboxOverlay: document.getElementById('lightbox-overlay'),
    lightboxImg: document.getElementById('lightbox-img'),
    lightboxCloseBtn: document.getElementById('lightbox-close-btn'),

    // 토스트
    toastContainer: document.getElementById('toast-container')
  };

  // 모바일 바텀시트 상태: 'hidden', 'peek' (60px), 'half' (52vh), 'full' (전체)
  let currentSheetState = 'half';

  /**
   * 모바일 하단 네비게이션 활성 탭 UI 동기화
   * @param {string} targetName 
   */
  function syncMobileNavActiveState(targetName) {
    if (!dom.mobileBottomNav) return;
    const items = dom.mobileBottomNav.querySelectorAll('.m-nav-item:not(.m-nav-fab)');
    items.forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.target === targetName);
    });
  }

  /**
   * 토스트 메시지 표시
   */
  function showToast(message) {
    const toast = document.createElement('div');
    toast.className = 'toast-msg';
    toast.textContent = message;
    dom.toastContainer.appendChild(toast);

    setTimeout(() => toast.classList.add('show'), 20);
    setTimeout(() => {
      toast.classList.remove('show');
      setTimeout(() => toast.remove(), 300);
    }, 2800);
  }

  /**
   * 모바일 바텀시트 상태 설정
   * @param {'hidden'|'peek'|'half'|'full'} state 
   */
  function setBottomSheetState(state) {
    currentSheetState = state;
    dom.sidePanel.classList.remove('sheet-hidden', 'sheet-peek', 'sheet-half', 'sheet-full');
    dom.sidePanel.classList.add(`sheet-${state}`);

    if (state === 'hidden') {
      syncMobileNavActiveState('map');
    } else {
      syncMobileNavActiveState(store.getState().activeTab);
    }

    setTimeout(() => mapManager.invalidateSize(), 360);
  }

  /**
   * 모바일 바텀시트 단계 순환 토글 (hidden -> half -> full -> hidden)
   */
  function cycleBottomSheetState() {
    if (currentSheetState === 'hidden') setBottomSheetState('half');
    else if (currentSheetState === 'peek') setBottomSheetState('half');
    else if (currentSheetState === 'half') setBottomSheetState('full');
    else setBottomSheetState('hidden');
  }

  /**
   * 모바일 바텀시트 터치 스와이프 제스처 엔진 초기화
   */
  function initBottomSheetTouchGesture() {
    if (!dom.bottomSheetHandle) return;

    let touchStartY = 0;
    let initialHeight = 0;
    let isDragging = false;
    let dragDistance = 0;

    dom.bottomSheetHandle.addEventListener('touchstart', (e) => {
      if (window.innerWidth > 900) return;
      const touch = e.touches[0];
      touchStartY = touch.clientY;
      initialHeight = dom.sidePanel.getBoundingClientRect().height;
      isDragging = true;
      dragDistance = 0;
      dom.sidePanel.classList.add('is-dragging');
    }, { passive: true });

    window.addEventListener('touchmove', (e) => {
      if (!isDragging || window.innerWidth > 900) return;
      const currentY = e.touches[0].clientY;
      dragDistance = touchStartY - currentY; // 위로 올리면 양수, 아래로 내리면 음수

      const windowH = window.innerHeight;
      const minH = 70;
      const maxH = windowH - 54;
      const calculatedHeight = Math.max(minH, Math.min(maxH, initialHeight + dragDistance));

      dom.sidePanel.style.height = `${calculatedHeight}px`;
    }, { passive: true });

    window.addEventListener('touchend', () => {
      if (!isDragging || window.innerWidth > 900) return;
      isDragging = false;
      dom.sidePanel.classList.remove('is-dragging');
      dom.sidePanel.style.height = ''; // 인라인 스타일 제거

      const windowH = window.innerHeight;

      // 미세한 탭인 경우 (이동거리 8px 미만) -> 단계 순환
      if (Math.abs(dragDistance) < 8) {
        cycleBottomSheetState();
        return;
      }

      // 빠른 위로 스와이프 (위로 50px 이상 이동)
      if (dragDistance > 60) {
        if (currentSheetState === 'peek') setBottomSheetState('half');
        else setBottomSheetState('full');
        return;
      }

      // 빠른 아래로 스와이프 (아래로 60px 이상 이동)
      if (dragDistance < -60) {
        if (currentSheetState === 'full') setBottomSheetState('half');
        else setBottomSheetState('hidden');
        return;
      }

      // 위치 기반 가장 가까운 스냅 지점 계산
      const finalH = initialHeight + dragDistance;
      const ratio = finalH / windowH;

      if (ratio > 0.65) {
        setBottomSheetState('full');
      } else if (ratio < 0.22) {
        setBottomSheetState('hidden');
      } else {
        setBottomSheetState('half');
      }
    });

    // 데스크톱 또는 마우스 클릭 시 순환
    dom.bottomSheetHandle.addEventListener('click', (e) => {
      if (Math.abs(dragDistance) < 5) {
        cycleBottomSheetState();
      }
    });
  }


  /**
   * 전체 여행 일정에서 사용 중인 최대 Day 계산
   */
  function getMaxDays(items = []) {
    let max = 1;
    items.forEach((it) => {
      if (it.day && it.day > max) max = it.day;
    });
    return max;
  }

  /**
   * 상단 헤더 텍스트 렌더링
   */
  function renderHeader(trip) {
    const meta = trip.metadata || {};
    dom.tripTitle.textContent = meta.title || '나의 여행 일정';
    dom.tripPeriod.textContent = `${meta.startDate || '출발일 미정'} ~ ${meta.endDate || '도착일 미정'}`;
  }

  /**
   * 일차(Day) 탭 바 렌더링
   */
  function renderDayTabs(trip, selectedDay) {
    const maxDays = Math.max(3, getMaxDays(trip.items));
    dom.daySelectorBar.innerHTML = '';

    for (let d = 1; d <= maxDays; d++) {
      const chip = document.createElement('button');
      chip.className = `day-chip${d === selectedDay ? ' active' : ''}`;
      chip.innerHTML = `${getIcon('CALENDAR', { size: 14 })} <span>Day ${d}</span>`;
      chip.addEventListener('click', () => {
        store.setSelectedDay(d);
      });
      dom.daySelectorBar.appendChild(chip);
    }

    // 일차 추가 버튼
    const addDayBtn = document.createElement('button');
    addDayBtn.className = 'day-chip btn-add-day';
    addDayBtn.title = '새 일차 추가';
    addDayBtn.innerHTML = `${getIcon('PLUS', { size: 14 })} <span>일차 추가</span>`;
    addDayBtn.addEventListener('click', () => {
      store.setSelectedDay(maxDays + 1);
      showToast(`Day ${maxDays + 1}이 생성되었습니다.`);
    });
    dom.daySelectorBar.appendChild(addDayBtn);
  }

  /**
   * 타임라인 패널 렌더링
   */
  function renderTimelinePanel(trip, selectedDay, selectedItemId) {
    const dayItems = (trip.items || []).filter((item) => Number(item.day) === Number(selectedDay));

    let html = `
      <div class="timeline-toolbar" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
        <div style="font-weight:700; font-size:0.95rem; color:var(--text-main);">
          Day ${selectedDay} 일정 (${dayItems.length}개)
        </div>
        <button id="btn-add-item-day" class="btn btn-primary btn-sm">
          ${getIcon('PLUS', { size: 14 })} <span>일정 추가</span>
        </button>
      </div>
    `;

    if (dayItems.length === 0) {
      html += `
        <div class="empty-timeline-state">
          ${getIcon('ROUTE', { size: 40, color: 'var(--gray-400)' })}
          <div>등록된 Day ${selectedDay} 일정이 없습니다.</div>
          <button id="btn-empty-add-item" class="btn btn-outline btn-sm">
            ${getIcon('PLUS', { size: 14 })} <span>첫 일정 추가하기</span>
          </button>
        </div>
      `;
      dom.panelContentArea.innerHTML = html;

      document.getElementById('btn-add-item-day')?.addEventListener('click', () => openItemModal());
      document.getElementById('btn-empty-add-item')?.addEventListener('click', () => openItemModal());
      return;
    }

    html += '<div class="timeline-container">';

    dayItems.forEach((item, index) => {
      const order = index + 1;
      const cat = CATEGORIES[item.category] || { label: '기타', icon: 'NOTE', color: '#64748b' };
      const isActive = item.id === selectedItemId ? ' is-active' : '';

      html += `
        <div class="timeline-item-card${isActive}" data-id="${escapeHtml(item.id)}">
          <div class="card-header-row">
            <div style="display:flex; align-items:center;">
              <span class="card-order-badge">${order}</span>
              <span class="category-tag cat-${(item.category || '').toLowerCase()}">
                ${getIcon(cat.icon, { size: 14 })} <span>${cat.label}</span>
              </span>
            </div>
            ${item.time ? `<div class="card-time-badge">${getIcon('CLOCK', { size: 13 })} ${escapeHtml(item.time)}</div>` : ''}
          </div>

          <div class="card-title">${escapeHtml(item.title || '일정')}</div>

          <!-- 카테고리별 핵심 요약 그리드 -->
          ${renderItemCardDetails(item)}

          ${item.photoDataUrl ? `
            <img src="${escapeHtml(item.photoDataUrl)}" class="card-thumbnail" alt="첨부 사진" data-photo-url="${escapeHtml(item.photoDataUrl)}" />
          ` : ''}

          <div class="card-footer-row">
            <div class="card-cost-info">
              ${Number(item.cost) > 0 ? `
                ${getIcon('MONEY', { size: 14, color: 'var(--accent-emerald)' })}
                <span>${formatAmount(item.cost, item.currency)}</span>
                ${item.payer ? `<span class="card-payer-badge">${escapeHtml(item.payer)}</span>` : ''}
              ` : '<span style="color:var(--text-muted); font-weight:normal; font-size:0.75rem;">비용 없음</span>'}
            </div>
            <div class="card-actions">
              <button type="button" class="btn-icon btn-edit-item" data-id="${escapeHtml(item.id)}" title="수정">
                ${getIcon('EDIT', { size: 16 })}
              </button>
              <button type="button" class="btn-icon btn-delete-item" data-id="${escapeHtml(item.id)}" title="삭제">
                ${getIcon('DELETE', { size: 16 })}
              </button>
            </div>
          </div>
        </div>
      `;
    });

    html += '</div>';
    dom.panelContentArea.innerHTML = html;

    // 이벤트 바인딩
    document.getElementById('btn-add-item-day')?.addEventListener('click', () => openItemModal());

    // 카드 클릭 이벤트 (지도 이동 및 하이라이트)
    dom.panelContentArea.querySelectorAll('.timeline-item-card').forEach((card) => {
      card.addEventListener('click', (e) => {
        if (e.target.closest('.card-actions') || e.target.closest('.card-thumbnail')) return;
        const id = card.dataset.id;
        store.setSelectedItemId(id);
        const item = (trip.items || []).find((it) => it.id === id);
        if (item) mapManager.flyToItem(item);
      });
    });

    // 썸네일 클릭 시 라이트박스 오픈
    dom.panelContentArea.querySelectorAll('.card-thumbnail').forEach((thumb) => {
      thumb.addEventListener('click', (e) => {
        e.stopPropagation();
        openLightbox(thumb.dataset.photoUrl);
      });
    });

    // 수정 버튼
    dom.panelContentArea.querySelectorAll('.btn-edit-item').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.dataset.id;
        const item = (trip.items || []).find((it) => it.id === id);
        if (item) openItemModal(item);
      });
    });

    // 삭제 버튼
    dom.panelContentArea.querySelectorAll('.btn-delete-item').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.dataset.id;
        if (confirm('이 일정을 삭제하시겠습니까?')) {
          store.deleteItem(id);
          showToast('일정이 삭제되었습니다.');
        }
      });
    });
  }

  /**
   * 카테고리별 카드 내부 요약 그리드 생성
   */
  function renderItemCardDetails(item) {
    const details = [];

    switch (item.category) {
      case 'FLIGHT':
        if (item.flightNo) details.push({ label: '편명', val: item.flightNo });
        if (item.departureAirport && item.arrivalAirport) details.push({ label: '구간', val: `${item.departureAirport} -> ${item.arrivalAirport}` });
        if (item.terminalGate) details.push({ label: '터미널/게이트', val: item.terminalGate });
        if (item.seat) details.push({ label: '좌석', val: item.seat });
        break;

      case 'AIRPORT':
        if (item.baggageClaim) details.push({ label: '수취대', val: item.baggageClaim });
        if (item.transitToCity) details.push({ label: '시내환승', val: item.transitToCity });
        if (item.pickupInfo) details.push({ label: '픽업/탑승', val: item.pickupInfo });
        break;

      case 'HOTEL':
        if (item.checkInTime || item.checkOutTime) details.push({ label: '체크인/아웃', val: `${item.checkInTime || '-'} / ${item.checkOutTime || '-'}` });
        if (item.passcode) details.push({ label: '비밀번호', val: item.passcode });
        if (item.voucherNo) details.push({ label: '바우처', val: item.voucherNo });
        break;

      case 'ATTRACTION':
        if (item.openingHours) details.push({ label: '운영시간', val: item.openingHours });
        if (item.bookingStatus) details.push({ label: '예약', val: item.bookingStatus });
        if (item.tips) details.push({ label: '관람팁', val: item.tips });
        break;

      case 'DINING':
        if (item.mealType) details.push({ label: '분류', val: item.mealType });
        if (item.menuRecommendation) details.push({ label: '추천메뉴', val: item.menuRecommendation });
        if (item.paymentMethod) details.push({ label: '결제수단', val: item.paymentMethod });
        break;

      case 'TRANSIT':
        if (item.transitMode) details.push({ label: '이동수단', val: item.transitMode });
        if (item.origin && item.destination) details.push({ label: '구간', val: `${item.origin} -> ${item.destination}` });
        if (item.duration) details.push({ label: '소요시간', val: item.duration });
        break;
    }

    if (item.memo && details.length < 3) {
      details.push({ label: '메모', val: item.memo });
    }

    if (details.length === 0) return '';

    return `
      <div class="card-details-grid">
        ${details.map((d) => `
          <div class="detail-item">
            <span class="detail-label">${escapeHtml(d.label)}</span>
            <span class="detail-value">${escapeHtml(d.val)}</span>
          </div>
        `).join('')}
      </div>
    `;
  }

  /**
   * 정산(Expense) 대시보드 패널 렌더링
   */
  function renderExpensePanel(trip) {
    const meta = trip.metadata || {};
    const participants = meta.participants || [];
    const baseCurr = meta.baseCurrency || 'KRW';
    const rates = meta.customRates || {};

    const { settlements, summary, balances } = calculateSettlements(participants, trip.items, baseCurr, rates);

    const perPerson = Math.round(summary.totalInBase / 2);

    // 카테고리별 한국어 명칭 및 아이콘 매핑
    const catMeta = {
      FLIGHT: { label: '항공권', icon: 'FLIGHT' },
      HOTEL: { label: '숙소/호텔', icon: 'HOTEL' },
      DINING: { label: '식비/맛집', icon: 'DINING' },
      ATTRACTION: { label: '관광/투어', icon: 'ATTRACTION' },
      TRANSIT: { label: '교통/이동', icon: 'TRANSIT' },
      AIRPORT: { label: '공항/기타', icon: 'AIRPORT' }
    };

    // 카테고리별 지출액 내림차순 정렬
    const catEntries = Object.entries(summary.byCategory || {})
      .filter(([_, amt]) => amt > 0)
      .sort((a, b) => b[1] - a[1]);

    let html = `
      <div class="expense-dashboard">
        <!-- 상단 요약 통계 -->
        <div class="summary-stat-grid">
          <div class="stat-card">
            <span class="stat-label">총 신혼여행 경비 (${baseCurr})</span>
            <span class="stat-value">${formatAmount(summary.totalInBase, baseCurr)}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">1인당 평균 경비 (2인 기준)</span>
            <span class="stat-value" style="color:var(--primary-600);">${formatAmount(perPerson, baseCurr)}</span>
          </div>
        </div>

        <!-- 신혼여행 항목별 지출 분석 -->
        <div class="expense-category-card">
          <div style="font-size:0.9rem; font-weight:700; color:var(--text-main); display:flex; align-items:center; gap:6px;">
            ${getIcon('CALCULATOR', { size: 18, color: 'var(--primary-600)' })}
            <span>항목별 지출 분석 (예산 배분)</span>
          </div>
    `;

    if (catEntries.length === 0) {
      html += `
        <div style="font-size:0.85rem; color:var(--text-muted); padding:6px 0;">
          등록된 지출 내역이 없습니다.
        </div>
      `;
    } else {
      catEntries.forEach(([catKey, catAmt]) => {
        const cInfo = catMeta[catKey] || { label: catKey, icon: 'INFO' };
        const percent = summary.totalInBase > 0 ? Math.round((catAmt / summary.totalInBase) * 100) : 0;
        html += `
          <div class="expense-cat-row">
            <div class="expense-cat-header">
              <span class="expense-cat-name">
                ${getIcon(cInfo.icon, { size: 14, color: 'var(--gray-600)' })}
                ${cInfo.label} <strong style="font-size:0.75rem; color:var(--primary-600);">(${percent}%)</strong>
              </span>
              <span class="expense-cat-amount">${formatAmount(catAmt, baseCurr)}</span>
            </div>
            <div class="expense-progress-bar">
              <div class="expense-progress-fill" style="width: ${percent}%;"></div>
            </div>
          </div>
        `;
      });
    }

    html += `
        </div>

        <!-- 결제 주체별 지출 요약 -->
        <div class="member-balance-list">
          <div style="font-size:0.88rem; font-weight:700; color:var(--text-main); margin-bottom:4px;">
            결제 주체별 지출 현황
          </div>
    `;

    // 공동 지출, 신랑, 신부 순서로 렌더링
    const allPayers = Array.from(new Set(['공통', '신랑', '신부', ...Object.keys(summary.paidByMember || {})]));
    allPayers.forEach((p) => {
      const paid = summary.paidByMember[p] || 0;
      if (paid <= 0 && p !== '공통' && p !== '신랑' && p !== '신부') return;
      const label = p === '공통' ? '부부 공동 지출' : p;
      html += `
        <div class="member-balance-row">
          <div>
            <strong>${escapeHtml(label)}</strong>
          </div>
          <div style="font-weight:700; color:var(--text-main); font-size:0.9rem;">
            ${formatAmount(paid, baseCurr)}
          </div>
        </div>
      `;
    });

    html += `
        </div>

        <!-- 상호 송금 정산 내역 (필요 시) -->
        <div class="settlement-route-box">
          <div class="settlement-route-title">
            ${getIcon('CHECK', { size: 16, color: 'var(--primary-600)' })}
            <span>상호 정산 상태</span>
          </div>
    `;

    if (settlements.length === 0) {
      html += `
        <div style="font-size:0.85rem; color:var(--text-muted); padding:6px 0;">
          [V] 부부 공동 경비로 모든 정산이 완료되었습니다.
        </div>
      `;
    } else {
      settlements.forEach((st) => {
        html += `
          <div class="settlement-item">
            <div class="settlement-transfer-text">
              <strong style="color:var(--text-main);">${escapeHtml(st.from)}</strong>
              ${getIcon('ARROW_RIGHT', { size: 16, color: 'var(--gray-500)' })}
              <strong style="color:var(--primary-600);">${escapeHtml(st.to)}</strong>
            </div>
            <div style="font-size:0.95rem; font-weight:700; color:var(--text-main);">
              ${formatAmount(st.amount, st.currency)} 송금
            </div>
          </div>
        `;
      });
    }

    html += `
        </div>
      </div>
    `;

    dom.panelContentArea.innerHTML = html;
  }

  /**
   * 무서버 공유(Share) 패널 렌더링
   */
  function renderSharePanel(trip) {
    const shareUrl = generateShareUrl(trip);

    const html = `
      <div style="display:flex; flex-direction:column; gap:16px;">
        <div class="stat-card">
          <div style="font-size:0.95rem; font-weight:700; margin-bottom:6px; display:flex; align-items:center; gap:6px;">
            ${getIcon('SHARE', { size: 18, color: 'var(--primary-600)' })}
            <span>무서버 압축 URL 공유 링크</span>
          </div>
          <p style="font-size:0.8rem; color:var(--text-muted); line-height:1.4; margin-bottom:12px;">
            서버 저장 없이 브라우저의 LZ-String 압축 알고리즘을 활용하여 URL 해시에 일정을 완전히 담아 전송합니다.
          </p>
          <div style="display:flex; gap:8px;">
            <input type="text" id="share-url-input" class="form-control text-sm" readonly value="${escapeHtml(shareUrl)}" />
            <button type="button" id="btn-copy-share-url" class="btn btn-primary btn-sm">복사</button>
          </div>
        </div>
      </div>
    `;

    dom.panelContentArea.innerHTML = html;

    document.getElementById('btn-copy-share-url')?.addEventListener('click', async () => {
      const input = document.getElementById('share-url-input');
      const success = await copyToClipboard(input.value);
      if (success) {
        showToast('공유 링크가 클립보드에 복사되었습니다.');
      } else {
        showToast('복사에 실패했습니다. URL을 직접 복사해 주세요.');
      }
    });
  }

  /**
   * 라이트박스 팝업 열기
   */
  function openLightbox(imageUrl) {
    if (!imageUrl) return;
    dom.lightboxImg.src = imageUrl;
    dom.lightboxOverlay.classList.add('is-open');
  }

  function closeLightbox() {
    dom.lightboxOverlay.classList.remove('is-open');
    dom.lightboxImg.src = '';
  }

  /**
   * 모달 팝업 열기/닫기
   */
  function openModal(title, contentHtml) {
    dom.modalTitle.textContent = title;
    dom.modalContainer.innerHTML = contentHtml;
    dom.modalOverlay.classList.add('is-open');
  }

  function closeModal() {
    dom.modalOverlay.classList.remove('is-open');
    dom.modalContainer.innerHTML = '';
    mapManager.setPinDropMode(false);
    dom.btnPinDropToggle.classList.remove('active');
  }

  /**
   * 일정 등록/수정 모달 열기
   */
  function openItemModal(itemToEdit = null) {
    const trip = store.getState().trip;
    const participants = (trip.metadata && trip.metadata.participants) || [];

    const isEdit = Boolean(itemToEdit);
    const modalTitle = isEdit ? '일정 수정하기' : '새 여행 일정 추가';

    const defaultData = itemToEdit || {
      day: store.getState().selectedDay || 1,
      category: 'ATTRACTION',
      currency: trip.metadata.baseCurrency || 'KRW',
      payer: participants[0] || '공통'
    };

    const formHtml = formManager.renderFormHtml(defaultData, participants);
    openModal(modalTitle, formHtml);

    const modalForm = document.getElementById('item-editor-form');
    if (!modalForm) return;

    // 카테고리 알약 버튼 클릭 시 동적 필드 재렌더링
    const catGroup = document.getElementById('category-selector');
    const dynamicFields = document.getElementById('dynamic-category-fields');
    const inputCategory = document.getElementById('input-category');

    catGroup?.querySelectorAll('.category-pill').forEach((btn) => {
      btn.addEventListener('click', () => {
        catGroup.querySelectorAll('.category-pill').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        const cat = btn.dataset.category;
        inputCategory.value = cat;
        formManager.currentCategory = cat;
        dynamicFields.innerHTML = formManager.renderCategorySpecificFields(cat, defaultData);
      });
    });

    // Nominatim 주소/장소 검색
    const searchInput = document.getElementById('place-search-input');
    const searchBtn = document.getElementById('btn-search-place');
    const dropdown = document.getElementById('search-results-dropdown');
    const latInput = document.getElementById('item-lat');
    const lngInput = document.getElementById('item-lng');

    const handleSearch = async () => {
      const q = searchInput.value.trim();
      if (!q) return;
      dropdown.innerHTML = '<div class="search-dropdown-item" style="color:var(--text-muted);">검색 중...</div>';
      dropdown.classList.remove('hidden');

      const results = await TripGeocoder.searchPlaces(q);
      if (results.length === 0) {
        dropdown.innerHTML = '<div class="search-dropdown-item" style="color:var(--text-muted);">검색 결과가 없습니다.</div>';
        return;
      }

      dropdown.innerHTML = results.map((r, idx) => `
        <div class="search-dropdown-item" data-idx="${idx}">
          <strong>${escapeHtml(r.name)}</strong><br>
          <span style="font-size:0.75rem; color:var(--text-muted);">${escapeHtml(r.displayName)}</span>
        </div>
      `).join('');

      dropdown.querySelectorAll('.search-dropdown-item').forEach((itemEl) => {
        itemEl.addEventListener('click', () => {
          const idx = itemEl.dataset.idx;
          const chosen = results[idx];
          if (chosen) {
            latInput.value = chosen.lat;
            lngInput.value = chosen.lng;
            searchInput.value = chosen.name;
            const titleInput = document.getElementById('item-title');
            if (titleInput && !titleInput.value) {
              titleInput.value = chosen.name;
            }
            dropdown.classList.add('hidden');
            mapManager.setPinDropPreview(chosen.lat, chosen.lng);
            showToast(`좌표가 지정되었습니다: ${chosen.name}`);
          }
        });
      });
    };

    searchBtn?.addEventListener('click', handleSearch);
    searchInput?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        handleSearch();
      }
    });

    // 지도 핀 드롭 버튼 클릭
    const pickOnMapBtn = document.getElementById('btn-pick-on-map');
    pickOnMapBtn?.addEventListener('click', () => {
      mapManager.setPinDropMode(true);
      dom.btnPinDropToggle.classList.add('active');
      showToast('지도를 클릭하여 위치를 지정해 주세요.');
    });

    // 사진 첨부 및 Canvas 리사이징 연동
    const photoTriggerBtn = document.getElementById('btn-trigger-photo');
    const photoInput = document.getElementById('item-photo-input');
    const previewWrapper = document.getElementById('photo-preview-wrapper');
    const previewImg = document.getElementById('photo-preview-img');
    const removePhotoBtn = document.getElementById('btn-remove-photo');

    photoTriggerBtn?.addEventListener('click', () => photoInput.click());

    photoInput?.addEventListener('change', async (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) return;

      try {
        showToast('이미지 압축 처리 중...');
        const { dataUrl } = await resizeImage(file, 1200, 0.75);
        const photoId = 'photo-' + Date.now();
        await savePhoto(photoId, dataUrl, file.name);

        formManager.uploadedPhotoId = photoId;
        formManager.uploadedPhotoDataUrl = dataUrl;

        previewImg.src = dataUrl;
        previewWrapper.classList.remove('hidden');
        showToast('사진이 안전하게 등록되었습니다.');
      } catch (err) {
        showToast('사진 처리 실패: ' + err.message);
      }
    });

    removePhotoBtn?.addEventListener('click', () => {
      formManager.uploadedPhotoId = null;
      formManager.uploadedPhotoDataUrl = null;
      previewWrapper.classList.add('hidden');
      previewImg.src = '';
      photoInput.value = '';
    });

    // 취소 버튼
    document.getElementById('btn-modal-cancel')?.addEventListener('click', closeModal);

    // 폼 제출(Submit)
    modalForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const titleInput = document.getElementById('item-title');
      if (!titleInput.value.trim()) {
        alert('일정/장소명을 입력해 주세요.');
        titleInput.focus();
        return;
      }

      const extracted = formManager.extractFormData(modalForm);

      if (isEdit && itemToEdit.id) {
        store.updateItem(itemToEdit.id, extracted);
        showToast('일정이 성공적으로 수정되었습니다.');
      } else {
        const added = store.addItem(extracted);
        store.setSelectedItemId(added.id);
        showToast('새 일정이 등록되었습니다.');
      }

      closeModal();
    });
  }

  /**
   * 여행 메타데이터 편집 모달 열기
   */
  function openTripMetaModal() {
    const trip = store.getState().trip;
    const meta = trip.metadata || {};

    const contentHtml = `
      <form id="trip-meta-form" class="editor-form">
        <div class="form-group">
          <label class="form-label" for="meta-title">여행 제목</label>
          <input type="text" id="meta-title" name="title" class="form-control" required value="${escapeHtml(meta.title || '')}" />
        </div>
        <div class="form-row">
          <div class="form-group flex-1">
            <label class="form-label" for="meta-start-date">시작일</label>
            <input type="date" id="meta-start-date" name="startDate" class="form-control" value="${escapeHtml(meta.startDate || '')}" />
          </div>
          <div class="form-group flex-1">
            <label class="form-label" for="meta-end-date">종료일</label>
            <input type="date" id="meta-end-date" name="endDate" class="form-control" value="${escapeHtml(meta.endDate || '')}" />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label" for="meta-base-currency">정산 기준 통화</label>
          <select id="meta-base-currency" name="baseCurrency" class="form-control">
            <option value="KRW"${(meta.baseCurrency || 'KRW') === 'KRW' ? ' selected' : ''}>KRW (대한민국 원)</option>
            <option value="JPY"${(meta.baseCurrency || '') === 'JPY' ? ' selected' : ''}>JPY (일본 엔)</option>
            <option value="USD"${(meta.baseCurrency || '') === 'USD' ? ' selected' : ''}>USD (미국 달러)</option>
            <option value="EUR"${(meta.baseCurrency || '') === 'EUR' ? ' selected' : ''}>EUR (유럽 유로)</option>
          </select>
        </div>
        <div class="form-group">
          <label class="form-label" for="meta-gmaps-key">Google Maps API 키</label>
          <input type="text" id="meta-gmaps-key" name="gmapsKey" class="form-control" 
                 placeholder="AIzaSy... (입력 시 고화질 구글 지도로 즉시 전환)" 
                 value="${escapeHtml(TripMap.getSavedGoogleApiKey() || '')}" />
          <span style="font-size:0.72rem; color:var(--text-muted); margin-top:3px; display:block;">
            Google Cloud에서 발급받은 API 키를 입력하시면 브라우저에 안전하게 저장되고 Google Maps로 즉시 전환됩니다.
          </span>
        </div>
        <div class="modal-form-actions">
          <button type="button" id="btn-meta-cancel" class="btn btn-secondary">취소</button>
          <button type="submit" class="btn btn-primary">
            ${getIcon('CHECK', { size: 16 })} <span>저장 완료</span>
          </button>
        </div>
      </form>
    `;

    openModal('여행 기본 정보 수정', contentHtml);

    document.getElementById('btn-meta-cancel')?.addEventListener('click', closeModal);
    document.getElementById('trip-meta-form')?.addEventListener('submit', (e) => {
      e.preventDefault();
      const form = e.target;
      const title = form.title.value.trim();
      const startDate = form.startDate.value;
      const endDate = form.endDate.value;
      const baseCurrency = form.baseCurrency.value;
      const gmapsKey = (form.gmapsKey ? form.gmapsKey.value : '').trim();

      store.updateMetadata({
        title,
        startDate,
        endDate,
        participants: ['신랑', '신부'],
        baseCurrency
      });

      const currentKey = TripMap.getSavedGoogleApiKey();
      if (gmapsKey !== currentKey) {
        mapManager.updateApiKey(gmapsKey).then((success) => {
          if (success) {
            showToast('Google Maps로 전환되었습니다.');
          }
        });
      }

      showToast('여행 기본 정보가 수정되었습니다.');
      closeModal();
    });
  }

  /**
   * 앱 초기화 및 이벤트 리스너 바인딩
   */
  function initApp() {
    // 1. URL Hash 공유 데이터 체크
    if (window.location.hash) {
      const parsedTrip = parseShareHash(window.location.hash);
      if (parsedTrip && parsedTrip.metadata && Array.isArray(parsedTrip.items)) {
        try {
          store.replaceTrip(parsedTrip);
          showToast('공유받은 여행 일정을 성공적으로 불러왔습니다!');
        } catch (e) {
          console.warn('Failed to load shared trip:', e);
        }
      }
    }

    // 2. 지도 초기화 (하이브리드: 구글 맵 또는 Leaflet 폴백)
    mapManager.init('map-container');

    // 2-1. 모바일 뷰포트 진입 시 초기 바텀시트(half) 및 하단 탭 바 활성화 보장
    if (window.innerWidth <= 900) {
      setBottomSheetState('half');
    }

    // 3. 지도 마커 클릭 시 타임라인 카드 포커스
    mapManager.setMarkerClickListener((itemId) => {
      store.setSelectedItemId(itemId);
      const card = dom.panelContentArea.querySelector(`[data-id="${itemId}"]`);
      if (card) {
        card.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });

    // 4. 지도 핀 드롭 리스너 연동
    mapManager.setPinDropListener(async (lat, lng) => {
      const latInput = document.getElementById('item-lat');
      const lngInput = document.getElementById('item-lng');
      if (latInput && lngInput) {
        latInput.value = lat.toFixed(5);
        lngInput.value = lng.toFixed(5);
      }
      showToast(`핀 좌표 선택 완료: ${lat.toFixed(4)}, ${lng.toFixed(4)}`);

      // 역지오코딩 시도
      try {
        const place = await TripGeocoder.reverseGeocode(lat, lng);
        const searchInput = document.getElementById('place-search-input');
        if (searchInput && place.name) {
          searchInput.value = place.name;
        }
      } catch (err) {
        // 무시
      }
    });

    // 5. 플로팅 핀 드롭 토글 버튼
    dom.btnPinDropToggle?.addEventListener('click', () => {
      const isPinDrop = !store.getState().pinDropMode;
      store.setPinDropMode(isPinDrop);
      mapManager.setPinDropMode(isPinDrop);
      if (isPinDrop) {
        dom.btnPinDropToggle.classList.add('active');
        showToast('지도 클릭 핀 지정 모드가 켜졌습니다.');
      } else {
        dom.btnPinDropToggle.classList.remove('active');
        showToast('핀 지정 모드가 꺼졌습니다.');
      }
    });

    // 6. 플로팅 + 일정 추가 버튼
    dom.btnAddItemFloating?.addEventListener('click', () => openItemModal());

    // 7. 내비게이션 탭 이벤트
    dom.tabTimeline.addEventListener('click', () => {
      store.setActiveTab('timeline');
      if (currentSheetState === 'hidden') setBottomSheetState('half');
    });
    dom.tabExpense.addEventListener('click', () => {
      store.setActiveTab('expense');
      if (currentSheetState === 'hidden') setBottomSheetState('half');
    });
    dom.tabShare.addEventListener('click', () => {
      store.setActiveTab('share');
      if (currentSheetState === 'hidden') setBottomSheetState('half');
    });

    // 8. 모바일 바텀시트 닫기 버튼 이벤트
    dom.btnSheetClose?.addEventListener('click', () => {
      setBottomSheetState('hidden');
    });

    // 9. 모바일 하단 내비게이션 바 버튼 리스너
    dom.mNavMap?.addEventListener('click', () => {
      setBottomSheetState('hidden');
      showToast('지도 전체화면 모드');
    });

    dom.mNavTimeline?.addEventListener('click', () => {
      store.setActiveTab('timeline');
      if (currentSheetState === 'hidden' || currentSheetState === 'peek') {
        setBottomSheetState('half');
      } else {
        syncMobileNavActiveState('timeline');
      }
    });

    dom.mNavAdd?.addEventListener('click', () => {
      openItemModal();
    });

    dom.mNavExpense?.addEventListener('click', () => {
      store.setActiveTab('expense');
      if (currentSheetState === 'hidden' || currentSheetState === 'peek') {
        setBottomSheetState('half');
      } else {
        syncMobileNavActiveState('expense');
      }
    });

    dom.mNavShare?.addEventListener('click', () => {
      store.setActiveTab('share');
      if (currentSheetState === 'hidden' || currentSheetState === 'peek') {
        setBottomSheetState('half');
      } else {
        syncMobileNavActiveState('share');
      }
    });

    // 10. 모달 및 라이트박스 닫기 이벤트
    dom.modalCloseBtn?.addEventListener('click', closeModal);
    dom.modalOverlay?.addEventListener('click', (e) => {
      if (e.target === dom.modalOverlay) closeModal();
    });
    dom.lightboxCloseBtn?.addEventListener('click', closeLightbox);
    dom.lightboxOverlay?.addEventListener('click', (e) => {
      if (e.target === dom.lightboxOverlay) closeLightbox();
    });

    // Esc 키 이벤트
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal();
        closeLightbox();
      }
    });

    // 11. 모바일 바텀시트 터치 스와이프 제스처 엔진 가동
    initBottomSheetTouchGesture();

    // 12. 반응형 뷰포트 변경 및 기기 회전(Orientation) 시 지도 렌더링 무결성 보장
    let resizeDebounceTimer = null;
    window.addEventListener('resize', () => {
      clearTimeout(resizeDebounceTimer);
      resizeDebounceTimer = setTimeout(() => {
        mapManager.invalidateSize();
      }, 120);
    });

    window.addEventListener('orientationchange', () => {
      setTimeout(() => mapManager.invalidateSize(), 300);
    });

    // 13. 상단 헤더 액션 버튼
    dom.btnEditTrip?.addEventListener('click', openTripMetaModal);

    // 14. 중앙 상태(Store) 변경 감지 구독
    store.subscribe((state) => {
      const { trip, selectedDay, selectedItemId, activeTab } = state;

      // 헤더 렌더링
      renderHeader(trip);

      // 탭 활성화 상태
      [dom.tabTimeline, dom.tabExpense, dom.tabShare].forEach((t) => t.classList.remove('active'));
      if (activeTab === 'timeline') dom.tabTimeline.classList.add('active');
      else if (activeTab === 'expense') dom.tabExpense.classList.add('active');
      else if (activeTab === 'share') dom.tabShare.classList.add('active');

      // Day 선택 탭 표시/숨김
      if (activeTab === 'timeline') {
        if (dom.dayChipSliderWrapper) dom.dayChipSliderWrapper.classList.remove('hidden');
        renderDayTabs(trip, selectedDay);
        renderTimelinePanel(trip, selectedDay, selectedItemId);
      } else if (activeTab === 'expense') {
        if (dom.dayChipSliderWrapper) dom.dayChipSliderWrapper.classList.add('hidden');
        renderExpensePanel(trip);
      } else if (activeTab === 'share') {
        if (dom.dayChipSliderWrapper) dom.dayChipSliderWrapper.classList.add('hidden');
        renderSharePanel(trip);
      }

      // 모바일 하단 내비게이션 탭 동기화
      if (currentSheetState !== 'hidden') {
        syncMobileNavActiveState(activeTab);
      }

      // 지도 마커 및 동선 재렌더링
      mapManager.render(trip.items, selectedDay, selectedItemId);
    });

    // 첫 알림 발송으로 화면 렌더링 개시
    store.notify();
  }

  // DOM 로드 완료 시 구동
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }
})();
