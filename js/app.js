/**
 * @intent 메인 애플리케이션 진입점 및 전역 이벤트 오케스트레이터 (지도 플로팅 컨트롤 제거 및 클린 뷰포트 확보)
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
    brandInfo: document.getElementById('brand-info'),
    tripTitle: document.getElementById('trip-title'),
    tripPeriod: document.getElementById('trip-period'),
    btnManageTrips: document.getElementById('btn-manage-trips'),
    btnCopyShareLink: document.getElementById('btn-copy-share-link'),
    btnEditTrip: document.getElementById('btn-edit-trip'),

    // 내비게이션 탭 (일정, 경비)
    tabTimeline: document.getElementById('tab-timeline'),
    tabExpense: document.getElementById('tab-expense'),
    daySelectorBar: document.getElementById('day-selector-bar'),
    dayChipSliderWrapper: document.getElementById('day-chip-slider-wrapper'),

    // 컨텐츠 패널
    panelContentArea: document.getElementById('panel-content-area'),
    sidePanel: document.getElementById('side-panel'),
    bottomSheetHandle: document.getElementById('bottom-sheet-handle'),

    // 모바일 전용 하단 내비게이션 요소 (지도, 일정, 추가, 경비)
    mobileBottomNav: document.getElementById('mobile-bottom-nav'),
    mNavMap: document.getElementById('m-nav-map'),
    mNavTimeline: document.getElementById('m-nav-timeline'),
    mNavAdd: document.getElementById('m-nav-add'),
    mNavExpense: document.getElementById('m-nav-expense'),

    // 지도 핀 위치 선택 플로팅 바 (Pin Picker Bar)
    pinPickerBar: document.getElementById('pin-picker-bar'),
    pinPickerAddress: document.getElementById('pin-picker-address'),
    btnPinPickerCancel: document.getElementById('btn-pin-picker-cancel'),
    btnPinPickerConfirm: document.getElementById('btn-pin-picker-confirm'),

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
  let previousSheetStateBeforePicker = 'half';
  let activePickerCoord = null;

  /**
   * 모바일 하단 네비게이션 활성 탭 UI 동기화
   * @param {string} targetName 
   */
  function syncMobileNavActiveState(targetName) {
    if (!dom.mobileBottomNav) return;
    const items = dom.mobileBottomNav.querySelectorAll('.m-nav-item[data-target]');
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
   * @intent 모바일 바텀시트 상태 설정 및 인라인 트랜스폼 리셋 (CSS 클래스 기반 순수 transform 제어)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {'hidden'|'peek'|'half'|'full'} state 
   */
  function setBottomSheetState(state) {
    currentSheetState = state;
    if (dom.sidePanel) {
      dom.sidePanel.style.transform = '';
      dom.sidePanel.style.transition = '';
      dom.sidePanel.classList.remove('sheet-hidden', 'sheet-peek', 'sheet-half', 'sheet-full');
      dom.sidePanel.classList.add(`sheet-${state}`);
    }

    if (state === 'hidden') {
      syncMobileNavActiveState('map');
    } else {
      syncMobileNavActiveState(store.getState().activeTab);
    }

    setTimeout(() => mapManager.invalidateSize(), 360);
  }

  /**
   * @intent 모바일 바텀시트 단계 순환 토글 (hidden/peek -> half, half -> full, full -> half)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function cycleBottomSheetState() {
    if (currentSheetState === 'hidden' || currentSheetState === 'peek') {
      setBottomSheetState('half');
    } else if (currentSheetState === 'half') {
      setBottomSheetState('full');
    } else if (currentSheetState === 'full') {
      setBottomSheetState('half');
    } else {
      setBottomSheetState('half');
    }
  }

  /**
   * @intent 모바일 바텀시트 고속 제스처 엔진 (단일 고정 높이 + 순수 GPU transform 기반 스무스 스냅)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function initBottomSheetTouchGesture() {
    const handle = dom.bottomSheetHandle;
    const panel = dom.sidePanel;
    if (!handle || !panel) return;

    // 핸들 또는 상단 핸들 컨테이너 전체를 터치 타겟으로 활용
    const handleTarget = handle.parentElement || handle;

    let isDragging = false;
    let startY = 0;
    let lastY = 0;
    let lastTime = 0;
    let velocity = 0; // px / ms (아래로: 양수, 위로: 음수)
    let baseY = 0;
    let panelHeight = 0;
    let activePointerId = null;

    // 상태별 기준 Y 오프셋(픽셀) 계산
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

    function onPointerDown(e) {
      if (window.innerWidth > 900) return;
      if (e.pointerType === 'mouse' && e.button !== 0) return;

      isDragging = true;
      activePointerId = e.pointerId ?? null;
      startY = e.clientY;
      lastY = e.clientY;
      lastTime = performance.now();
      velocity = 0;

      panelHeight = panel.getBoundingClientRect().height || (window.innerHeight - 84);
      baseY = getBaseYForState(currentSheetState, panelHeight);

      panel.style.transition = 'none';
      panel.classList.add('is-dragging');

      if (e.target && e.target.setPointerCapture && activePointerId !== null) {
        try {
          e.target.setPointerCapture(activePointerId);
        } catch (_) {}
      }
    }

    function onPointerMove(e) {
      if (!isDragging || window.innerWidth > 900) return;
      if (activePointerId !== null && e.pointerId !== undefined && e.pointerId !== activePointerId) return;

      const currentPointerY = e.clientY;
      const now = performance.now();
      const dt = now - lastTime;

      if (dt > 8) {
        const instantVelocity = (currentPointerY - lastY) / dt;
        velocity = velocity * 0.4 + instantVelocity * 0.6;
        lastY = currentPointerY;
        lastTime = now;
      }

      const deltaY = currentPointerY - startY;
      let currentY = baseY + deltaY;

      // 위로 끌어올릴 때(currentY < 0): 부드러운 고무줄 저항감
      if (currentY < 0) {
        currentY = currentY * 0.2;
      }

      // 아래로 과도하게 내릴 때(currentY > maxOffset): 고무줄 저항감
      const maxOffset = panelHeight + 80;
      if (currentY > maxOffset) {
        const overDistance = currentY - maxOffset;
        currentY = maxOffset + overDistance * 0.2;
      }

      panel.style.transform = `translate3d(0, ${currentY}px, 0)`;
    }

    function onPointerUp(e) {
      if (!isDragging) return;
      if (activePointerId !== null && e.pointerId !== undefined && e.pointerId !== activePointerId) return;

      isDragging = false;
      panel.classList.remove('is-dragging');

      if (e.target && e.target.releasePointerCapture && activePointerId !== null) {
        try {
          e.target.releasePointerCapture(activePointerId);
        } catch (_) {}
      }
      activePointerId = null;

      const endY = (e.clientY !== undefined) ? e.clientY : lastY;
      const deltaY = endY - startY;

      // 1. 단순 탭(클릭) 인터랙션: 이동 거리 < 8px
      if (Math.abs(deltaY) < 8) {
        panel.style.transform = '';
        panel.style.transition = '';
        cycleBottomSheetState();
        return;
      }

      // 2. 현재 Y 좌표 계산 (저항감 포함)
      let currentY = baseY + deltaY;
      if (currentY < 0) {
        currentY = currentY * 0.2;
      }
      const maxOffset = panelHeight + 80;
      if (currentY > maxOffset) {
        currentY = maxOffset + (currentY - maxOffset) * 0.2;
      }

      let targetState = currentSheetState;

      // 플릭(속도 velocity) 및 놓은 위치에 따라 가장 자연스러운 목표 상태(hidden, half, full) 결정
      const isFlickDown = velocity > 0.45 || deltaY > 100;
      const isFlickUp = velocity < -0.45 || deltaY < -100;

      if (isFlickDown) {
        // 아래로 휙 스와이프: full이면 half 또는 hidden, half이면 hidden
        if (currentSheetState === 'full') {
          if (velocity > 0.85 || deltaY > 240) {
            targetState = 'hidden';
          } else {
            targetState = 'half';
          }
        } else {
          // half 또는 peek 상태에서 내렸을 때 hidden으로 쏙 들어감
          targetState = 'hidden';
        }
      } else if (isFlickUp) {
        // 위로 휙 스와이프: hidden/half이면 full
        targetState = 'full';
      } else {
        // 천천히 놓았을 때: 가장 가까운 스냅 지점으로 결정
        const fullY = 0;
        const halfY = panelHeight * 0.52;
        const hiddenY = panelHeight + 80;

        const distToFull = Math.abs(currentY - fullY);
        const distToHalf = Math.abs(currentY - halfY);
        const distToHidden = Math.abs(currentY - hiddenY);

        if (distToFull <= distToHalf && distToFull <= distToHidden) {
          targetState = 'full';
        } else if (distToHalf <= distToFull && distToHalf <= distToHidden) {
          targetState = 'half';
        } else {
          targetState = 'hidden';
        }
      }

      // 3. 스냅 시: 목표 상태의 기준 픽셀 Y로 transition 애니메이션을 주어 스르륵 안착시킨 뒤
      //    완료 시 인라인 transform 리셋 및 setBottomSheetState(targetState) 호출!
      const targetY = getBaseYForState(targetState, panelHeight);
      panel.style.transition = 'transform 0.34s cubic-bezier(0.2, 0.9, 0.3, 1)';
      panel.style.transform = `translate3d(0, ${targetY}px, 0)`;

      let snapFinished = false;
      const finalizeSnap = () => {
        if (snapFinished) return;
        snapFinished = true;
        panel.removeEventListener('transitionend', onTransitionEnd);
        panel.style.transition = '';
        setBottomSheetState(targetState);
      };

      const onTransitionEnd = (evt) => {
        if (evt && evt.propertyName !== 'transform') return;
        finalizeSnap();
      };

      panel.addEventListener('transitionend', onTransitionEnd);
      // 안전 타이머: 애니메이션 타임아웃(360ms)으로 이벤트 유실 완벽 방어
      setTimeout(finalizeSnap, 360);
    }

    if (window.PointerEvent) {
      handleTarget.addEventListener('pointerdown', onPointerDown);
      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', onPointerUp);
      window.addEventListener('pointercancel', onPointerUp);
    } else {
      // Touch fallback (구형 브라우저 대응)
      handleTarget.addEventListener('touchstart', (e) => {
        const touch = e.touches[0];
        onPointerDown({
          clientY: touch.clientY,
          pointerType: 'touch',
          pointerId: 1,
          target: handleTarget
        });
      }, { passive: true });

      window.addEventListener('touchmove', (e) => {
        if (!isDragging) return;
        const touch = e.touches[0];
        onPointerMove({
          clientY: touch.clientY,
          pointerId: 1
        });
      }, { passive: true });

      window.addEventListener('touchend', (e) => {
        const touch = e.changedTouches ? e.changedTouches[0] : null;
        onPointerUp({
          pointerId: 1,
          target: handleTarget,
          clientY: touch ? touch.clientY : undefined
        });
      });
      window.addEventListener('touchcancel', (e) => {
        const touch = e.changedTouches ? e.changedTouches[0] : null;
        onPointerUp({
          pointerId: 1,
          target: handleTarget,
          clientY: touch ? touch.clientY : undefined
        });
      });
    }
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
                <span>${formatAmount(item.cost, 'KRW')}</span>
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
   * 정산(Expense) 대시보드 패널 렌더링 (부부 공동 경비 및 KRW 원화 단일화)
   */
  function renderExpensePanel(trip) {
    const meta = trip.metadata || {};
    const participants = meta.participants || [];
    const baseCurr = 'KRW';
    const rates = meta.customRates || {};

    const { summary } = calculateSettlements(participants, trip.items, baseCurr, rates);

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
        <div style="margin-bottom:12px;">
          <h3 style="font-size:1rem; font-weight:700; color:var(--text-main); margin-bottom:2px;">부부 공동 경비 대시보드</h3>
          <span style="font-size:0.78rem; color:var(--text-muted);">통화: KRW (원) | 모든 지출은 부부 공동 경비로 통합 집계됩니다.</span>
        </div>

        <!-- 상단 요약 통계 -->
        <div class="summary-stat-grid">
          <div class="stat-card">
            <span class="stat-label">총 여행 경비 (KRW 원)</span>
            <span class="stat-value">${formatAmount(summary.totalInBase, 'KRW')}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">1인당 평균 경비 (2인 기준)</span>
            <span class="stat-value" style="color:var(--primary-600);">${formatAmount(perPerson, 'KRW')}</span>
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
              <span class="expense-cat-amount">${formatAmount(catAmt, 'KRW')}</span>
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

        <!-- 공동 결제 현황 (통합 안내) -->
        <div class="settlement-route-box">
          <div class="settlement-route-title">
            ${getIcon('CHECK', { size: 16, color: 'var(--primary-600)' })}
            <span>공동 결제 현황</span>
          </div>
          <div style="font-size:0.875rem; color:var(--text-main); line-height:1.5; padding:6px 0;">
            모든 지출은 공동 결제(부부 공동 경비)로 처리되어 별도의 개인간 송금 정산이 필요 없습니다.
          </div>
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
    if (typeof document !== 'undefined' && document.body) {
      document.body.classList.add('modal-open');
    }
  }

  function closeModal() {
    dom.modalOverlay.classList.remove('is-open', 'picker-mode-active');
    dom.modalContainer.innerHTML = '';
    mapManager.setPinDropMode(false);
    dom.pinPickerBar?.classList.add('hidden');
    activePickerCoord = null;
    if (typeof document !== 'undefined' && document.body) {
      document.body.classList.remove('modal-open');
    }
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

    // 위치 초기화 버튼 (#btn-clear-location)
    /**
     * @intent 지정된 위치(위도, 경도, 장소명) 초기화 및 UI 뱃지/버튼 상태 리셋
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    const clearLocationBtn = document.getElementById('btn-clear-location');
    clearLocationBtn?.addEventListener('click', () => {
      const latInput = document.getElementById('item-lat');
      const lngInput = document.getElementById('item-lng');
      const searchInput = document.getElementById('place-search-input');
      const statusBadge = document.getElementById('location-status-badge');
      const badgeText = document.getElementById('location-badge-text');
      const pickBtn = document.getElementById('btn-pick-on-map');

      if (latInput) {
        latInput.value = '';
        latInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (lngInput) {
        lngInput.value = '';
        lngInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (searchInput) {
        searchInput.value = '';
        searchInput.dispatchEvent(new Event('input', { bubbles: true }));
      }

      statusBadge?.classList.remove('has-location');
      if (badgeText) {
        badgeText.textContent = '지도에서 위치를 지정해 주세요';
      }
      const pickBtnSpan = pickBtn?.querySelector('span');
      if (pickBtnSpan) {
        pickBtnSpan.textContent = '지도 핀 지정';
      }
      clearLocationBtn.classList.add('hidden');
      activePickerCoord = null;
      mapManager.setPinDropMode(false);
      showToast('위치 지정이 해제되었습니다.');
    });

    // 지도 핀 드롭 버튼 클릭 (지도 핀 위치 선택 모드 진입)
    const pickOnMapBtn = document.getElementById('btn-pick-on-map');
    pickOnMapBtn?.addEventListener('click', () => {
      dom.modalOverlay.classList.add('picker-mode-active');
      previousSheetStateBeforePicker = currentSheetState;
      if (window.innerWidth <= 900) {
        syncMobileNavActiveState('map');
        setBottomSheetState('hidden');
      }
      mapManager.invalidateSize();

      dom.pinPickerBar?.classList.remove('hidden');
      if (dom.pinPickerAddress) {
        dom.pinPickerAddress.textContent = '위치를 선택해 주세요';
      }
      if (dom.btnPinPickerConfirm) {
        dom.btnPinPickerConfirm.disabled = true;
      }
      mapManager.setPinDropMode(true);
      activePickerCoord = null;

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
   * @intent 일정 등록/수정 모달 호출 별칭 함수 (openItemModal 위임)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function openItemEditModal(item) {
    openItemModal(item);
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
        <input type="hidden" id="meta-base-currency" name="baseCurrency" value="KRW" />
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
   * @intent 여행 기간 포맷팅 (박/일수 계산)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} startDate 
   * @param {string} endDate 
   * @returns {string} 기간 및 박수 문자열
   */
  function getTripDurationText(startDate, endDate) {
    if (!startDate || !endDate) return '기간 미정';
    const start = new Date(startDate);
    const end = new Date(endDate);
    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      return `${startDate} ~ ${endDate}`;
    }
    const diffDays = Math.round((end - start) / (1000 * 60 * 60 * 24));
    if (diffDays < 0) return `${startDate} ~ ${endDate}`;
    if (diffDays === 0) return `${startDate} (당일치기)`;
    return `${startDate} ~ ${endDate} (${diffDays}박 ${diffDays + 1}일)`;
  }

  /**
   * @intent 여행 총 예상 경비 계산 (기준 통화 환산 합계)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip 
   * @returns {number} 기준 통화 환산 총합
   */
  function calculateTripTotalExpense(trip) {
    if (!trip || !Array.isArray(trip.items) || trip.items.length === 0) return 0;
    const rates = (trip.metadata && trip.metadata.customRates) || {};
    const baseCurrency = (trip.metadata && trip.metadata.baseCurrency) || 'KRW';
    let total = 0;
    trip.items.forEach((item) => {
      const cost = Number(item.cost) || 0;
      if (cost > 0) {
        total += TripExpense.convertCurrency(cost, item.currency || baseCurrency, baseCurrency, rates);
      }
    });
    return Math.round(total);
  }

  /**
   * @intent Day별 주요 일정 요약 목록 추출 (비교 뷰용)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip 
   * @returns {Array<{day: number, text: string}>} 일자별 요약 배열
   */
  function getTripDaySummaries(trip) {
    const items = (trip && Array.isArray(trip.items)) ? trip.items : [];
    if (items.length === 0) {
      return [{ day: 1, text: '등록된 일정 없음' }];
    }
    const maxDay = Math.max(1, ...items.map((it) => Number(it.day) || 1));
    const summaries = [];
    for (let d = 1; d <= maxDay; d++) {
      const dayItems = items.filter((it) => (Number(it.day) || 1) === d);
      if (dayItems.length === 0) {
        summaries.push({ day: d, text: '일정 없음' });
      } else {
        const titles = dayItems.slice(0, 3).map((it) => it.title || '일정').join(', ');
        const more = dayItems.length > 3 ? ` 외 ${dayItems.length - 3}건` : '';
        summaries.push({ day: d, text: `${titles}${more}` });
      }
    }
    return summaries;
  }

  /**
   * @intent 복수 여행 계획 관리 및 비교 모달 팝업 열기
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {'list'|'compare'} initialTab - 초기 활성 탭
   */
  function openTripManagerModal(initialTab = 'list') {
    const trips = store.getTrips();
    const currentTripId = store.getState().currentTripId;

    const renderContent = (activeTab) => {
      let html = `
        <div class="trip-modal-tabs" role="tablist">
          <button type="button" class="trip-modal-tab-btn${activeTab === 'list' ? ' active' : ''}" data-tab="list" role="tab">
            ${getIcon('FOLDER', { size: 16 })}
            <span>계획 목록 (${trips.length})</span>
          </button>
          <button type="button" class="trip-modal-tab-btn${activeTab === 'compare' ? ' active' : ''}" data-tab="compare" role="tab">
            ${getIcon('COMPARE', { size: 16 })}
            <span>계획 한눈에 비교</span>
          </button>
        </div>
      `;

      if (activeTab === 'list') {
        html += `
          <div class="trip-manager-toolbar">
            <span class="trip-manager-count">총 ${trips.length}개의 여행 계획이 보관되어 있습니다.</span>
            <button type="button" id="btn-open-create-trip" class="btn-create-trip">
              ${getIcon('PLUS', { size: 16 })}
              <span>새 여행 계획 만들기</span>
            </button>
          </div>
          <div class="trip-card-grid">
        `;

        trips.forEach((trip) => {
          const isSelected = trip.metadata && trip.metadata.id === currentTripId;
          const totalCost = calculateTripTotalExpense(trip);
          const baseCurrency = (trip.metadata && trip.metadata.baseCurrency) || 'KRW';
          const durationText = getTripDurationText(trip.metadata && trip.metadata.startDate, trip.metadata && trip.metadata.endDate);
          const itemCount = (trip.items || []).length;
          const tripId = (trip.metadata && trip.metadata.id) || '';

          html += `
            <div class="trip-plan-card${isSelected ? ' is-selected' : ''}" data-id="${escapeHtml(tripId)}">
              <div class="trip-card-header">
                <div class="trip-card-title-wrap">
                  <div class="trip-card-title">${escapeHtml((trip.metadata && trip.metadata.title) || '새로운 여행 계획')}</div>
                </div>
                ${isSelected ? `<span class="badge-selected">[선택됨]</span>` : ''}
              </div>

              <div class="trip-card-meta">
                <div class="trip-card-meta-row">
                  <span class="trip-card-meta-label">여행 기간</span>
                  <span class="trip-card-meta-val">${escapeHtml(durationText)}</span>
                </div>
                <div class="trip-card-meta-row">
                  <span class="trip-card-meta-label">등록 일정</span>
                  <span class="trip-card-meta-val">${itemCount}개</span>
                </div>
                <div class="trip-card-meta-row">
                  <span class="trip-card-meta-label">총 경비</span>
                  <span class="trip-card-meta-val">${formatAmount(totalCost, baseCurrency)}</span>
                </div>
              </div>

              <div class="trip-card-actions">
                ${
                  isSelected
                    ? `<button type="button" class="btn btn-secondary btn-sm" disabled>선택 중</button>`
                    : `<button type="button" class="btn btn-primary btn-sm btn-select-trip" data-id="${escapeHtml(tripId)}">이 계획 선택</button>`
                }
                <button type="button" class="btn btn-outline btn-sm btn-duplicate-trip" data-id="${escapeHtml(tripId)}" title="계획 복제">
                  ${getIcon('COPY', { size: 14 })}
                  <span>복제</span>
                </button>
                ${
                  trips.length > 1
                    ? `<button type="button" class="btn btn-danger btn-sm btn-delete-trip" data-id="${escapeHtml(tripId)}" title="계획 삭제">
                        ${getIcon('DELETE', { size: 14 })}
                      </button>`
                    : ''
                }
              </div>
            </div>
          `;
        });

        html += `</div>`;
      } else {
        // compare 탭 (계획 한눈에 비교 뷰)
        html += `
          <div class="trip-compare-container">
            <div class="trip-compare-grid">
        `;

        trips.forEach((trip) => {
          const isSelected = trip.metadata && trip.metadata.id === currentTripId;
          const totalCost = calculateTripTotalExpense(trip);
          const baseCurrency = (trip.metadata && trip.metadata.baseCurrency) || 'KRW';
          const durationText = getTripDurationText(trip.metadata && trip.metadata.startDate, trip.metadata && trip.metadata.endDate);
          const itemCount = (trip.items || []).length;
          const daySummaries = getTripDaySummaries(trip);
          const tripId = (trip.metadata && trip.metadata.id) || '';

          html += `
            <div class="trip-compare-card${isSelected ? ' is-current' : ''}">
              <div class="trip-compare-header">
                <div class="trip-compare-title">${escapeHtml((trip.metadata && trip.metadata.title) || '새로운 여행 계획')}</div>
                ${isSelected ? `<span class="badge-selected">[현재 활성]</span>` : ''}
              </div>

              <div class="trip-compare-stats">
                <div class="trip-compare-stat-item">
                  <span class="trip-compare-stat-label">기간</span>
                  <span class="trip-compare-stat-val">${escapeHtml(durationText)}</span>
                </div>
                <div class="trip-compare-stat-item">
                  <span class="trip-compare-stat-label">총 예상 경비</span>
                  <span class="trip-compare-stat-val">${formatAmount(totalCost, baseCurrency)}</span>
                </div>
                <div class="trip-compare-stat-item">
                  <span class="trip-compare-stat-label">방문지 / 일정</span>
                  <span class="trip-compare-stat-val">${itemCount}개</span>
                </div>
                <div class="trip-compare-stat-item">
                  <span class="trip-compare-stat-label">참가 인원</span>
                  <span class="trip-compare-stat-val">${((trip.metadata && trip.metadata.participants) || []).length}명</span>
                </div>
              </div>

              <div style="font-size:0.8rem; font-weight:700; color:var(--text-main); margin-bottom:6px;">
                Day별 주요 일정 요약
              </div>
              <div class="trip-compare-day-list">
          `;

          daySummaries.forEach((sum) => {
            html += `
              <div class="trip-compare-day-item">
                <span class="trip-compare-day-badge">Day ${sum.day}</span>
                <span class="trip-compare-day-summary">${escapeHtml(sum.text)}</span>
              </div>
            `;
          });

          html += `
              </div>

              <div class="trip-compare-actions">
                ${
                  isSelected
                    ? `<button type="button" class="btn btn-secondary btn-sm" style="width:100%;" disabled>현재 보는 중</button>`
                    : `<button type="button" class="btn btn-primary btn-sm btn-select-trip" data-id="${escapeHtml(tripId)}" style="width:100%;">이 계획으로 보기</button>`
                }
              </div>
            </div>
          `;
        });

        html += `
            </div>
          </div>
        `;
      }

      return html;
    };

    openModal('여행 계획 관리 및 비교', renderContent(initialTab));

    function bindEvents(activeTab) {
      // 서브 탭 전환 이벤트
      dom.modalContainer.querySelectorAll('.trip-modal-tab-btn').forEach((btn) => {
        btn.addEventListener('click', () => {
          const nextTab = btn.dataset.tab;
          dom.modalContainer.innerHTML = renderContent(nextTab);
          bindEvents(nextTab);
        });
      });

      // 새 여행 계획 생성 버튼 이벤트
      document.getElementById('btn-open-create-trip')?.addEventListener('click', () => {
        openCreateTripModal();
      });

      // 계획 선택 이벤트
      dom.modalContainer.querySelectorAll('.btn-select-trip').forEach((btn) => {
        btn.addEventListener('click', () => {
          const tripId = btn.dataset.id;
          const target = store.switchTrip(tripId);
          if (target) {
            closeModal();
            showToast(`'${target.metadata.title || '선택한'}' 계획으로 전환되었습니다.`);
          }
        });
      });

      // 계획 복제 이벤트
      dom.modalContainer.querySelectorAll('.btn-duplicate-trip').forEach((btn) => {
        btn.addEventListener('click', () => {
          const tripId = btn.dataset.id;
          const duplicated = store.duplicateTrip(tripId);
          if (duplicated) {
            closeModal();
            showToast(`'${duplicated.metadata.title}' 계획이 복제되었습니다.`);
          }
        });
      });

      // 계획 삭제 이벤트
      dom.modalContainer.querySelectorAll('.btn-delete-trip').forEach((btn) => {
        btn.addEventListener('click', () => {
          const tripId = btn.dataset.id;
          const targetTrip = store.getTrips().find((t) => t.metadata && t.metadata.id === tripId);
          const targetTitle = (targetTrip && targetTrip.metadata && targetTrip.metadata.title) || '이 여행 계획';
          if (confirm(`'${targetTitle}' 여행 계획을 완전히 삭제하시겠습니까?\n삭제 후에는 복구할 수 없습니다.`)) {
            const success = store.deleteTrip(tripId);
            if (success) {
              showToast(`'${targetTitle}' 계획이 삭제되었습니다.`);
              openTripManagerModal('list');
            } else {
              showToast('최소 1개의 여행 계획은 유지되어야 하므로 삭제할 수 없습니다.');
            }
          }
        });
      });
    }

    bindEvents(initialTab);
  }

  /**
   * @intent 신규 여행 계획 생성 모달 폼 열기
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function openCreateTripModal() {
    const contentHtml = `
      <form id="create-trip-form" class="editor-form">
        <div class="form-group">
          <label class="form-label" for="create-trip-title">여행 제목 <span class="required">*</span></label>
          <input type="text" id="create-trip-title" name="title" class="form-control" required placeholder="예: 오사카 3박 4일 미식 탐방" value="" />
        </div>
        <div class="form-row">
          <div class="form-group flex-1">
            <label class="form-label" for="create-trip-start">출발일</label>
            <input type="date" id="create-trip-start" name="startDate" class="form-control" value="" />
          </div>
          <div class="form-group flex-1">
            <label class="form-label" for="create-trip-end">도착일</label>
            <input type="date" id="create-trip-end" name="endDate" class="form-control" value="" />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label" for="create-trip-participants">참가자 명단 (콤마 구분)</label>
          <input type="text" id="create-trip-participants" name="participants" class="form-control" placeholder="예: 신랑, 신부 또는 민우, 지훈, 서연" value="신랑, 신부" />
          <span style="font-size:0.72rem; color:var(--text-muted); margin-top:2px;">
            1/N 정산에 참여할 멤버들의 이름을 쉼표로 구분하여 입력해 주세요.
          </span>
        </div>
        <input type="hidden" id="create-trip-currency" name="baseCurrency" value="KRW" />
        <div class="modal-form-actions">
          <button type="button" id="btn-create-trip-cancel" class="btn btn-secondary">취소</button>
          <button type="submit" class="btn btn-primary">
            ${getIcon('CHECK', { size: 16 })} <span>새 계획 만들기</span>
          </button>
        </div>
      </form>
    `;

    openModal('새 여행 계획 만들기', contentHtml);

    document.getElementById('btn-create-trip-cancel')?.addEventListener('click', () => {
      openTripManagerModal('list');
    });

    document.getElementById('create-trip-form')?.addEventListener('submit', (e) => {
      e.preventDefault();
      const form = e.target;
      const title = form.title.value.trim() || '새로운 여행 계획';
      const startDate = form.startDate.value;
      const endDate = form.endDate.value;
      const rawParticipants = form.participants.value;
      const participants = rawParticipants
        .split(',')
        .map((p) => p.trim())
        .filter((p) => p.length > 0);
      const baseCurrency = form.baseCurrency.value || 'KRW';

      const newTrip = store.createTrip({
        title,
        startDate,
        endDate,
        participants: participants.length > 0 ? participants : ['신랑', '신부'],
        baseCurrency
      });

      closeModal();
      showToast(`'${newTrip.metadata.title}' 계획이 생성되었습니다.`);
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

    // 3. 지도 마커 클릭 시 타임라인 카드 포커스 및 바텀시트 연동
    /**
     * @intent 지도 마커 클릭 시 해당 일정 일차/탭/바텀시트 동기화 및 하이라이트 애니메이션
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    mapManager.setMarkerClickListener((itemId) => {
      const trip = store.getCurrentTrip();
      const item = (trip.items || []).find((it) => it.id === itemId);
      if (!item) return;

      if (Number(item.day) !== Number(store.getState().selectedDay)) {
        store.setSelectedDay(Number(item.day));
      }
      if (store.getState().activeTab !== 'timeline') {
        store.setActiveTab('timeline');
      }
      if (window.innerWidth <= 900) {
        if (currentSheetState === 'hidden' || currentSheetState === 'peek') {
          setBottomSheetState('half');
        }
      }
      store.setSelectedItemId(itemId);
      setTimeout(() => {
        const card = dom.panelContentArea.querySelector(`[data-id="${itemId}"]`);
        if (card) {
          card.scrollIntoView({ behavior: 'smooth', block: 'center' });
          card.classList.add('card-highlight-pulse');
          setTimeout(() => card.classList.remove('card-highlight-pulse'), 1600);
        }
      }, 60);
    });

    // 4. 지도 핀 드롭 리스너 연동
    /**
     * @intent 지도 핀 클릭 시 즉각 좌표 할당 및 2.5초 타임아웃 기반 비동기 역지오코딩 처리
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    mapManager.setPinDropListener(async (lat, lng) => {
      // 핀 마커 표시
      mapManager.setPinDropPreview(lat, lng);

      // 위치 선택 바 UI 활성화 여부 확인
      const isPickerActive = dom.pinPickerBar && !dom.pinPickerBar.classList.contains('hidden');
      if (isPickerActive) {
        // 지도를 클릭하는 순간(0초), 역지오코딩 완료를 대기하지 않고 즉시 기본 좌표로 activePickerCoord를 먼저 생성
        const fallbackCoordText = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
        activePickerCoord = {
          lat,
          lng,
          name: fallbackCoordText,
          address: fallbackCoordText
        };
        if (dom.btnPinPickerConfirm) {
          dom.btnPinPickerConfirm.disabled = false;
        }
        if (dom.pinPickerAddress) {
          dom.pinPickerAddress.textContent = `주소 확인 중... (${fallbackCoordText})`;
        }

        try {
          const timeoutPromise = new Promise((_, reject) => {
            setTimeout(() => reject(new Error('timeout')), 2500);
          });
          const place = await Promise.race([TripGeocoder.reverseGeocode(lat, lng), timeoutPromise]);
          const placeName = (place && place.name) || '';
          const placeAddress = (place && (place.address || place.displayName)) || '';
          const displayAddress = placeName || placeAddress || fallbackCoordText;

          if (dom.pinPickerAddress) {
            dom.pinPickerAddress.textContent = displayAddress;
          }
          activePickerCoord = {
            lat,
            lng,
            name: placeName || fallbackCoordText,
            address: placeAddress || fallbackCoordText
          };
          if (dom.btnPinPickerConfirm) {
            dom.btnPinPickerConfirm.disabled = false;
          }
        } catch (err) {
          if (dom.pinPickerAddress) {
            dom.pinPickerAddress.textContent = fallbackCoordText;
          }
          activePickerCoord = {
            lat,
            lng,
            name: fallbackCoordText,
            address: fallbackCoordText
          };
          if (dom.btnPinPickerConfirm) {
            dom.btnPinPickerConfirm.disabled = false;
          }
        }
      } else {
        // 일반 지도 핀 드롭 모드
        const latInput = document.getElementById('item-lat');
        const lngInput = document.getElementById('item-lng');
        if (latInput && lngInput) {
          latInput.value = lat.toFixed(5);
          lngInput.value = lng.toFixed(5);
          latInput.dispatchEvent(new Event('input', { bubbles: true }));
          lngInput.dispatchEvent(new Event('input', { bubbles: true }));

          const statusBadge = document.getElementById('location-status-badge');
          const badgeText = document.getElementById('location-badge-text');
          const pickBtn = document.getElementById('btn-pick-on-map');
          const clearBtn = document.getElementById('btn-clear-location');

          if (statusBadge) statusBadge.classList.add('has-location');
          if (badgeText) badgeText.textContent = `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
          const pickBtnSpan = pickBtn?.querySelector('span');
          if (pickBtnSpan) pickBtnSpan.textContent = '위치 변경';
          if (clearBtn) clearBtn.classList.remove('hidden');
        }
        showToast(`핀 좌표 선택 완료: ${lat.toFixed(4)}, ${lng.toFixed(4)}`);

        try {
          const timeoutPromise = new Promise((_, reject) => {
            setTimeout(() => reject(new Error('timeout')), 2500);
          });
          const place = await Promise.race([TripGeocoder.reverseGeocode(lat, lng), timeoutPromise]);
          const searchInput = document.getElementById('place-search-input');
          if (searchInput && place && place.name) {
            searchInput.value = place.name;
            searchInput.dispatchEvent(new Event('input', { bubbles: true }));
            const badgeText = document.getElementById('location-badge-text');
            if (badgeText) badgeText.textContent = place.name;
          }
        } catch (err) {
          // 무시
        }
      }
    });

    // 4-1. 지도 핀 위치 선택 완료 버튼 (#btn-pin-picker-confirm)
    /**
     * @intent 핀 선택 완료 시 폼 필드 주입, 위치 뱃지 업데이트 및 모달 팝업 복귀 확실성 보장
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    dom.btnPinPickerConfirm?.addEventListener('click', () => {
      if (!activePickerCoord) {
        showToast('선택된 핀 위치가 없습니다.');
        return;
      }

      const { lat, lng, name, address } = activePickerCoord;
      const latInput = document.getElementById('item-lat');
      const lngInput = document.getElementById('item-lng');
      const searchInput = document.getElementById('place-search-input');
      const titleInput = document.getElementById('item-title');

      if (latInput) {
        latInput.value = lat.toFixed(5);
        latInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (lngInput) {
        lngInput.value = lng.toFixed(5);
        lngInput.dispatchEvent(new Event('input', { bubbles: true }));
      }

      const placeLabel = name || address || '';
      if (searchInput) {
        searchInput.value = placeLabel;
        searchInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (titleInput && !titleInput.value.trim()) {
        titleInput.value = placeLabel;
        titleInput.dispatchEvent(new Event('input', { bubbles: true }));
      }

      // 위치 뱃지 및 버튼 상태 업데이트
      const statusBadge = document.getElementById('location-status-badge');
      const badgeText = document.getElementById('location-badge-text');
      const pickBtn = document.getElementById('btn-pick-on-map');
      const clearBtn = document.getElementById('btn-clear-location');

      if (statusBadge) {
        statusBadge.classList.add('has-location');
      }
      if (badgeText) {
        badgeText.textContent = placeLabel || `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
      }
      const pickBtnSpan = pickBtn?.querySelector('span');
      if (pickBtnSpan) {
        pickBtnSpan.textContent = '위치 변경';
      }
      if (clearBtn) {
        clearBtn.classList.remove('hidden');
      }

      // 카테고리별 명칭 필드가 비어있다면 자동 입력:
      // 숙소(HOTEL): #hotel-name
      // 명소(ATTRACTION): #attraction-name
      // 식당(DINING): #dining-name
      // 공항(AIRPORT): #airport-name
      ['hotel-name', 'attraction-name', 'dining-name', 'airport-name'].forEach((fieldId) => {
        const fieldEl = document.getElementById(fieldId);
        if (fieldEl && !fieldEl.value.trim()) {
          fieldEl.value = placeLabel;
          fieldEl.dispatchEvent(new Event('input', { bubbles: true }));
        }
      });

      // 핀 모드 종료 및 모달 복귀 확실성 보장
      mapManager.setPinDropMode(false);
      dom.pinPickerBar?.classList.add('hidden');
      dom.modalOverlay.classList.remove('picker-mode-active');
      dom.modalOverlay.classList.add('is-open');
      if (typeof document !== 'undefined' && document.body) {
        document.body.classList.add('modal-open');
      }

      if (window.innerWidth <= 900) {
        setBottomSheetState(previousSheetStateBeforePicker || 'half');
      }

      showToast('선택한 위치가 입력되었습니다.');
    });

    // 4-2. 지도 핀 위치 선택 취소 버튼 (#btn-pin-picker-cancel)
    /**
     * @intent 핀 선택 취소 시 모달 복귀 확실성 보장
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    dom.btnPinPickerCancel?.addEventListener('click', () => {
      mapManager.setPinDropMode(false);
      dom.pinPickerBar?.classList.add('hidden');
      dom.modalOverlay.classList.remove('picker-mode-active');
      dom.modalOverlay.classList.add('is-open');
      if (typeof document !== 'undefined' && document.body) {
        document.body.classList.add('modal-open');
      }

      if (window.innerWidth <= 900) {
        setBottomSheetState(previousSheetStateBeforePicker || 'half');
      }

      showToast('위치 선택을 취소했습니다.');
    });

    // 5. 내비게이션 탭 이벤트 (일정, 경비)
    dom.tabTimeline.addEventListener('click', () => {
      store.setActiveTab('timeline');
      if (currentSheetState === 'hidden') setBottomSheetState('half');
    });
    dom.tabExpense.addEventListener('click', () => {
      store.setActiveTab('expense');
      if (currentSheetState === 'hidden') setBottomSheetState('half');
    });

    // 6. 모바일 하단 내비게이션 바 버튼 리스너 (지도, 일정, 추가, 경비)
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

    // 13. 상단 헤더 액션 및 여행 관리 버튼
    dom.btnManageTrips?.addEventListener('click', () => {
      openTripManagerModal('list');
    });

    dom.brandInfo?.addEventListener('click', () => {
      openTripManagerModal('list');
    });

    dom.brandInfo?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openTripManagerModal('list');
      }
    });

    dom.tripTitle?.addEventListener('click', (e) => {
      e.stopPropagation();
      openTripManagerModal('list');
    });

    dom.btnCopyShareLink?.addEventListener('click', async () => {
      const currentTrip = store.getState().trip;
      const shareUrl = generateShareUrl(currentTrip);
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(shareUrl);
        } else {
          const tempInput = document.createElement('textarea');
          tempInput.value = shareUrl;
          document.body.appendChild(tempInput);
          tempInput.select();
          document.execCommand('copy');
          tempInput.remove();
        }
        showToast('여행 일정 링크가 복사되었습니다!');
      } catch (err) {
        showToast('링크 복사에 실패했습니다.');
      }
    });

    dom.btnEditTrip?.addEventListener('click', openTripMetaModal);

    // 14. 중앙 상태(Store) 변경 감지 구독
    store.subscribe((state) => {
      const { trip, selectedDay, selectedItemId, activeTab } = state;

      // 헤더 렌더링
      renderHeader(trip);

      // 탭 활성화 상태 (일정, 경비)
      [dom.tabTimeline, dom.tabExpense].forEach((t) => t?.classList.remove('active'));
      if (activeTab === 'timeline') dom.tabTimeline?.classList.add('active');
      else if (activeTab === 'expense') dom.tabExpense?.classList.add('active');

      // Day 선택 탭 표시/숨김
      if (activeTab === 'timeline') {
        if (dom.dayChipSliderWrapper) dom.dayChipSliderWrapper.classList.remove('hidden');
        renderDayTabs(trip, selectedDay);
        renderTimelinePanel(trip, selectedDay, selectedItemId);
      } else if (activeTab === 'expense') {
        if (dom.dayChipSliderWrapper) dom.dayChipSliderWrapper.classList.add('hidden');
        renderExpensePanel(trip);
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

    // 15. 지도 팝업 내 [상세보기 / 수정] 버튼 클릭 글로벌 이벤트 위임
    /**
     * @intent 지도 팝업 내 상세보기/수정 버튼 클릭 시 해당 일정 편집 모달 오픈
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    document.addEventListener('click', (e) => {
      const btn = e.target.closest('.btn-popup-view');
      if (!btn) return;
      const itemId = btn.dataset.itemId;
      const trip = store.getCurrentTrip();
      const item = (trip.items || []).find((it) => it.id === itemId);
      if (item) openItemEditModal(item);
    });
  }

  // DOM 로드 완료 시 구동
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }
})();
