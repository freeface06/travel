/**
 * @intent 헤더 메뉴 및 타임라인/지도 동선 뷰어 - 전체 일차('all') 동선 및 타임라인 한눈에 보기 지원
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function () {
  'use strict';

  const { store } = TripStore;
  const { mapManager, getDayColor } = TripMap;
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
    tripDdayBadge: document.getElementById('trip-dday-badge'),
    tripSummaryChip: document.getElementById('trip-summary-chip'),
    btnHeaderMenu: document.getElementById('btn-header-menu'),
    headerDropdownMenu: document.getElementById('header-dropdown-menu'),
    btnMenuEditTrip: document.getElementById('btn-menu-edit-trip'),
    btnMenuManageTrips: document.getElementById('btn-menu-manage-trips'),
    btnMenuCopyShare: document.getElementById('btn-menu-copy-share'),
    // 기존 호환용 요소 (선택적 참조)
    btnManageTrips: document.getElementById('btn-manage-trips'),
    btnOpenCloudSync: document.getElementById('btn-open-cloud-sync'),
    cloudSyncBadgeText: document.getElementById('cloud-sync-badge-text'),
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
    lightboxCloseBtn: document.getElementById('btn-close-lightbox') || document.getElementById('lightbox-close-btn'),
    btnLightboxPrev: document.getElementById('btn-lightbox-prev'),
    btnLightboxNext: document.getElementById('btn-lightbox-next'),
    lightboxCounter: document.getElementById('lightbox-counter'),

    // 토스트
    toastContainer: document.getElementById('toast-container')
  };

  // 라이트박스 갤러리 상태
  let currentLightboxGallery = [];
  let currentLightboxIndex = 0;

  // 모바일 바텀시트 상태: 'hidden', 'peek' (60px), 'half' (52vh), 'full' (전체)
  let currentSheetState = 'half';
  let previousSheetStateBeforePicker = 'half';
  let activePickerCoord = null;

  /**
   * @intent 모바일 하단 내비게이션 활성 탭 UI 동기화 (targetName falsy 시 전 메뉴 비활성화 보장)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string|null} targetName 
   */
  function syncMobileNavActiveState(targetName) {
    if (!dom.mobileBottomNav) return;
    const items = dom.mobileBottomNav.querySelectorAll('.m-nav-item');
    if (!targetName) {
      items.forEach((btn) => btn.classList.remove('active'));
      return;
    }
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
   * @intent 구글맵 좌표 문자열(위도, 경도) 파싱 유틸리티 - 복사된 다양한 형식(쉼표, 공백, 괄호 등)을 분석하여 위도/경도 객체 추출
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} str - 좌표 문자열
   * @returns {{lat: number, lng: number}|null} 유효한 좌표 객체 또는 null
   */
  const parseCoordinates = (typeof TripForms !== 'undefined' && typeof TripForms.parseCoordinates === 'function')
    ? TripForms.parseCoordinates
    : function (str) {
        if (!str) return null;
        const clean = str.replace(/[()]/g, '').trim();
        const match = clean.match(/^(-?\d+(?:\.\d+)?)[,\s/]+(-?\d+(?:\.\d+)?)$/);
        if (!match) return null;
        const lat = parseFloat(match[1]);
        const lng = parseFloat(match[2]);
        if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
        return { lat, lng };
      };

  /**
   * @intent 모바일 바텀시트 상태 설정 및 인라인 트랜스폼 리셋 (hidden 시 하단 네비 비활성화 및 반응형 지도 리사이즈)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {'hidden'|'peek'|'half'|'full'} state 
   */
  function setBottomSheetState(state) {
    currentSheetState = state;
    if (dom.sidePanel) {
      dom.sidePanel.style.removeProperty('transform');
      dom.sidePanel.style.removeProperty('transition');
      dom.sidePanel.classList.remove('sheet-hidden', 'sheet-peek', 'sheet-half', 'sheet-full');
      dom.sidePanel.classList.add(`sheet-${state}`);
    }

    if (state === 'hidden') {
      syncMobileNavActiveState(null);
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
   * @intent 모바일 바텀시트 손잡이 1:1 실시간 추종 및 바디 최상단 스크롤 풀다운 축소 제스처 엔진
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function initBottomSheetTouchGesture() {
    const handle = dom.bottomSheetHandle;
    const panel = dom.sidePanel;
    const contentArea = dom.panelContentArea;
    if (!handle || !panel) return;

    // 핸들 또는 상단 핸들 컨테이너 전체를 터치 타겟으로 활용
    const handleTarget = handle.parentElement || handle;

    let isDragging = false;
    let isBodyDragging = false;
    let startY = 0;
    let lastY = 0;
    let lastTime = 0;
    let velocity = 0; // px / ms (아래로: 양수, 위로: 음수)
    let baseY = 0;
    let panelHeight = 0;
    let activePointerId = null;

    // 본문 풀다운 제스처 관련 상태
    let bodyStartY = 0;
    let bodyLastDeltaY = 0;
    let initialScrollTop = 0;

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

    // ==========================================
    // A. 손잡이(핸들) 실시간 1:1 드래그 추종 & 스냅 고정
    // ==========================================
    function onPointerDown(e) {
      if (window.innerWidth > 900) return;
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      if (isBodyDragging) return;

      isDragging = true;
      activePointerId = e.pointerId ?? null;
      startY = e.clientY;
      lastY = e.clientY;
      lastTime = performance.now();
      velocity = 0;

      panelHeight = panel.getBoundingClientRect().height || (window.innerHeight - 122);
      baseY = getBaseYForState(currentSheetState, panelHeight);

      panel.classList.add('is-dragging');
      panel.style.setProperty('transition', 'none', 'important');

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

      // 상단 위로 오버드래그 시 탄성 저항
      if (currentY < 0) {
        currentY = currentY * 0.25;
      }

      // 하단 오버드래그 시 탄성 저항
      const maxOffset = panelHeight + 80;
      if (currentY > maxOffset) {
        const overDistance = currentY - maxOffset;
        currentY = maxOffset + overDistance * 0.25;
      }

      panel.style.setProperty('transform', `translate3d(0, ${currentY}px, 0)`, 'important');
    }

    function onPointerUp(e) {
      if (!isDragging) return;
      if (activePointerId !== null && e.pointerId !== undefined && e.pointerId !== activePointerId) return;

      isDragging = false;

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
        panel.classList.remove('is-dragging');
        panel.style.removeProperty('transform');
        panel.style.removeProperty('transition');
        cycleBottomSheetState();
        return;
      }

      // 2. 현재 Y 좌표 계산 (탄성 저항 반영)
      let currentY = baseY + deltaY;
      if (currentY < 0) {
        currentY = currentY * 0.25;
      }
      const maxOffset = panelHeight + 80;
      if (currentY > maxOffset) {
        currentY = maxOffset + (currentY - maxOffset) * 0.25;
      }

      let targetState = currentSheetState;

      // 플릭(속도 velocity) 및 최종 위치 종합 분석
      const isFlickDown = velocity > 0.45 || (deltaY > 120 && velocity > 0.2);
      const isFlickUp = velocity < -0.45 || (deltaY < -120 && velocity < -0.2);

      if (isFlickDown) {
        // 플릭 다운: full -> half, half -> hidden
        if (currentSheetState === 'full') {
          targetState = 'half';
        } else {
          targetState = 'hidden';
        }
      } else if (isFlickUp) {
        // 플릭 업: hidden/half -> full
        targetState = 'full';
      } else {
        // 천천히 놓았을 때 화면 비율 기준 결정
        // 0 ~ 30%: full, 30% ~ 70%: half, 70% 초과: hidden
        const ratio = currentY / panelHeight;
        if (ratio < 0.30) {
          targetState = 'full';
        } else if (ratio <= 0.70) {
          targetState = 'half';
        } else {
          targetState = 'hidden';
        }
      }

      // 3. 목표 상태 targetState 결정 후 cubic-bezier(0.16, 1, 0.3, 1) 부드러운 스냅 애니메이션 적용 후 완료
      const targetY = getBaseYForState(targetState, panelHeight);
      panel.style.setProperty('transition', 'transform 0.36s cubic-bezier(0.16, 1, 0.3, 1)', 'important');
      panel.style.setProperty('transform', `translate3d(0, ${targetY}px, 0)`, 'important');

      let snapFinished = false;
      const finalizeSnap = () => {
        if (snapFinished) return;
        snapFinished = true;
        panel.removeEventListener('transitionend', onTransitionEnd);
        panel.classList.remove('is-dragging');
        panel.style.removeProperty('transition');
        panel.style.removeProperty('transform');
        setBottomSheetState(targetState);
      };

      const onTransitionEnd = (evt) => {
        if (evt && evt.propertyName !== 'transform') return;
        finalizeSnap();
      };

      panel.addEventListener('transitionend', onTransitionEnd);
      setTimeout(finalizeSnap, 380);
    }

    // ==========================================
    // B. 바텀시트 바디(본문) 스와이프 양방향 제스처 (Swipe-up to Expand, Pull-down to Collapse)
    // ==========================================
    function onBodyTouchStart(e) {
      if (window.innerWidth > 900) return;
      if (isDragging) return;
      if (!e.touches || e.touches.length === 0) return;
      if (currentSheetState === 'hidden') return;

      const touch = e.touches[0];
      bodyStartY = touch.clientY;
      bodyLastDeltaY = 0;
      isBodyDragging = false;
      initialScrollTop = contentArea ? contentArea.scrollTop : 0;

      panelHeight = panel.getBoundingClientRect().height || (window.innerHeight - 122);
      baseY = getBaseYForState(currentSheetState, panelHeight);
    }

    function onBodyTouchMove(e) {
      if (window.innerWidth > 900) return;
      if (isDragging) return;
      if (!e.touches || e.touches.length === 0) return;
      if (currentSheetState === 'hidden') return;

      const touch = e.touches[0];
      const deltaY = touch.clientY - bodyStartY;
      bodyLastDeltaY = deltaY;

      const currentScrollTop = contentArea ? contentArea.scrollTop : 0;

      if (currentSheetState === 'half' || currentSheetState === 'peek') {
        if (deltaY < 0) {
          // 브라우저 내부 스크롤 대신 바텀시트 확장 제스처 즉시 발동
          if (e.cancelable) {
            e.preventDefault();
          }
          isBodyDragging = true;
          panel.classList.add('is-dragging');
          panel.style.setProperty('transition', 'none', 'important');

          let currentY = baseY + deltaY;
          if (currentY < 0) {
            currentY = currentY * 0.25;
          }
          panel.style.setProperty('transform', `translate3d(0, ${currentY}px, 0)`, 'important');
        } else if (deltaY > 0 && (initialScrollTop <= 0 || currentScrollTop <= 0)) {
          // 최상단에서 아래로 스와이프: 실시간 하향 추종
          if (e.cancelable) {
            e.preventDefault();
          }
          isBodyDragging = true;
          panel.classList.add('is-dragging');
          panel.style.setProperty('transition', 'none', 'important');

          const currentY = baseY + deltaY * 0.85;
          panel.style.setProperty('transform', `translate3d(0, ${currentY}px, 0)`, 'important');
        }
      } else if (currentSheetState === 'full') {
        if (deltaY > 0 && (initialScrollTop <= 0 || currentScrollTop <= 0)) {
          // 최상단 상태에서 아래로 스와이프: 축소 추종
          if (e.cancelable) {
            e.preventDefault();
          }
          isBodyDragging = true;
          panel.classList.add('is-dragging');
          panel.style.setProperty('transition', 'none', 'important');

          const currentY = baseY + deltaY * 0.85;
          panel.style.setProperty('transform', `translate3d(0, ${currentY}px, 0)`, 'important');
        } else if (isBodyDragging && deltaY <= 0) {
          // 아래로 당기다가 다시 위로 올린 경우
          if (e.cancelable) {
            e.preventDefault();
          }
          let currentY = baseY + deltaY * 0.25;
          if (currentY < 0) {
            currentY = currentY * 0.25;
          }
          panel.style.setProperty('transform', `translate3d(0, ${currentY}px, 0)`, 'important');
        }
        // deltaY < 0 이거나 스크롤이 이미 내려가 있을 때는 정상적인 본문 스크롤 허용
      }
    }

    function onBodyTouchEnd() {
      if (!isBodyDragging) return;
      isBodyDragging = false;

      const deltaY = bodyLastDeltaY;
      let targetState = currentSheetState;

      if (currentSheetState === 'half' || currentSheetState === 'peek') {
        if (deltaY <= -50) {
          // 위로 50px 이상 올렸거나 위로 휙 올림: 전체 화면으로 확장
          targetState = 'full';
        } else if (deltaY >= 60) {
          // 아래로 60px 이상 내렸음: 아래로 닫힘
          targetState = 'hidden';
        } else {
          // 미세한 흔들림: 원래 상태(half) 복귀
          targetState = 'half';
        }
      } else if (currentSheetState === 'full') {
        if (deltaY >= 60) {
          // 아래로 60px 이상 내렸음: 절반으로 축소
          targetState = 'half';
        } else {
          // 원래 상태(full) 복귀
          targetState = 'full';
        }
      }

      const targetY = getBaseYForState(targetState, panelHeight);
      panel.style.setProperty('transition', 'transform 0.36s cubic-bezier(0.16, 1, 0.3, 1)', 'important');
      panel.style.setProperty('transform', `translate3d(0, ${targetY}px, 0)`, 'important');

      let snapFinished = false;
      const finalizeBodySnap = () => {
        if (snapFinished) return;
        snapFinished = true;
        panel.removeEventListener('transitionend', onBodyTransitionEnd);
        panel.classList.remove('is-dragging');
        panel.style.removeProperty('transition');
        panel.style.removeProperty('transform');
        setBottomSheetState(targetState);
      };

      const onBodyTransitionEnd = (evt) => {
        if (evt && evt.propertyName !== 'transform') return;
        finalizeBodySnap();
      };

      panel.addEventListener('transitionend', onBodyTransitionEnd);
      setTimeout(finalizeBodySnap, 380);
    }

    // 핸들 터치 이벤트 리스너 등록
    if (window.PointerEvent && handleTarget) {
      handleTarget.addEventListener('pointerdown', onPointerDown);
      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', onPointerUp);
      window.addEventListener('pointercancel', onPointerUp);
    } else if (handleTarget) {
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

    // 바텀시트 본문 스크롤 풀다운 제스처 이벤트 리스너 등록
    if (contentArea) {
      contentArea.addEventListener('touchstart', onBodyTouchStart, { passive: true });
      contentArea.addEventListener('touchmove', onBodyTouchMove, { passive: false });
      contentArea.addEventListener('touchend', onBodyTouchEnd, { passive: true });
      contentArea.addEventListener('touchcancel', onBodyTouchEnd, { passive: true });
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

  const DAY_OF_WEEK_NAMES = ['일', '월', '화', '수', '목', '금', '토'];

  /**
   * @intent 여행 시작일/종료일 기반 오늘 실시간 D-Day 계산 및 상태 문자열 산출
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} startDateStr - YYYY-MM-DD
   * @param {string} endDateStr - YYYY-MM-DD
   * @returns {{text: string, state: 'before'|'today'|'ongoing'|'completed'}|null}
   */
  function calculateTripDday(startDateStr, endDateStr) {
    if (!startDateStr) return null;

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();

    const startParts = startDateStr.split('-').map(Number);
    if (startParts.length < 3 || isNaN(startParts[0])) return null;
    const startDate = new Date(startParts[0], startParts[1] - 1, startParts[2]).getTime();

    let endDate = null;
    if (endDateStr) {
      const endParts = endDateStr.split('-').map(Number);
      if (endParts.length >= 3 && !isNaN(endParts[0])) {
        endDate = new Date(endParts[0], endParts[1] - 1, endParts[2]).getTime();
      }
    }

    const msPerDay = 1000 * 60 * 60 * 24;
    const diffDaysFromStart = Math.round((startDate - today) / msPerDay);

    if (diffDaysFromStart > 0) {
      // 오늘 이전 (출발 전)
      return { text: `D-${diffDaysFromStart}`, state: 'before' };
    } else if (diffDaysFromStart === 0) {
      // 시작일 당일
      return { text: '오늘 출발! D-Day', state: 'today' };
    } else {
      // 시작일 이후
      if (endDate && today > endDate) {
        return { text: '여행 완료', state: 'completed' };
      }
      const ongoingDay = Math.abs(diffDaysFromStart) + 1;
      return { text: `여행 ${ongoingDay}일차`, state: 'ongoing' };
    }
  }

  /**
   * @intent 시작일 기준 Day 번호에 해당하는 월/일/요일 텍스트 반환
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} startDateStr - YYYY-MM-DD
   * @param {number} dayNumber - 1-based Day 번호
   * @returns {string} 예: "(10.15 화)"
   */
  function formatDayDateLabel(startDateStr, dayNumber) {
    if (!startDateStr) return '';
    const parts = startDateStr.split('-').map(Number);
    if (parts.length < 3 || isNaN(parts[0])) return '';

    const dateObj = new Date(parts[0], parts[1] - 1, parts[2] + (dayNumber - 1));
    const m = dateObj.getMonth() + 1;
    const d = dateObj.getDate();
    const dow = DAY_OF_WEEK_NAMES[dateObj.getDay()];
    return `(${m}.${d} ${dow})`;
  }

  /**
   * @intent 상단 헤더 텍스트 및 D-Day 실시간 계산 뱃지, 일정 요약 칩 동기화 렌더링
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip
   */
  function renderHeader(trip) {
    const meta = trip.metadata || {};
    dom.tripTitle.textContent = meta.title || '나의 여행 일정';
    dom.tripPeriod.textContent = `${meta.startDate || '출발일 미정'} ~ ${meta.endDate || '도착일 미정'}`;

    // D-Day 실시간 계산 뱃지 동기화
    if (dom.tripDdayBadge) {
      const dday = calculateTripDday(meta.startDate, meta.endDate);
      if (dday) {
        dom.tripDdayBadge.textContent = dday.text;
        dom.tripDdayBadge.classList.remove('hidden');
      } else {
        dom.tripDdayBadge.classList.add('hidden');
      }
    }

    // 여행 일정 요약 칩 동기화
    if (dom.tripSummaryChip) {
      const itemCount = (trip.items || []).length;
      if (itemCount > 0) {
        dom.tripSummaryChip.textContent = `총 ${itemCount}개 일정`;
        dom.tripSummaryChip.classList.remove('hidden');
      } else {
        dom.tripSummaryChip.classList.add('hidden');
      }
    }
  }

  /**
   * @intent 일차(Day) 탭 바 렌더링 (실제 날짜 및 요일 감성 표기, 활성 그라디언트 테마 지원)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip
   * @param {number} selectedDay
   */
  function renderDayTabs(trip, selectedDay) {
    const meta = trip.metadata || {};
    const maxDays = Math.max(3, getMaxDays(trip.items));
    dom.daySelectorBar.innerHTML = '';

    // 전체 칩 (맨 앞)
    const isAllSelected = selectedDay === 'all' || selectedDay === 'ALL';
    const allChip = document.createElement('button');
    allChip.className = `day-chip chip-all${isAllSelected ? ' active' : ''}`;
    allChip.title = '전체 일정 및 모든 날짜 동선 한눈에 보기';
    allChip.innerHTML = `${getIcon('MAP', { size: 14 })} <span>전체</span>`;
    allChip.addEventListener('click', () => {
      store.setSelectedDay('all');
    });
    dom.daySelectorBar.appendChild(allChip);

    for (let d = 1; d <= maxDays; d++) {
      const chip = document.createElement('button');
      chip.className = `day-chip${!isAllSelected && Number(d) === Number(selectedDay) ? ' active' : ''}`;

      const dateLabel = formatDayDateLabel(meta.startDate, d);
      const text = dateLabel ? `Day ${d} ${dateLabel}` : `Day ${d}`;

      chip.innerHTML = `${getIcon('CALENDAR', { size: 14 })} <span>${text}</span>`;
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

    // 활성 Day 칩으로 부드러운 자동 센터링 스크롤 (일차가 많아져 가로 스크롤 영역을 벗어났을 때 자동 안착)
    setTimeout(() => {
      const activeChip = dom.daySelectorBar.querySelector('.day-chip.active');
      if (activeChip && typeof activeChip.scrollIntoView === 'function') {
        activeChip.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
      }
    }, 40);
  }

  /**
   * @intent 타임라인 카드 내 사진 마크업 렌더링 (단일 썸네일 및 2열/3열/2x2 그리드 레이아웃)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} item - 일정 아이템
   * @returns {string} 사진 HTML 마크업
   */
  function renderCardPhotosHtml(item) {
    const photos = (item.photos && item.photos.length > 0)
      ? item.photos
      : (item.photoDataUrl ? [{ id: item.photoId || 'photo-1', dataUrl: item.photoDataUrl }] : []);

    if (photos.length === 0) return '';

    if (photos.length === 1) {
      return `
        <img src="${escapeHtml(photos[0].dataUrl)}" class="card-thumbnail" alt="첨부 사진" 
             data-photo-url="${escapeHtml(photos[0].dataUrl)}" data-gallery-index="0" />
      `;
    }

    const count = photos.length;
    let gridClass = 'cols-4';
    if (count === 2) gridClass = 'cols-2';
    else if (count === 3) gridClass = 'cols-3';

    const displayPhotos = photos.slice(0, 4);
    const remainingCount = count - 4;

    return `
      <div class="card-photos-grid ${gridClass}">
        ${displayPhotos.map((p, idx) => {
          const isLastAndMore = idx === 3 && remainingCount > 0;
          return `
            <div class="card-photo-item" data-photo-url="${escapeHtml(p.dataUrl)}" data-gallery-index="${idx}">
              <img src="${escapeHtml(p.dataUrl)}" alt="사진 ${idx + 1}" />
              ${isLastAndMore ? `<div class="card-photo-more-badge">+${remainingCount}장</div>` : ''}
            </div>
          `;
        }).join('')}
      </div>
    `;
  }

  /**
   * @intent 일정 아이템의 카테고리 및 속성에 따른 타임라인 시간 뱃지 텍스트 서식화
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} item
   * @returns {string} 서식화된 시간 텍스트 (없으면 빈 문자열)
   */
  function formatItemTimeBadge(item) {
    if (!item) return '';
    if (item.category === 'FLIGHT') {
      const flightTime = item.time || (item.flightType === 'ARRIVAL' ? item.arrivalTime : item.departureTime);
      if (!flightTime) return '';
      return item.flightType === 'ARRIVAL' ? ('도착 ' + flightTime) : ('출발 ' + flightTime);
    }
    if (item.category === 'HOTEL') {
      if (item.time) return '체크인 ' + item.time;
      if (item.checkInTime) return '체크인 ' + item.checkInTime;
      return '';
    }
    return item.time || '';
  }

  /**
   * @intent 타임라인 패널 렌더링 - 시간순 자동 정렬, 스루라인(동선 연결선), 모던 트래블 카드, 정제된 미니멀 액션 바(지도/수정/삭제)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip
   * @param {number} selectedDay
   * @param {string|null} selectedItemId
   */
  function renderTimelinePanel(trip, selectedDay, selectedItemId) {
    const meta = trip.metadata || {};
    const isAllDays = selectedDay === 'all' || selectedDay === 'ALL';

    const itemsToRender = (trip.items || [])
      .filter((item) => (isAllDays ? true : Number(item.day) === Number(selectedDay)))
      .slice()
      .sort((a, b) => {
        if (isAllDays) {
          const dayA = Number(a.day) || 1;
          const dayB = Number(b.day) || 1;
          if (dayA !== dayB) return dayA - dayB;
        }
        const timeA = a.time || (a.category === 'FLIGHT' ? (a.flightType === 'ARRIVAL' ? a.arrivalTime : a.departureTime) : (a.category === 'HOTEL' ? a.checkInTime : '')) || '';
        const timeB = b.time || (b.category === 'FLIGHT' ? (b.flightType === 'ARRIVAL' ? b.arrivalTime : b.departureTime) : (b.category === 'HOTEL' ? b.checkInTime : '')) || '';
        if (timeA && timeB) {
          return timeA.localeCompare(timeB);
        }
        if (timeA && !timeB) return -1;
        if (!timeA && timeB) return 1;
        return 0;
      });

    const toolbarTitle = isAllDays
      ? `전체 여행 일정 (${itemsToRender.length}개)`
      : `Day ${selectedDay} 일정 (${itemsToRender.length}개)`;

    let html = `
      <div class="timeline-toolbar" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:14px;">
        <div style="font-weight:700; font-size:0.95rem; color:var(--text-main);">
          ${toolbarTitle}
        </div>
        <button id="btn-add-item-day" class="btn btn-primary btn-sm">
          ${getIcon('PLUS', { size: 14 })} <span>일정 추가</span>
        </button>
      </div>
    `;

    const addDefaultDay = isAllDays ? 1 : (Number(selectedDay) || 1);

    if (itemsToRender.length === 0) {
      const emptyMessage = isAllDays
        ? '등록된 여행 일정이 없습니다.'
        : `등록된 Day ${selectedDay} 일정이 없습니다.`;
      html += `
        <div class="empty-timeline-state">
          ${getIcon('ROUTE', { size: 40, color: 'var(--gray-400)' })}
          <div>${emptyMessage}</div>
          <button id="btn-empty-add-item" class="btn btn-outline btn-sm">
            ${getIcon('PLUS', { size: 14 })} <span>첫 일정 추가하기</span>
          </button>
        </div>
      `;
      dom.panelContentArea.innerHTML = html;
      document.getElementById('btn-add-item-day')?.addEventListener('click', () => openItemModal({ day: addDefaultDay }));
      document.getElementById('btn-empty-add-item')?.addEventListener('click', () => openItemModal({ day: addDefaultDay }));
      return;
    }

    // 일차별 일정 개수 집계 (전체 보기 모드용)
    const dayItemCounts = {};
    if (isAllDays) {
      itemsToRender.forEach((it) => {
        const d = Number(it.day) || 1;
        dayItemCounts[d] = (dayItemCounts[d] || 0) + 1;
      });
    }

    html += '<div class="timeline-flow-wrapper">';

    let currentRenderDay = null;
    let dayOrder = 0;

    itemsToRender.forEach((item, index) => {
      const itemDay = Number(item.day) || 1;
      const dayColor = getDayColor(itemDay);

      // 전체 보기 모드에서 Day 전환 시 구분 헤더 렌더링
      if (isAllDays && itemDay !== currentRenderDay) {
        currentRenderDay = itemDay;
        dayOrder = 0;
        const count = dayItemCounts[itemDay] || 0;
        html += `
          <div class="timeline-day-divider">
            <span class="day-divider-pill" style="background:${dayColor};">Day ${itemDay}</span>
            <span class="day-divider-date">${formatDayDateLabel(meta.startDate, itemDay)}</span>
            <span class="day-divider-count">${count}개 일정</span>
          </div>
        `;
      }

      dayOrder++;
      const order = isAllDays ? dayOrder : (index + 1);
      const cat = CATEGORIES[item.category] || { label: '기타', icon: 'NOTE', color: '#64748b' };
      const isActive = item.id === selectedItemId;
      const activeClass = isActive ? ' is-active' : '';
      const timeBadge = formatItemTimeBadge(item);
      const photos = (item.photos && item.photos.length > 0)
        ? item.photos
        : (item.photoDataUrl ? [{ id: item.photoId || 'photo-1', dataUrl: item.photoDataUrl }] : []);
      const photosCount = photos.length;

      html += `
        <div class="timeline-flow-item${activeClass}" data-id="${escapeHtml(item.id)}">
          <div class="timeline-flow-lane">
            <span class="card-order-marker" style="${isAllDays ? `border-color:${dayColor}; color:${dayColor};` : ''}">${order}</span>
            <div class="timeline-through-line"></div>
          </div>
          <div class="timeline-item-card${activeClass}" data-id="${escapeHtml(item.id)}">
            <div class="card-header-row">
              <div class="card-header-left">
                ${isAllDays ? `<span class="category-tag day-pill-tag" style="background:${dayColor}; color:#ffffff; font-weight:700;">Day ${itemDay}</span>` : ''}
                <span class="category-tag cat-${(item.category || '').toLowerCase()}">
                  ${getIcon(cat.icon, { size: 14 })} <span>${cat.label}</span>
                </span>
              </div>
              <div class="card-header-badges">
                ${timeBadge ? `
                  <div class="card-time-badge">
                    ${getIcon('CLOCK', { size: 13 })} <span>${escapeHtml(timeBadge)}</span>
                  </div>
                ` : ''}
                ${photosCount > 0 ? `
                  <div class="card-photos-badge">
                    ${getIcon('IMAGE', { size: 13 })} <span>사진 ${photosCount}장</span>
                  </div>
                ` : ''}
              </div>
            </div>

            <div class="card-title">${escapeHtml(item.title || '일정')}</div>

            ${item.address ? `
              <div class="card-location-tag">
                ${getIcon('MAP_PIN', { size: 12 })} <span>${escapeHtml(item.address)}</span>
              </div>
            ` : ''}

            <!-- 카테고리별 핵심 요약 그리드 -->
            ${renderItemCardDetails(item)}

            <!-- 사진 영역 (단일 또는 다중 그리드) -->
            ${renderCardPhotosHtml(item)}

            <div class="card-footer-row">
              <div class="card-cost-info">
                ${Number(item.cost) > 0 ? `
                  ${getIcon('MONEY', { size: 14, color: 'var(--accent-emerald)' })}
                  <span>${formatAmount(item.cost, 'KRW')}</span>
                ` : '<span class="card-cost-free">비용 없음</span>'}
              </div>
              <div class="card-actions">
                <button type="button" class="card-action-btn btn-view-map" data-id="${escapeHtml(item.id)}" title="지도에서 위치 보기">
                  ${getIcon('MAP', { size: 13 })} <span>지도</span>
                </button>
                <button type="button" class="card-action-btn btn-edit-item" data-id="${escapeHtml(item.id)}" title="수정">
                  ${getIcon('EDIT', { size: 13 })} <span>수정</span>
                </button>
                <button type="button" class="card-action-btn btn-delete-item danger" data-id="${escapeHtml(item.id)}" title="삭제">
                  ${getIcon('DELETE', { size: 13 })} <span>삭제</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      `;
    });

    html += '</div>';
    dom.panelContentArea.innerHTML = html;

    // 이벤트 바인딩
    document.getElementById('btn-add-item-day')?.addEventListener('click', () => openItemModal({ day: addDefaultDay }));

    // 카드 클릭 이벤트 (지도 이동 및 하이라이트)
    dom.panelContentArea.querySelectorAll('.timeline-item-card').forEach((card) => {
      card.addEventListener('click', (e) => {
        if (e.target.closest('.card-actions') || e.target.closest('.card-thumbnail') || e.target.closest('.card-photo-item')) return;
        const id = card.dataset.id;
        store.setSelectedItemId(id);
        const item = (trip.items || []).find((it) => it.id === id);
        if (item) mapManager.flyToItem(item);
      });
    });

    // 지도 보기 버튼 이벤트
    dom.panelContentArea.querySelectorAll('.btn-view-map').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.dataset.id;
        store.setSelectedItemId(id);
        const item = (trip.items || []).find((it) => it.id === id);
        if (item) mapManager.flyToItem(item);
      });
    });

    // 썸네일 및 그리드 사진 클릭 시 라이트박스 갤러리 오픈
    dom.panelContentArea.querySelectorAll('.timeline-item-card').forEach((card) => {
      const id = card.dataset.id;
      const item = (trip.items || []).find((it) => it.id === id);
      if (!item) return;

      const photos = (item.photos && item.photos.length > 0)
        ? item.photos
        : (item.photoDataUrl ? [{ id: item.photoId || 'photo-1', dataUrl: item.photoDataUrl }] : []);
      const galleryUrls = photos.map((p) => p.dataUrl);

      // 단일 썸네일
      const singleThumb = card.querySelector('.card-thumbnail');
      if (singleThumb) {
        singleThumb.addEventListener('click', (e) => {
          e.stopPropagation();
          openLightbox(singleThumb.dataset.photoUrl, galleryUrls, 0);
        });
      }

      // 다중 사진 그리드 아이템들
      card.querySelectorAll('.card-photo-item').forEach((photoItem) => {
        photoItem.addEventListener('click', (e) => {
          e.stopPropagation();
          const photoIdx = parseInt(photoItem.dataset.galleryIndex, 10) || 0;
          const url = photoItem.dataset.photoUrl || galleryUrls[photoIdx];
          openLightbox(url, galleryUrls, photoIdx);
        });
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
        const isArr = item.flightType === 'ARRIVAL';
        details.push({ label: '구분', val: isArr ? '도착편 (착륙)' : '출발편 (이륙)' });
        const airportVal = item.airport || (isArr ? item.arrivalAirport : item.departureAirport);
        if (airportVal) {
          details.push({ label: isArr ? '도착 공항' : '출발 공항', val: airportVal });
        } else if (item.departureAirport && item.arrivalAirport) {
          details.push({ label: '구간', val: `${item.departureAirport} -> ${item.arrivalAirport}` });
        }
        if (item.flightNo) details.push({ label: '편명', val: item.flightNo });
        if (item.seat) details.push({ label: '좌석', val: item.seat });
        if (item.terminalGate) details.push({ label: '터미널/게이트', val: item.terminalGate });
        if (item.bookingRef) details.push({ label: '예약번호', val: item.bookingRef });
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
   * @intent 여행 경비 대시보드 렌더링 - 대형 총 지출액 히어로 카드, 멀티 세그먼트 프로그레스 게이지, 공동 결제 안심 카드, 지출 상위 랭킹 TOP 5
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {object} trip
   */
  function renderExpensePanel(trip) {
    const meta = trip.metadata || {};
    const participants = meta.participants || [];
    const baseCurr = 'KRW';
    const rates = meta.customRates || {};

    const { summary } = calculateSettlements(participants, trip.items, baseCurr, rates);
    const perPerson = Math.round(summary.totalInBase / 2);

    const catMeta = {
      FLIGHT: { label: '항공권', icon: 'FLIGHT', key: 'flight' },
      HOTEL: { label: '숙소/호텔', icon: 'HOTEL', key: 'hotel' },
      DINING: { label: '식비/맛집', icon: 'DINING', key: 'dining' },
      ATTRACTION: { label: '관광/투어', icon: 'ATTRACTION', key: 'attraction' },
      TRANSIT: { label: '교통/이동', icon: 'TRANSIT', key: 'transit' },
      AIRPORT: { label: '공항/기타', icon: 'AIRPORT', key: 'airport' }
    };

    const catEntries = Object.entries(summary.byCategory || {})
      .filter(([_, amt]) => amt > 0)
      .sort((a, b) => b[1] - a[1]);

    // 지출 상위 아이템 정렬 (비용 내림차순 TOP 5)
    const paidItems = (trip.items || [])
      .filter((it) => Number(it.cost) > 0)
      .sort((a, b) => Number(b.cost) - Number(a.cost));
    const topCostItems = paidItems.slice(0, 5);

    let html = `
      <div class="expense-dashboard">
        <!-- 대형 총 지출액 히어로 카드 -->
        <div class="expense-hero-card">
          <div class="expense-hero-top">
            <span class="expense-hero-badge">${getIcon('SHIELD', { size: 13, color: '#e2e8f0' })} 부부 공동 경비</span>
            <span class="expense-hero-curr">통화: KRW 원</span>
          </div>
          <div class="expense-hero-amount-wrap">
            <span class="expense-hero-label">총 예상 지출액</span>
            <h2 class="expense-hero-amount">${formatAmount(summary.totalInBase, 'KRW')}</h2>
          </div>
          <div class="expense-hero-footer">
            <div class="expense-hero-chip">
              ${getIcon('USER', { size: 14, color: '#38bdf8' })}
              <span>1인당 ${formatAmount(perPerson, 'KRW')} (2인 기준)</span>
            </div>
            <span style="font-size:0.75rem; color:#94a3b8; margin-left:auto;">
              총 ${paidItems.length}건 결제
            </span>
          </div>
        </div>

        <!-- 카테고리별 지출 배분 멀티 세그먼트 게이지 카드 -->
        <div class="expense-gauge-card">
          <div class="expense-card-header">
            <div class="expense-card-title">
              ${getIcon('CALCULATOR', { size: 16, color: 'var(--primary-600)' })}
              <span>카테고리별 지출 배분</span>
            </div>
            <span class="expense-card-sub">${catEntries.length}개 카테고리</span>
          </div>
    `;

    if (catEntries.length === 0) {
      html += `
          <div style="font-size:0.85rem; color:var(--text-muted); padding:10px 0; text-align:center;">
            등록된 지출 내역이 없습니다.
          </div>
      `;
    } else {
      // 멀티 세그먼트 프로그레스 게이지 바
      html += '<div class="expense-multi-gauge-bar">';
      catEntries.forEach(([catKey, catAmt]) => {
        const pct = summary.totalInBase > 0 ? ((catAmt / summary.totalInBase) * 100).toFixed(1) : 0;
        const cInfo = catMeta[catKey] || { label: catKey };
        html += `<div class="expense-progress-segment seg-${catKey.toLowerCase()}" style="width: ${pct}%;" title="${cInfo.label}: ${pct}%"></div>`;
      });
      html += '</div>';

      // 카테고리별 범례 및 세부 내역
      html += '<div class="expense-cat-list">';
      catEntries.forEach(([catKey, catAmt]) => {
        const cInfo = catMeta[catKey] || { label: catKey, icon: 'INFO' };
        const percent = summary.totalInBase > 0 ? Math.round((catAmt / summary.totalInBase) * 100) : 0;
        html += `
          <div class="expense-cat-item">
            <div class="expense-cat-info">
              <span class="cat-dot dot-${catKey.toLowerCase()}"></span>
              <span class="expense-cat-name">${cInfo.label}</span>
              <span class="expense-cat-pct">${percent}%</span>
            </div>
            <span class="expense-cat-value">${formatAmount(catAmt, 'KRW')}</span>
          </div>
        `;
      });
      html += '</div>';
    }

    html += `
        </div>

        <!-- 공동 결제 완결 상태를 보여주는 감성 안심 카드 -->
        <div class="settlement-peace-card">
          <div class="peace-icon-wrap">
            ${getIcon('CHECK', { size: 20, color: 'var(--accent-emerald)' })}
          </div>
          <div class="peace-content">
            <div class="peace-title">정산 걱정 없는 편안한 여행</div>
            <div class="peace-desc">모든 지출은 부부 공동 경비로 자동 통합되어 별도의 개인간 송금 정산 없이 투명하고 편리하게 관리됩니다.</div>
          </div>
        </div>
    `;

    // 항목별 지출 랭킹 리스트 (TOP 5)
    if (topCostItems.length > 0) {
      html += `
        <div class="expense-ranking-card">
          <div class="expense-card-header">
            <div class="expense-card-title">
              ${getIcon('STAR', { size: 16, color: 'var(--accent-amber)' })}
              <span>지출 상위 랭킹 TOP 5</span>
            </div>
            <span class="expense-card-sub">주요 예산 항목</span>
          </div>
          <div class="expense-ranking-list">
      `;

      topCostItems.forEach((item, idx) => {
        const rank = idx + 1;
        const catInfo = CATEGORIES[item.category] || { label: '기타' };
        html += `
          <div class="ranking-item" data-id="${escapeHtml(item.id)}" style="cursor:pointer;" title="해당 일정으로 이동">
            <div class="ranking-rank rank-${rank}">${rank}</div>
            <div class="ranking-info">
              <div class="ranking-name">${escapeHtml(item.title || '일정')}</div>
              <div class="ranking-meta">${escapeHtml(catInfo.label)} | Day ${item.day}</div>
            </div>
            <div class="ranking-cost">${formatAmount(item.cost, 'KRW')}</div>
          </div>
        `;
      });

      html += `
          </div>
        </div>
      `;
    }

    html += '</div>';
    dom.panelContentArea.innerHTML = html;

    // 랭킹 항목 클릭 시 해당 일정 선택 및 지도 이동
    dom.panelContentArea.querySelectorAll('.ranking-item').forEach((row) => {
      row.addEventListener('click', () => {
        const id = row.dataset.id;
        if (!id) return;
        store.setSelectedItemId(id);
        const targetItem = (trip.items || []).find((it) => it.id === id);
        if (targetItem) {
          if (Number(targetItem.day) !== store.getState().selectedDay) {
            store.setSelectedDay(Number(targetItem.day));
          }
          mapManager.flyToItem(targetItem);
        }
      });
    });
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
   * @intent 라이트박스 갤러리 뷰 및 카운터/이전다음 버튼 가시성 동기화
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function updateLightboxDisplay() {
    if (!dom.lightboxImg || currentLightboxGallery.length === 0) return;
    const currentUrl = currentLightboxGallery[currentLightboxIndex];
    if (currentUrl) {
      dom.lightboxImg.src = currentUrl;
    }

    if (currentLightboxGallery.length > 1) {
      dom.btnLightboxPrev?.classList.remove('hidden');
      dom.btnLightboxNext?.classList.remove('hidden');
      if (dom.lightboxCounter) {
        dom.lightboxCounter.textContent = `${currentLightboxIndex + 1} / ${currentLightboxGallery.length}`;
        dom.lightboxCounter.classList.remove('hidden');
      }
    } else {
      dom.btnLightboxPrev?.classList.add('hidden');
      dom.btnLightboxNext?.classList.add('hidden');
      dom.lightboxCounter?.classList.add('hidden');
    }
  }

  /**
   * @intent 라이트박스 다음 사진 이동 (원형 순환)
   */
  function showNextLightboxImage() {
    if (currentLightboxGallery.length <= 1) return;
    currentLightboxIndex = (currentLightboxIndex + 1) % currentLightboxGallery.length;
    updateLightboxDisplay();
  }

  /**
   * @intent 라이트박스 이전 사진 이동 (원형 순환)
   */
  function showPrevLightboxImage() {
    if (currentLightboxGallery.length <= 1) return;
    currentLightboxIndex = (currentLightboxIndex - 1 + currentLightboxGallery.length) % currentLightboxGallery.length;
    updateLightboxDisplay();
  }

  /**
   * @intent 라이트박스 팝업 열기 (단일 사진 및 다중 갤러리/초기 인덱스 지원)
   * @param {string} imageUrl - 메인 사진 URL
   * @param {Array<string>} gallery - 전체 사진 URL 배열
   * @param {number} initialIndex - 초기 열람할 사진 인덱스
   */
  function openLightbox(imageUrl, gallery = [], initialIndex = 0) {
    if (Array.isArray(gallery) && gallery.length > 0) {
      currentLightboxGallery = [...gallery];
      currentLightboxIndex = Math.max(0, Math.min(initialIndex, currentLightboxGallery.length - 1));
    } else if (imageUrl) {
      currentLightboxGallery = [imageUrl];
      currentLightboxIndex = 0;
    } else {
      return;
    }

    updateLightboxDisplay();
    dom.lightboxOverlay.classList.add('is-open');
  }

  /**
   * @intent 라이트박스 팝업 닫기 및 갤러리 상태 리셋
   */
  function closeLightbox() {
    dom.lightboxOverlay.classList.remove('is-open');
    if (dom.lightboxImg) dom.lightboxImg.src = '';
    currentLightboxGallery = [];
    currentLightboxIndex = 0;
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

    const isEdit = Boolean(itemToEdit && itemToEdit.id);
    const modalTitle = isEdit ? '일정 수정하기' : '새 여행 일정 추가';

    const selDay = store.getState().selectedDay;
    const fallbackDay = (selDay === 'all' || selDay === 'ALL' ? 1 : selDay) || 1;

    const defaultData = (itemToEdit && itemToEdit.id) ? itemToEdit : Object.assign({
      day: fallbackDay,
      category: 'ATTRACTION',
      currency: trip.metadata.baseCurrency || 'KRW',
      payer: participants[0] || '공통'
    }, itemToEdit || {});

    if (defaultData.day === 'all' || defaultData.day === 'ALL' || !defaultData.day) {
      defaultData.day = 1;
    }

    const formHtml = formManager.renderFormHtml(defaultData, participants);
    openModal(modalTitle, formHtml);

    const modalForm = document.getElementById('item-editor-form');
    if (!modalForm) return;

    // 천 단위 콤마 실시간 포맷팅 헬퍼
    /**
     * @intent 인풋 필드에 실시간 천 단위 콤마 포맷팅 및 커서 위치 보정 리스너 바인딩
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {HTMLInputElement} inputEl
     */
    function attachCommaFormatter(inputEl) {
      if (!inputEl) return;
      inputEl.addEventListener('input', () => {
        const cursorPosition = inputEl.selectionEnd;
        const originalLength = inputEl.value.length;
        const digitsOnly = inputEl.value.replace(/[^\d]/g, '');
        if (!digitsOnly) {
          inputEl.value = '';
          return;
        }
        const formatted = Number(digitsOnly).toLocaleString('ko-KR');
        inputEl.value = formatted;
        // 콤마 추가에 따른 자연스러운 커서 위치 보정
        const newLength = formatted.length;
        const newCursorPos = Math.max(0, cursorPosition + (newLength - originalLength));
        inputEl.setSelectionRange(newCursorPos, newCursorPos);
      });
    }

    const costInput = document.getElementById('item-cost');
    attachCommaFormatter(costInput);

    const ticketCostInput = document.getElementById('item-ticket-cost');
    attachCommaFormatter(ticketCostInput);

    /**
     * @intent 비행기 카테고리 출발/도착 구분 토글 및 라벨/플레이스홀더 실시간 반응형 동기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    function setupFlightTypeListeners() {
      const selector = document.getElementById('flight-type-selector');
      if (!selector) return;
      const airportLabel = document.getElementById('flight-airport-label');
      const airportInput = document.getElementById('flight-airport-input');
      const timeLabel = document.getElementById('flight-time-label');
      const options = selector.querySelectorAll('.flight-type-option');
      const radios = selector.querySelectorAll('input[name="flightType"]');

      radios.forEach((radio) => {
        radio.addEventListener('change', () => {
          const val = radio.value;
          options.forEach((opt) => {
            const r = opt.querySelector('input[type="radio"]');
            if (r && r.value === val) {
              opt.classList.add('active');
            } else {
              opt.classList.remove('active');
            }
          });

          if (val === 'ARRIVAL') {
            if (airportLabel) airportLabel.textContent = '도착 공항 (IATA)';
            if (airportInput) airportInput.placeholder = '예: NRT, HND';
            if (timeLabel) timeLabel.textContent = '도착 시각 *';
          } else {
            if (airportLabel) airportLabel.textContent = '출발 공항 (IATA)';
            if (airportInput) airportInput.placeholder = '예: ICN, GMP';
            if (timeLabel) timeLabel.textContent = '출발 시각 *';
          }
        });
      });
    }

    setupFlightTypeListeners();

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
        // 동적 필드 재렌더링 시 입장료 콤마 포맷터 바인딩
        attachCommaFormatter(document.getElementById('item-ticket-cost'));
        // 비행기 폼인 경우 출발/도착 토글러 리스너 바인딩
        setupFlightTypeListeners();
      });
    });

    // 위치 및 구글맵 좌표 처리 (#coord-paste-input, #item-lat, #item-lng, #btn-clear-location)
    // 위치 및 구글맵 장소 검색/좌표 처리 (#place-search-input, #coord-paste-input, #item-lat, #item-lng, #btn-clear-location)
    /**
     * @intent 구글맵 장소 실시간 검색, 좌표 자동 파싱, 위도/경도 직접 입력 양방향 동기화 및 핀 연동
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    const placeSearchInput = document.getElementById('place-search-input');
    const btnClearPlaceSearch = document.getElementById('btn-clear-place-search');
    const placeSearchDropdown = document.getElementById('place-search-dropdown');
    const coordPasteInput = document.getElementById('coord-paste-input');
    const btnApplyCoordPaste = document.getElementById('btn-apply-coord-paste');
    const itemLatInput = document.getElementById('item-lat');
    const itemLngInput = document.getElementById('item-lng');
    const btnClearLocation = document.getElementById('btn-clear-location');
    const pickOnMapBtn = document.getElementById('btn-pick-on-map');

    let lastAutoParsedText = '';
    let placeSearchDebounceTimer = null;
    let currentSearchResults = [];

    // 구글맵 장소 실시간 검색 실행 함수
    function performPlaceSearch(query) {
      const q = (query || '').trim();
      if (!q || q.length < 2) {
        if (placeSearchDropdown) {
          placeSearchDropdown.innerHTML = '';
          placeSearchDropdown.classList.add('hidden');
        }
        return;
      }

      TripGeocoder.searchPlaces(q, 6).then((results) => {
        currentSearchResults = results || [];
        if (!placeSearchDropdown) return;

        if (currentSearchResults.length === 0) {
          placeSearchDropdown.innerHTML = `
            <div style="padding: 10px 12px; font-size: 0.8rem; color: var(--text-muted, #64748b); text-align: center;">
              검색 결과가 없습니다.
            </div>
          `;
          placeSearchDropdown.classList.remove('hidden');
          return;
        }

        placeSearchDropdown.innerHTML = currentSearchResults.map((item, idx) => {
          const mainText = item.name || item.displayName || '';
          const subText = item.secondaryText || (item.displayName && item.displayName !== item.name ? item.displayName : '');
          return `
            <div class="place-search-item" data-index="${idx}">
              <span class="place-search-icon">
                ${typeof Icons !== 'undefined' ? Icons.getIcon('LOCATION_TARGET', { size: 14 }) : ''}
              </span>
              <div class="place-search-texts">
                <span class="place-search-main">${escapeHtml(mainText)}</span>
                ${subText ? `<span class="place-search-sub">${escapeHtml(subText)}</span>` : ''}
              </div>
            </div>
          `;
        }).join('');

        placeSearchDropdown.classList.remove('hidden');
      }).catch((err) => {
        console.warn('Place search error:', err);
      });
    }

    if (placeSearchInput) {
      placeSearchInput.addEventListener('input', (e) => {
        const val = e.target.value;
        if (btnClearPlaceSearch) {
          btnClearPlaceSearch.classList.toggle('hidden', !val.trim());
        }
        clearTimeout(placeSearchDebounceTimer);
        placeSearchDebounceTimer = setTimeout(() => {
          performPlaceSearch(val);
        }, 250);
      });

      placeSearchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          clearTimeout(placeSearchDebounceTimer);
          performPlaceSearch(placeSearchInput.value);
        }
      });
    }

    if (btnClearPlaceSearch) {
      btnClearPlaceSearch.addEventListener('click', () => {
        if (placeSearchInput) {
          placeSearchInput.value = '';
          placeSearchInput.focus();
        }
        btnClearPlaceSearch.classList.add('hidden');
        if (placeSearchDropdown) {
          placeSearchDropdown.innerHTML = '';
          placeSearchDropdown.classList.add('hidden');
        }
      });
    }

    if (placeSearchDropdown) {
      placeSearchDropdown.addEventListener('click', async (e) => {
        const itemEl = e.target.closest('.place-search-item');
        if (!itemEl) return;
        const idx = Number(itemEl.dataset.index);
        const item = currentSearchResults[idx];
        if (!item) return;

        try {
          let lat = item.lat;
          let lng = item.lng;
          let name = item.name || item.displayName;

          // Google Places ID 기반 좌표 조회
          if ((lat == null || lng == null) && item.placeId && typeof TripGeocoder.getPlaceCoordinates === 'function') {
            const coords = await TripGeocoder.getPlaceCoordinates(item.placeId);
            if (coords) {
              lat = coords.lat;
              lng = coords.lng;
              if (coords.name) name = coords.name;
            }
          }

          if (lat != null && lng != null && !isNaN(lat) && !isNaN(lng)) {
            lat = Number(lat);
            lng = Number(lng);

            if (itemLatInput) itemLatInput.value = lat;
            if (itemLngInput) itemLngInput.value = lng;
            if (coordPasteInput) {
              coordPasteInput.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
              lastAutoParsedText = coordPasteInput.value;
            }

            const itemTitleInput = document.getElementById('item-title');
            if (itemTitleInput && !itemTitleInput.value.trim()) {
              itemTitleInput.value = name;
            }

            if (placeSearchInput) {
              placeSearchInput.value = name;
            }
            if (btnClearPlaceSearch) {
              btnClearPlaceSearch.classList.remove('hidden');
            }
            if (btnClearLocation) {
              btnClearLocation.classList.remove('hidden');
            }

            placeSearchDropdown.innerHTML = '';
            placeSearchDropdown.classList.add('hidden');

            mapManager.setPinDropPreview(lat, lng);
            if (mapManager.map && mapManager.engine === 'google') {
              mapManager.map.panTo({ lat, lng });
              mapManager.map.setZoom(15);
            } else if (mapManager.map && mapManager.engine === 'leaflet') {
              mapManager.map.panTo([lat, lng]);
            }

            showToast(`구글맵에서 장소와 좌표를 가져왔습니다: ${name}`);
          } else {
            showToast('해당 장소의 좌표 정보를 가져올 수 없습니다.');
          }
        } catch (err) {
          console.warn('Place selection error:', err);
          showToast('장소 좌표 조회 중 오류가 발생했습니다.');
        }
      });
    }

    // 모달 내 드롭다운 외부 클릭 시 닫기
    document.addEventListener('click', (e) => {
      if (
        placeSearchDropdown &&
        !placeSearchDropdown.contains(e.target) &&
        e.target !== placeSearchInput &&
        e.target !== btnClearPlaceSearch
      ) {
        placeSearchDropdown.classList.add('hidden');
      }
    });

    function tryAutoParseCoord(text) {
      if (!text || text.trim() === lastAutoParsedText) return;
      const parsed = parseCoordinates(text);
      if (parsed) {
        lastAutoParsedText = text.trim();
        if (itemLatInput) itemLatInput.value = parsed.lat;
        if (itemLngInput) itemLngInput.value = parsed.lng;
        if (btnClearLocation) btnClearLocation.classList.remove('hidden');
        showToast(`구글맵 좌표가 자동으로 인식되었습니다: ${parsed.lat.toFixed(4)}, ${parsed.lng.toFixed(4)}`);
      }
    }

    if (coordPasteInput) {
      // 붙여넣기 이벤트
      coordPasteInput.addEventListener('paste', () => {
        setTimeout(() => {
          tryAutoParseCoord(coordPasteInput.value);
        }, 0);
      });

      // 입력 이벤트
      coordPasteInput.addEventListener('input', () => {
        tryAutoParseCoord(coordPasteInput.value);
      });
    }

    // 좌표 즉시 적용 버튼 (#btn-apply-coord-paste)
    btnApplyCoordPaste?.addEventListener('click', () => {
      const val = coordPasteInput ? coordPasteInput.value.trim() : '';
      const parsed = parseCoordinates(val);
      if (parsed) {
        lastAutoParsedText = val;
        if (itemLatInput) itemLatInput.value = parsed.lat;
        if (itemLngInput) itemLngInput.value = parsed.lng;
        if (btnClearLocation) btnClearLocation.classList.remove('hidden');
        showToast(`구글맵 좌표가 자동으로 인식되었습니다: ${parsed.lat.toFixed(4)}, ${parsed.lng.toFixed(4)}`);
      } else {
        showToast('올바른 좌표 형식(예: 35.6585, 139.7454)을 입력해 주세요.');
      }
    });

    // 위도(#item-lat) 및 경도(#item-lng) 직접 입력 (input 이벤트)
    function handleDirectCoordInput() {
      const latVal = itemLatInput ? itemLatInput.value.trim() : '';
      const lngVal = itemLngInput ? itemLngInput.value.trim() : '';
      const latNum = parseFloat(latVal);
      const lngNum = parseFloat(lngVal);
      const hasValidNumbers = latVal !== '' && lngVal !== '' && !isNaN(latNum) && !isNaN(lngNum);

      if (hasValidNumbers) {
        if (btnClearLocation) btnClearLocation.classList.remove('hidden');
        if (coordPasteInput && document.activeElement !== coordPasteInput) {
          coordPasteInput.value = `${itemLatInput.value}, ${itemLngInput.value}`;
          lastAutoParsedText = coordPasteInput.value;
        }
      } else if (!latVal && !lngVal) {
        if (btnClearLocation) btnClearLocation.classList.add('hidden');
        if (coordPasteInput && document.activeElement !== coordPasteInput) {
          coordPasteInput.value = '';
          lastAutoParsedText = '';
        }
      }
    }
    itemLatInput?.addEventListener('input', handleDirectCoordInput);
    itemLngInput?.addEventListener('input', handleDirectCoordInput);

    // 좌표 초기화 버튼 (#btn-clear-location)
    btnClearLocation?.addEventListener('click', () => {
      if (itemLatInput) itemLatInput.value = '';
      if (itemLngInput) itemLngInput.value = '';
      if (coordPasteInput) coordPasteInput.value = '';
      lastAutoParsedText = '';
      if (placeSearchInput) placeSearchInput.value = '';
      if (btnClearPlaceSearch) btnClearPlaceSearch.classList.add('hidden');
      if (placeSearchDropdown) {
        placeSearchDropdown.innerHTML = '';
        placeSearchDropdown.classList.add('hidden');
      }

      btnClearLocation.classList.add('hidden');
      activePickerCoord = null;
      mapManager.setPinDropMode(false);
      showToast('좌표가 초기화되었습니다.');
    });

    // 지도 핀 드롭 버튼 클릭 (지도 핀 위치 선택 모드 진입)
    pickOnMapBtn?.addEventListener('click', () => {
      dom.modalOverlay.classList.add('picker-mode-active');
      previousSheetStateBeforePicker = currentSheetState;
      if (window.innerWidth <= 900) {
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

    // 사진 첨부 및 다중 사진 등록/삭제 관리
    const photoTriggerBtn = document.getElementById('btn-trigger-photo');
    const photoInput = document.getElementById('item-photo-input');
    const photoPreviewSection = document.getElementById('photo-preview-section');
    const photoPreviewCount = document.getElementById('photo-preview-count');
    const photosPreviewGrid = document.getElementById('photos-preview-grid');
    const clearAllPhotosBtn = document.getElementById('btn-clear-all-photos');

    function updateModalPhotoPreview() {
      if (!photoPreviewSection || !photoPreviewCount || !photosPreviewGrid) return;
      const count = formManager.uploadedPhotos.length;
      if (count > 0) {
        photoPreviewCount.textContent = `첨부된 사진 (${count}장)`;
        photosPreviewGrid.innerHTML = formManager.renderPhotosPreviewGridHtml();
        photoPreviewSection.classList.remove('hidden');
      } else {
        photoPreviewSection.classList.add('hidden');
        photosPreviewGrid.innerHTML = '';
      }
    }

    photoTriggerBtn?.addEventListener('click', () => photoInput.click());

    photoInput?.addEventListener('change', async (e) => {
      const files = Array.from(e.target.files || []);
      if (files.length === 0) return;

      try {
        showToast(`${files.length}장의 사진 압축 및 처리 중...`);
        const mgr = (typeof TripSupabase !== 'undefined' ? TripSupabase.supabaseManager : null);
        const isCloudReady = mgr && typeof mgr.isConfigured === 'function' && mgr.isConfigured();

        for (let i = 0; i < files.length; i++) {
          const file = files[i];
          const { dataUrl } = await resizeImage(file, 1200, 0.75);
          const photoId = 'photo-' + Date.now() + '-' + i;
          let finalPhotoUrl = dataUrl;

          if (isCloudReady) {
            try {
              const publicUrl = await mgr.uploadPhoto(dataUrl, file.name);
              if (publicUrl) {
                finalPhotoUrl = publicUrl;
              }
            } catch (cloudErr) {
              console.warn('Supabase photo upload fallback to local storage:', cloudErr);
            }
          }

          await savePhoto(photoId, finalPhotoUrl, file.name);
          formManager.uploadedPhotos.push({
            id: photoId,
            dataUrl: finalPhotoUrl,
            filename: file.name
          });
        }
        updateModalPhotoPreview();
        photoInput.value = '';
        showToast(`${files.length}장의 사진이 안전하게 추가되었습니다.`);
      } catch (err) {
        showToast('사진 처리 실패: ' + err.message);
      }
    });

    // 개별 사진 삭제 (이벤트 위임)
    photosPreviewGrid?.addEventListener('click', (e) => {
      const removeBtn = e.target.closest('.btn-remove-single-photo');
      if (!removeBtn) return;
      e.stopPropagation();
      const idx = parseInt(removeBtn.dataset.index, 10);
      if (!isNaN(idx) && idx >= 0 && idx < formManager.uploadedPhotos.length) {
        formManager.uploadedPhotos.splice(idx, 1);
        updateModalPhotoPreview();
      }
    });

    // 전체 삭제 리스너
    clearAllPhotosBtn?.addEventListener('click', (e) => {
      e.stopPropagation();
      formManager.uploadedPhotos = [];
      updateModalPhotoPreview();
      if (photoInput) photoInput.value = '';
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
   * @intent 여행 메타데이터 편집 모달 열기 (순수 여행 정보만 편집하도록 구글맵 API키 설정 섹션 완전 제거)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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

      store.updateMetadata({
        title,
        startDate,
        endDate,
        participants: ['신랑', '신부'],
        baseCurrency
      });

      showToast('여행 기본 정보가 수정되었습니다.');
      closeModal();
    });
  }

  /**
   * @intent 여행 정보 및 설정 모달 오픈 별칭 함수 (openTripMetaModal 위임)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function openTripSettingsModal() {
    openTripMetaModal();
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
          <div class="trip-manager-toolbar" style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;">
            <span class="trip-manager-count">총 ${trips.length}개의 여행 계획이 보관되어 있습니다.</span>
            <div style="display:flex; align-items:center; gap:8px;">
              <button type="button" id="btn-clear-current-trip" class="btn btn-outline btn-sm" style="color:var(--danger, #ef4444); border-color:var(--danger, #ef4444);" title="현재 활성 여행의 모든 일정을 비웁니다">
                ${getIcon('DELETE', { size: 14 })}
                <span>현재 일정 비우기</span>
              </button>
              <button type="button" id="btn-open-create-trip" class="btn-create-trip">
                ${getIcon('PLUS', { size: 16 })}
                <span>새 여행 계획 만들기</span>
              </button>
            </div>
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

      // 현재 활성 일정 전체 비우기 버튼 이벤트
      document.getElementById('btn-clear-current-trip')?.addEventListener('click', () => {
        const curTrip = store.getCurrentTrip();
        const curTitle = (curTrip && curTrip.metadata && curTrip.metadata.title) || '현재 여행';
        const itemCount = (curTrip && Array.isArray(curTrip.items)) ? curTrip.items.length : 0;
        if (itemCount === 0) {
          showToast('비울 일정이 없습니다. 이미 빈 상태입니다.');
          return;
        }
        if (confirm(`'${curTitle}'의 모든 일정(${itemCount}개)을 완전히 삭제하시겠습니까?\n삭제 후에는 복구할 수 없습니다.`)) {
          store.clearCurrentTripItems();
          showToast('모든 일정이 깨끗하게 초기화되었습니다.');
          openTripManagerModal('list');
        }
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
   * @intent 헤더 드롭다운 메뉴 닫기 유틸리티
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function closeHeaderMenu() {
    const menu = document.getElementById('header-dropdown-menu') || dom.headerDropdownMenu;
    const btn = document.getElementById('btn-header-menu') || dom.btnHeaderMenu;
    if (menu) menu.classList.add('hidden');
    if (btn) btn.setAttribute('aria-expanded', 'false');
  }

  /**
   * @intent 헤더 드롭다운 메뉴 열림/닫힘 토글 유틸리티
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function toggleHeaderMenu() {
    const menu = document.getElementById('header-dropdown-menu') || dom.headerDropdownMenu;
    const btn = document.getElementById('btn-header-menu') || dom.btnHeaderMenu;
    if (!menu) return;
    const isHidden = menu.classList.contains('hidden');
    if (isHidden) {
      menu.classList.remove('hidden');
      if (btn) btn.setAttribute('aria-expanded', 'true');
    } else {
      menu.classList.add('hidden');
      if (btn) btn.setAttribute('aria-expanded', 'false');
    }
  }

  /**
   * @intent 클라우드 실시간 자동 동기화 배지 UI 갱신 (Strict No-Emoji 원칙 준수)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {'idle'|'syncing'|'synced'|'error'} state 
   * @param {string} [customMessage] 
   */
  function updateCloudBadgeUI(state, customMessage) {
    let labelText = customMessage || '';
    if (!labelText) {
      if (state === 'syncing') labelText = '동기화 중...';
      else if (state === 'synced') labelText = '실시간 자동 저장 중';
      else if (state === 'error') labelText = '로컬 보관 모드';
      else labelText = '클라우드 대기';
    }

    // 기존 호환용 배지 존재 시 갱신
    const badge = dom.btnOpenCloudSync || document.getElementById('btn-open-cloud-sync');
    const textEl = dom.cloudSyncBadgeText || document.getElementById('cloud-sync-badge-text');
    if (badge) {
      badge.classList.remove('syncing', 'synced', 'error', 'idle');
      badge.classList.add(state || 'synced');
      if (textEl) textEl.textContent = labelText;
      badge.setAttribute('title', `Supabase 클라우드: ${labelText}`);
    }
  }

  // 동의어 별칭 함수 매핑
  const updateCloudSyncIndicator = updateCloudBadgeUI;

  /**
   * @intent 앱 구동 시 백그라운드로 클라우드 데이터 확인 및 자동 복원/초기 백업 동기화
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  async function initCloudAutoSync() {
    const mgr = (typeof TripSupabase !== 'undefined' ? TripSupabase.supabaseManager : null);
    if (!mgr) return;

    // 동기화 상태 리스너 등록하여 헤더 배지와 자동 연동
    mgr.onSyncStateChange(({ state, message }) => {
      updateCloudBadgeUI(state, message);
    });

    try {
      updateCloudBadgeUI('syncing', '동기화 확인 중...');
      const result = await mgr.autoFetchAndRestore(store);
      if (result.action === 'imported') {
        showToast(`클라우드에서 ${result.count}개의 여행 계획을 자동으로 불러왔습니다.`);
      } else if (result.action === 'seeded') {
        showToast('현재 여행 계획이 클라우드에 안전하게 자동 백업되었습니다.');
      }
    } catch (err) {
      console.warn('initCloudAutoSync background error:', err);
      updateCloudBadgeUI('error', '로컬 보관 모드');
    }
  }

  /**
   * @intent Google Maps API 키 설정 모달 (기본 내장 키 자동 동작 + 사용자 커스텀 키 등록 및 변경 지원)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function openGoogleMapsConfigModal() {
    const savedKey = (localStorage.getItem('mytriplog_gmaps_api_key') || '').trim();
    const hasCustomKey = Boolean(savedKey);

    const bodyHtml = `
      <form id="form-maps-config" class="editor-form">
        <div class="cloud-sync-info-box" style="margin-bottom:14px; background:var(--primary-50, #eff6ff); border-color:var(--primary-200, #bfdbfe);">
          <div class="cloud-info-icon" style="color:var(--primary-600, #2563eb);">
            ${typeof Icons !== 'undefined' ? Icons.getIcon('MAP', { size: 20 }) : ''}
          </div>
          <div class="cloud-info-text">
            <strong style="color:var(--text-main, #0f172a);">Google Maps 및 Places 실시간 검색 연동</strong>
            <p style="margin:4px 0 0 0; font-size:0.78rem; color:var(--text-muted, #64748b);">
              기본 제공 API 키가 내장되어 있어 별도 설정 없이도 Google Maps 렌더링과 Places 장소 실시간 검색이 즉시 동작합니다.
              본인 전용 Google Cloud API 키를 사용하시려면 아래에 입력해 주십시오.
            </p>
          </div>
        </div>

        <div class="form-group">
          <label class="form-label" for="input-gmaps-custom-key">Google Maps API 키</label>
          <input type="text" id="input-gmaps-custom-key" class="form-control" 
                 placeholder="AIzaSy... (미입력 시 기본 내장 키로 동작)" 
                 value="${escapeHtml(savedKey)}" autocomplete="off" />
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <span style="font-size:0.75rem; color:${hasCustomKey ? 'var(--primary-600, #2563eb)' : 'var(--text-muted, #64748b)'};">
              현재 상태: ${hasCustomKey ? '사용자 커스텀 키 적용 중' : '기본 내장 키 자동 동작 중'}
            </span>
            ${hasCustomKey ? `
              <button type="button" id="btn-reset-gmaps-key" class="btn btn-outline btn-sm" style="font-size:0.75rem; padding:2px 8px;">
                기본 키로 복원
              </button>
            ` : ''}
          </div>
        </div>

        <div class="modal-form-actions">
          <button type="button" id="btn-maps-config-cancel" class="btn btn-secondary">취소</button>
          <button type="submit" class="btn btn-primary">
            ${typeof Icons !== 'undefined' ? Icons.getIcon('CHECK', { size: 16 }) : ''}
            <span>저장 및 적용</span>
          </button>
        </div>
      </form>
    `;

    openModal('Google Maps 키 설정', bodyHtml);

    document.getElementById('btn-maps-config-cancel')?.addEventListener('click', closeModal);

    document.getElementById('btn-reset-gmaps-key')?.addEventListener('click', async () => {
      TripMap.saveGoogleApiKey('');
      showToast('기본 내장 Google Maps 키로 복원되었습니다.');
      closeModal();
      await mapManager.updateApiKey(TripMap.DEFAULT_MAPS_KEY);
    });

    document.getElementById('form-maps-config')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = document.getElementById('input-gmaps-custom-key');
      const newKey = (input ? input.value : '').trim();

      TripMap.saveGoogleApiKey(newKey);
      const activeKey = newKey || TripMap.DEFAULT_MAPS_KEY;

      showToast('Google Maps 설정을 적용하는 중입니다...');
      closeModal();

      const success = await mapManager.updateApiKey(activeKey);
      if (success) {
        showToast(newKey ? 'Google Maps 커스텀 키가 적용되었습니다.' : '기본 내장 Google Maps 키로 동작합니다.');
      } else {
        showToast('Google Maps 적용에 실패하여 Leaflet으로 동작합니다.');
      }
    });
  }

  /**
   * @intent Supabase 클라우드 PostgreSQL DB 및 스토리지 연동 상태 모달 (수동 입력 필드 제거 및 내장 클라우드 자동 관리)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  async function openCloudSyncModal() {
    const mgr = (typeof TripSupabase !== 'undefined' ? TripSupabase.supabaseManager : null);
    if (!mgr) {
      showToast('Supabase 연동 모듈을 불러올 수 없습니다.');
      return;
    }

    const config = mgr.getConfig();
    const isConfigured = mgr.isConfigured();
    const initialStatusState = {
      status: isConfigured ? 'connected' : 'unconfigured',
      message: isConfigured ? 'Supabase 클라우드 실시간 자동 연동 중' : '클라우드 연동 준비 중'
    };

    const sqlScript = mgr.getSetupSqlScript();
    const modalHtml = formManager.renderCloudSyncModalHtml(config, initialStatusState, sqlScript);
    openModal('Supabase 클라우드 실시간 동기화', modalHtml);

    const updateStatusBadge = (status, text) => {
      const badge = document.getElementById('cloud-status-badge');
      if (!badge) return;
      badge.className = `cloud-status-badge status-${status}`;
      const textSpan = badge.querySelector('.status-indicator-text');
      if (textSpan) textSpan.textContent = text;
    };

    // 설정 상태 백그라운드 검증
    if (isConfigured) {
      mgr.testConnection().then((res) => {
        if (res.ok) {
          updateStatusBadge('connected', 'Supabase 클라우드 실시간 자동 연동 중');
        } else {
          updateStatusBadge('error', '클라우드 일시 지연: ' + (res.error || '접근 불가'));
        }
      }).catch((err) => {
        updateStatusBadge('error', '클라우드 일시 지연: ' + err.message);
      });
    }

    // 1. 로컬 데이터를 클라우드로 즉시 일괄 업로드
    document.getElementById('btn-cloud-upload-all')?.addEventListener('click', async () => {
      try {
        showToast('로컬 여행 계획을 클라우드로 업로드 중...');
        const count = await store.syncAllToCloud();
        showToast(`${count}개의 여행 계획이 Supabase 클라우드로 안전하게 업로드되었습니다.`);
      } catch (err) {
        showToast('클라우드 업로드 실패: ' + err.message);
      }
    });

    // 2. 클라우드에서 최신 데이터 가져오기 (복원)
    document.getElementById('btn-cloud-import')?.addEventListener('click', async () => {
      if (!confirm('Supabase 클라우드에 저장된 여행 데이터를 로컬로 가져와 복원하시겠습니까?')) {
        return;
      }
      try {
        showToast('클라우드에서 데이터 조회 중...');
        const res = await store.importFromCloud();
        if (res.count === 0) {
          showToast('클라우드에 저장된 여행 계획이 없습니다.');
        } else {
          showToast(`클라우드에서 ${res.count}개의 여행 계획을 성공적으로 복원했습니다.`);
          closeModal();
        }
      } catch (err) {
        showToast('데이터 복원 실패: ' + err.message);
      }
    });

    // 3. SQL 설정 스크립트 클립보드 복사
    const copySqlBtn = document.getElementById('btn-copy-setup-sql') || document.querySelector('.btn-copy-sql');
    copySqlBtn?.addEventListener('click', async () => {
      const codeTarget = document.getElementById('sql-code-target');
      const textToCopy = codeTarget ? codeTarget.textContent : mgr.getSetupSqlScript();
      const success = await copyToClipboard(textToCopy);
      if (success) {
        showToast('SQL 스크립트가 복사되었습니다. Supabase 대시보드 SQL Editor에 붙여넣어 실행하세요.');
      } else {
        showToast('클립보드 복사에 실패했습니다. 텍스트를 직접 복사해 주세요.');
      }
    });
  }

  /**
   * 앱 초기화 및 이벤트 리스너 바인딩
   */
  function initApp() {
    // 0. 레거시 더미 데이터 감지 시 클린 슬레이트(Clean Slate) 정제 및 강제 빈 상태 동기화
    const curTrip = store.getCurrentTrip();
    if (curTrip) {
      const isLegacyDummy = curTrip.metadata && (
        curTrip.metadata.id === 'trip-honeymoon-2026' ||
        curTrip.metadata.title === '우리의 로맨틱 신혼여행' ||
        curTrip.metadata.title === '도쿄 3박 4일 감성 힐링 여행'
      );
      const hasDummyItems = Array.isArray(curTrip.items) && curTrip.items.some((it) =>
        it && (
          (typeof it.id === 'string' && (it.id.startsWith('item-00') || it.id === 'item-001')) ||
          (typeof it.title === 'string' && (it.title.includes('에어서울 RS701') || it.title.includes('나리타 국제공항')))
        )
      );

      if (isLegacyDummy || hasDummyItems) {
        if (isLegacyDummy) {
          store.updateMetadata({
            id: 'trip-my-first-trip',
            title: '나의 여행 계획',
            startDate: '',
            endDate: ''
          });
        }
        store.clearCurrentTripItems();
      }
    }

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
        const coordPasteInput = document.getElementById('coord-paste-input');
        const clearBtn = document.getElementById('btn-clear-location');

        if (latInput && lngInput) {
          latInput.value = lat;
          lngInput.value = lng;
          latInput.dispatchEvent(new Event('input', { bubbles: true }));
          lngInput.dispatchEvent(new Event('input', { bubbles: true }));

          if (coordPasteInput) {
            coordPasteInput.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
          }
          if (clearBtn) clearBtn.classList.remove('hidden');

          const statusBadge = document.getElementById('location-status-badge');
          const badgeText = document.getElementById('location-badge-text');
          const pickBtn = document.getElementById('btn-pick-on-map');

          if (statusBadge) statusBadge.classList.add('has-location');
          if (badgeText) badgeText.textContent = `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
          const pickBtnSpan = pickBtn?.querySelector('span');
          if (pickBtnSpan) pickBtnSpan.textContent = '위치 변경';
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
      const coordPasteInput = document.getElementById('coord-paste-input');
      const searchInput = document.getElementById('place-search-input');
      const titleInput = document.getElementById('item-title');
      const clearBtn = document.getElementById('btn-clear-location');

      if (latInput) {
        latInput.value = lat;
        latInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (lngInput) {
        lngInput.value = lng;
        lngInput.dispatchEvent(new Event('input', { bubbles: true }));
      }
      if (coordPasteInput) {
        coordPasteInput.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
      }
      if (clearBtn) {
        clearBtn.classList.remove('hidden');
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

    // 10. 모달 및 라이트박스 닫기/갤러리 내비게이션 이벤트
    dom.modalCloseBtn?.addEventListener('click', closeModal);
    dom.modalOverlay?.addEventListener('click', (e) => {
      if (e.target === dom.modalOverlay) closeModal();
    });
    dom.lightboxCloseBtn?.addEventListener('click', closeLightbox);
    dom.lightboxOverlay?.addEventListener('click', (e) => {
      if (e.target === dom.lightboxOverlay) closeLightbox();
    });
    dom.btnLightboxPrev?.addEventListener('click', (e) => {
      e.stopPropagation();
      showPrevLightboxImage();
    });
    dom.btnLightboxNext?.addEventListener('click', (e) => {
      e.stopPropagation();
      showNextLightboxImage();
    });

    // Esc 및 좌/우 화살표 키 이벤트
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal();
        closeLightbox();
      } else if (dom.lightboxOverlay && dom.lightboxOverlay.classList.contains('is-open')) {
        if (e.key === 'ArrowLeft') {
          e.preventDefault();
          showPrevLightboxImage();
        } else if (e.key === 'ArrowRight') {
          e.preventDefault();
          showNextLightboxImage();
        }
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

    // 13. 상단 헤더 액션 및 더보기 드롭다운 메뉴 이벤트 바인딩
    const btnHeaderMenu = document.getElementById('btn-header-menu') || dom.btnHeaderMenu;
    const headerDropdownMenu = document.getElementById('header-dropdown-menu') || dom.headerDropdownMenu;

    // 메뉴 토글 버튼 클릭 (이벤트 버블링 차단하여 즉시 닫히지 않도록 함)
    btnHeaderMenu?.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleHeaderMenu();
    });

    // 외부 클릭 시 드롭다운 닫기 (Click outside to close)
    document.addEventListener('click', (e) => {
      const menu = document.getElementById('header-dropdown-menu') || dom.headerDropdownMenu;
      const btn = document.getElementById('btn-header-menu') || dom.btnHeaderMenu;
      if (!menu || menu.classList.contains('hidden')) return;
      if (!menu.contains(e.target) && !btn?.contains(e.target)) {
        closeHeaderMenu();
      }
    });

    // 드롭다운 메뉴 아이템: 1) 여행 정보 수정
    document.getElementById('btn-menu-edit-trip')?.addEventListener('click', () => {
      closeHeaderMenu();
      openTripSettingsModal();
    });

    // 드롭다운 메뉴 아이템: 2) 여행 계획 목록 및 비교
    document.getElementById('btn-menu-manage-trips')?.addEventListener('click', () => {
      closeHeaderMenu();
      openTripManagerModal('list');
    });

    // 드롭다운 메뉴 아이템: 3) 여행 일정 링크 복사
    document.getElementById('btn-menu-copy-share')?.addEventListener('click', async () => {
      closeHeaderMenu();
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

    // 브랜드 로고/제목 클릭 시 여행 계획 목록 열기 (자연스럽게 유지)
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

    // 기존 호환용 버튼 리스너 (DOM에 존재할 경우 안전 바인딩)
    dom.btnOpenCloudSync?.addEventListener('click', openCloudSyncModal);
    dom.btnManageTrips?.addEventListener('click', () => openTripManagerModal('list'));
    dom.btnEditTrip?.addEventListener('click', openTripSettingsModal);
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

    // 14. 일차(Day) 칩 바 데스크톱 마우스 휠 가로 스크롤 지원
    const dayChipSlider = document.getElementById('day-chip-slider-wrapper');
    dayChipSlider?.addEventListener('wheel', (e) => {
      if (e.deltaY !== 0) {
        e.preventDefault();
        dayChipSlider.scrollLeft += e.deltaY;
      }
    }, { passive: false });

    // 15. 중앙 상태(Store) 변경 감지 구독
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
      } else {
        syncMobileNavActiveState(null);
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

    // 16. 기본 내장 Supabase 클라우드 양방향 완전 자동 동기화 백그라운드 가동
    initCloudAutoSync();
  }

  // DOM 로드 완료 시 구동
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }
})();
