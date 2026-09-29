/**
 * @intent Leaflet/OpenStreetMap 단독 대화형 지도 렌더러 (Google Maps 의존성 완전 제거 및 단일 엔진 표준화)
 *         - 번호 SVG 커스텀 마커 (1, 2, 3...)
 *         - 일차별 고유 테마 컬러 Polyline 및 항공편(FLIGHT) 전용 점선 항공로
 *         - Leaflet Popup 및 타임라인 카드-마커 양방향 연동
 *         - 지도 직접 클릭 핀 드롭 모드
 *         - 100% 반응형 및 모바일 바텀시트 연동
 *         - 시각적 +/- 줌 버튼 완전 제거 (핀치 줌 및 마우스 휠 줌 유지)
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripMap = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // 일차(Day)별 고유 테마 색상 팔레트
  const DAY_COLORS = [
    '#2563eb', // Day 1: Royal Blue
    '#059669', // Day 2: Emerald Green
    '#d97706', // Day 3: Amber Orange
    '#db2777', // Day 4: Deep Pink
    '#7c3aed', // Day 5: Purple
    '#0891b2', // Day 6: Cyan
    '#4b5563'  // Day 7+: Slate Gray
  ];

  function getDayColor(dayNumber) {
    const idx = (Math.max(1, Number(dayNumber) || 1) - 1) % DAY_COLORS.length;
    return DAY_COLORS[idx];
  }

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  /**
   * 커스텀 번호 SVG 마커 생성 (공통)
   */
  function createNumberedSvgString(order, color = '#2563eb', isSelected = false) {
    const width = isSelected ? 36 : 30;
    const height = isSelected ? 46 : 40;
    const strokeWidth = isSelected ? 2.5 : 1.5;

    return `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 42" width="${width}" height="${height}">
        <path d="M16 1C7.716 1 1 7.716 1 16c0 10.5 15 25 15 25s15-14.5 15-25c0-8.284-6.716-15-15-15z" 
              fill="${color}" stroke="#ffffff" stroke-width="${strokeWidth}" />
        <circle cx="16" cy="16" r="10" fill="#ffffff" />
        <text x="16" y="20.5" font-size="12" font-weight="700" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" 
              fill="${color}" text-anchor="middle" dominant-baseline="central">${order}</text>
      </svg>
    `.trim();
  }

  /**
   * @intent 마커 클릭 시 Leaflet 팝업용 미니 일정 카드 템플릿 생성
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  function createMarkerPopupHtml(item, order, themeColor) {
    const catMeta = {
      FLIGHT: '비행기',
      AIRPORT: '공항',
      HOTEL: '숙소',
      ATTRACTION: '명소',
      DINING: '식당',
      TRANSIT: '교통'
    };
    const catLabel = catMeta[item.category] || '일정';
    const timeText = item.time || item.checkInTime || item.departureTime || '';
    const subInfo = item.flightNo || item.transitMode || item.menuRecommendation || item.address || '';
    const costText = Number(item.cost) > 0 ? `${Number(item.cost).toLocaleString()}원` : '';

    return `
      <div class="map-item-popup">
        <div class="popup-header">
          <span class="popup-order-badge" style="background-color:${themeColor || '#2563eb'};">${order}</span>
          <span class="popup-cat-badge">${escapeHtml(catLabel)}</span>
          <strong class="popup-title">${escapeHtml(item.title || '일정')}</strong>
        </div>
        ${timeText || subInfo ? `
          <div class="popup-details">
            ${timeText ? `<span class="popup-detail-time">${escapeHtml(timeText)}</span>` : ''}
            ${subInfo ? `<span class="popup-detail-sub">${escapeHtml(subInfo)}</span>` : ''}
          </div>
        ` : ''}
        ${costText ? `<div class="popup-cost">${costText}</div>` : ''}
        <button type="button" class="btn-popup-view" data-item-id="${escapeHtml(item.id)}">
          상세보기 / 수정
        </button>
      </div>
    `.trim();
  }

  class TripMapManager {
    constructor() {
      this.engine = 'leaflet';
      this.map = null;
      this.containerId = 'map-container';
      this.markers = [];
      this.polylines = [];
      this.pinDropMarker = null;
      this.markerMap = new Map();
      this.onMarkerClickListener = null;
      this.onPinDropListener = null;
      this.isPinDropActive = false;
      this.currentCenter = [35.6895, 139.6917];
      this.currentZoom = 12;
      this.currentRenderedDay = null;
      this.pendingRender = null;
      this.lastRenderArgs = null;
    }

    /**
     * 외부 하위 호환성을 위한 no-op 메서드
     */
    setApiKeyBannerVisible() {}

    /**
     * @intent Leaflet 단독 지도 초기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    async init(containerId = 'map-container', initialCenter = [35.6895, 139.6917], initialZoom = 12) {
      this.containerId = containerId;
      this.currentCenter = initialCenter;
      this.currentZoom = initialZoom;

      if (typeof document === 'undefined') return;
      const container = document.getElementById(containerId);
      if (!container) return;

      if (typeof L !== 'undefined') {
        this.initLeaflet(container, initialCenter, initialZoom);
      }
    }

    /**
     * 외부 하위 호환성을 위한 no-op 메서드
     */
    async updateApiKey() {
      return false;
    }

    /**
     * @intent Leaflet 초기화 (+/- 줌 컨트롤 제거 및 핀치/마우스 휠 줌 유지)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    initLeaflet(container, initialCenter, initialZoom) {
      this.engine = 'leaflet';

      try {
        if (this.map && typeof this.map.remove === 'function') {
          this.map.remove();
        }

        this.map = L.map(container, {
          zoomControl: false,
          attributionControl: true
        }).setView(initialCenter, initialZoom);

        // 오픈스트리트맵 타일
        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
          maxZoom: 19,
          attribution: '&copy; OpenStreetMap'
        }).addTo(this.map);

        this.map.on('click', (e) => {
          if (!this.isPinDropActive) return;
          const { lat, lng } = e.latlng;
          this.setPinDropPreview(lat, lng);
          if (this.onPinDropListener) this.onPinDropListener(lat, lng);
        });

        if (this.pendingRender) {
          const { items, dayNumber, selectedItemId } = this.pendingRender;
          this.pendingRender = null;
          this.render(items, dayNumber, selectedItemId);
        }
      } catch (err) {
        console.error('Leaflet init failed:', err);
      }
    }

    setMarkerClickListener(listener) {
      this.onMarkerClickListener = listener;
    }

    setPinDropListener(listener) {
      this.onPinDropListener = listener;
    }

    setPinDropMode(enabled) {
      this.isPinDropActive = Boolean(enabled);

      if (!this.isPinDropActive && this.pinDropMarker && this.map) {
        this.map.removeLayer(this.pinDropMarker);
        this.pinDropMarker = null;
      }
    }

    setPinDropPreview(lat, lng) {
      if (!this.map) return;

      if (this.pinDropMarker) {
        this.map.removeLayer(this.pinDropMarker);
      }

      const icon = L.divIcon({
        className: 'pin-drop-preview-icon',
        html: `<div style="width:14px;height:14px;background:#ef4444;border:2px solid #fff;border-radius:50%;box-shadow:0 2px 6px rgba(0,0,0,0.4);"></div>`,
        iconSize: [14, 14],
        iconAnchor: [7, 7]
      });
      this.pinDropMarker = L.marker([lat, lng], { icon }).addTo(this.map);
      this.pinDropMarker.bindPopup(`선택 위치: ${lat.toFixed(4)}, ${lng.toFixed(4)}`).openPopup();
    }

    clearLayers() {
      if (this.map) {
        this.markers.forEach((m) => this.map.removeLayer(m));
        this.polylines.forEach((p) => this.map.removeLayer(p));
      }
      this.markers = [];
      this.polylines = [];
      this.markerMap.clear();
    }

    /**
     * 특정 일차(Day)의 아이템 렌더링
     */
    render(items = [], dayNumber = 1, selectedItemId = null) {
      this.lastRenderArgs = { items, dayNumber, selectedItemId };
      if (!this.map) {
        this.pendingRender = { items, dayNumber, selectedItemId };
        return;
      }
      this.clearLayers();

      const dayItems = (items || []).filter((it) => Number(it.day) === Number(dayNumber));
      const validItems = dayItems.filter((it) => it.lat != null && it.lng != null && !isNaN(it.lat) && !isNaN(it.lng));

      if (validItems.length === 0) return;

      const themeColor = getDayColor(dayNumber);
      const points = [];

      validItems.forEach((item, index) => {
        const order = index + 1;
        const lat = Number(item.lat);
        const lng = Number(item.lng);
        const isSelected = item.id === selectedItemId;

        points.push([lat, lng]);

        const svgStr = createNumberedSvgString(order, themeColor, isSelected);
        const icon = L.divIcon({
          className: 'numbered-custom-pin',
          html: svgStr,
          iconSize: [isSelected ? 36 : 30, isSelected ? 46 : 40],
          iconAnchor: [isSelected ? 18 : 15, isSelected ? 46 : 40],
          popupAnchor: [0, -40]
        });

        const marker = L.marker([lat, lng], { icon, zIndexOffset: isSelected ? 1000 : order * 10 }).addTo(this.map);
        const popupHtml = createMarkerPopupHtml(item, order, themeColor);
        marker.popupHtml = popupHtml;
        marker.bindPopup(popupHtml, { minWidth: 200, className: 'leaflet-custom-popup' });

        marker.on('click', () => {
          marker.openPopup();
          if (this.onMarkerClickListener) this.onMarkerClickListener(item.id);
        });

        if (isSelected) {
          marker.openPopup();
        }

        this.markers.push(marker);
        this.markerMap.set(item.id, marker);
      });

      // 경로선(Polyline) 렌더링
      if (points.length >= 2) {
        const polyline = L.polyline(points, {
          color: themeColor,
          weight: 4,
          opacity: 0.85,
          lineJoin: 'round'
        }).addTo(this.map);
        this.polylines.push(polyline);
      }

      // 비행기(FLIGHT) 전용 점선 항공로 렌더링
      validItems.forEach((item) => {
        if (item.category === 'FLIGHT' && item.destLat && item.destLng) {
          const startPt = [Number(item.lat), Number(item.lng)];
          const endPt = [Number(item.destLat), Number(item.destLng)];

          const flightPoly = L.polyline([startPt, endPt], {
            color: '#0284c7',
            weight: 3,
            opacity: 0.8,
            dashArray: '8, 8'
          }).addTo(this.map);
          this.polylines.push(flightPoly);
        }
      });

      // 지도 범위 자동 조정 (일차가 변경되었거나 첫 렌더링 시에만 실행하여 사용자 줌/선택 상태 유지)
      const dayChanged = this.currentRenderedDay !== dayNumber;
      this.currentRenderedDay = dayNumber;
      if (points.length > 0 && dayChanged) {
        this.map.fitBounds(points, { padding: [40, 40], maxZoom: 15 });
      }
    }

    /**
     * @intent 특정 마커 위치로 카메라 부드러운 이동 및 팝업 활성화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    flyToItem(itemOrId) {
      const targetId = typeof itemOrId === 'object' && itemOrId !== null ? itemOrId.id : itemOrId;
      const marker = this.markerMap.get(targetId);
      if (!marker || !this.map) return;

      const latlng = marker.getLatLng();
      this.map.flyTo(latlng, 15, { duration: 0.8 });
      marker.openPopup();
    }

    invalidateSize() {
      if (!this.map) return;
      if (typeof this.map.invalidateSize === 'function') {
        this.map.invalidateSize();
      }
    }
  }

  const mapManager = new TripMapManager();

  return {
    TripMapManager,
    mapManager,
    DAY_COLORS,
    getDayColor,
    createMarkerPopupHtml,
    getSavedGoogleApiKey: () => '',
    saveGoogleApiKey: () => {}
  };
});
