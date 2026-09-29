/**
 * @intent Leaflet.js 기반 대화형 지도 렌더러 - 번호 SVG 마커, 일차별 경로 Polyline, 비행기 점선 동선
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

  /**
   * 커스텀 번호 SVG 마커 아이콘 생성
   * @param {number} order - 방문 순번 (1, 2, 3...)
   * @param {string} color - 핀 테마 색상
   * @param {boolean} isSelected - 선택 상태 여부
   * @returns {L.DivIcon} Leaflet DivIcon
   */
  function createNumberedMarkerIcon(order, color = '#2563eb', isSelected = false) {
    if (typeof L === 'undefined') return null;

    const width = isSelected ? 38 : 32;
    const height = isSelected ? 48 : 42;
    const strokeWidth = isSelected ? 2.5 : 1.5;
    const strokeColor = isSelected ? '#ffffff' : '#ffffff';
    const dropShadow = isSelected
      ? 'filter: drop-shadow(0 4px 8px rgba(0,0,0,0.45));'
      : 'filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));';

    const svg = `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 42" width="${width}" height="${height}" style="${dropShadow} cursor: pointer;">
        <path d="M16 1C7.716 1 1 7.716 1 16c0 10.5 15 25 15 25s15-14.5 15-25c0-8.284-6.716-15-15-15z" 
              fill="${color}" stroke="${strokeColor}" stroke-width="${strokeWidth}" />
        <circle cx="16" cy="16" r="10" fill="#ffffff" />
        <text x="16" y="20.5" font-size="12" font-weight="700" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" 
              fill="${color}" text-anchor="middle" dominant-baseline="central">${order}</text>
      </svg>
    `;

    return L.divIcon({
      className: 'mytriplog-map-marker',
      html: svg,
      iconSize: [width, height],
      iconAnchor: [width / 2, height],
      popupAnchor: [0, -height]
    });
  }

  class TripMapManager {
    constructor() {
      this.map = null;
      this.markersLayer = null;
      this.routesLayer = null;
      this.pinDropLayer = null;
      this.markerMap = new Map(); // id -> L.marker
      this.onMarkerClickListener = null;
      this.onPinDropListener = null;
      this.isPinDropActive = false;
    }

    /**
     * 지도 초기화
     * @param {string} containerId - 컨테이너 DOM ID
     * @param {Array<number>} initialCenter - [lat, lng]
     * @param {number} initialZoom - 기본 줌 레벨
     */
    init(containerId = 'map-container', initialCenter = [35.6895, 139.6917], initialZoom = 12) {
      if (typeof L === 'undefined') {
        console.warn('Leaflet library is not loaded');
        return;
      }

      const container = document.getElementById(containerId);
      if (!container) {
        console.warn(`Map container #${containerId} not found`);
        return;
      }

      this.map = L.map(containerId, {
        zoomControl: true,
        attributionControl: true
      }).setView(initialCenter, initialZoom);

      // OpenStreetMap 타일 레이어
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(this.map);

      // 레이어 그룹
      this.routesLayer = L.layerGroup().addTo(this.map);
      this.markersLayer = L.layerGroup().addTo(this.map);
      this.pinDropLayer = L.layerGroup().addTo(this.map);

      // 지도 클릭 시 핀 드롭 이벤트 처리
      this.map.on('click', (e) => {
        if (this.isPinDropActive && this.onPinDropListener) {
          const { lat, lng } = e.latlng;
          this.setPinDropPreview(lat, lng);
          this.onPinDropListener(lat, lng);
        }
      });
    }

    setMarkerClickListener(listener) {
      this.onMarkerClickListener = listener;
    }

    setPinDropListener(listener) {
      this.onPinDropListener = listener;
    }

    setPinDropMode(enabled) {
      this.isPinDropActive = Boolean(enabled);
      if (this.map && this.map.getContainer()) {
        if (this.isPinDropActive) {
          this.map.getContainer().style.cursor = 'crosshair';
        } else {
          this.map.getContainer().style.cursor = '';
          this.pinDropLayer.clearLayers();
        }
      }
    }

    setPinDropPreview(lat, lng) {
      this.pinDropLayer.clearLayers();
      const marker = L.circleMarker([lat, lng], {
        radius: 8,
        color: '#dc2626',
        fillColor: '#ef4444',
        fillOpacity: 0.9,
        weight: 3
      }).addTo(this.pinDropLayer);
      marker.bindPopup(`<strong>선택한 위치</strong><br>${lat.toFixed(5)}, ${lng.toFixed(5)}`).openPopup();
    }

    /**
     * 일차별 마커 및 이동 경로 Polyline 렌더링
     * @param {Array<object>} items - 일정 목록
     * @param {number} selectedDay - 선택된 일차
     * @param {string|null} selectedItemId - 현재 선택/하이라이트된 아이템 ID
     */
    render(items = [], selectedDay = 1, selectedItemId = null) {
      if (!this.map) return;

      this.markersLayer.clearLayers();
      this.routesLayer.clearLayers();
      this.markerMap.clear();

      const dayItems = items.filter((item) => Number(item.day) === Number(selectedDay));
      const validPoints = [];
      const dayColor = getDayColor(selectedDay);

      let order = 1;
      dayItems.forEach((item) => {
        if (typeof item.lat === 'number' && typeof item.lng === 'number' && !isNaN(item.lat) && !isNaN(item.lng)) {
          const isSelected = item.id === selectedItemId;
          const icon = createNumberedMarkerIcon(order, dayColor, isSelected);

          const marker = L.marker([item.lat, item.lng], {
            icon,
            title: item.title || `스팟 ${order}`
          });

          // 팝업 내용 조립 (XSS 안전 텍스트 노드 처리 보장)
          const popupDiv = document.createElement('div');
          popupDiv.className = 'map-popup-card';
          
          const titleEl = document.createElement('div');
          titleEl.className = 'map-popup-title';
          titleEl.textContent = `[${order}] ${item.title || '일정'}`;
          popupDiv.appendChild(titleEl);

          if (item.category) {
            const catBadge = document.createElement('span');
            catBadge.className = 'map-popup-badge';
            catBadge.textContent = item.category;
            popupDiv.appendChild(catBadge);
          }

          if (item.time) {
            const timeEl = document.createElement('div');
            timeEl.className = 'map-popup-time';
            timeEl.textContent = `시간: ${item.time}`;
            popupDiv.appendChild(timeEl);
          }

          if (item.memo) {
            const memoEl = document.createElement('div');
            memoEl.className = 'map-popup-memo';
            memoEl.textContent = item.memo;
            popupDiv.appendChild(memoEl);
          }

          marker.bindPopup(popupDiv);

          marker.on('click', () => {
            if (this.onMarkerClickListener) {
              this.onMarkerClickListener(item.id);
            }
          });

          marker.addTo(this.markersLayer);
          this.markerMap.set(item.id, marker);

          validPoints.push([item.lat, item.lng]);

          // 항공(FLIGHT)의 경우 목적지 좌표가 있으면 항공 전용 점선 Polyline 별도 렌더링
          if (item.category === 'FLIGHT' && typeof item.destLat === 'number' && typeof item.destLng === 'number') {
            const flightPoints = [
              [item.lat, item.lng],
              [item.destLat, item.destLng]
            ];
            const flightLine = L.polyline(flightPoints, {
              color: '#3b82f6',
              weight: 4,
              opacity: 0.85,
              dashArray: '8, 8',
              lineCap: 'round'
            }).addTo(this.routesLayer);
            flightLine.bindTooltip(`항공편: ${item.flightNo || item.title || 'Flight'}`, { sticky: true });
          }

          order++;
        }
      });

      // 일반 방문지 간 동선 Polyline 연결
      if (validPoints.length >= 2) {
        L.polyline(validPoints, {
          color: dayColor,
          weight: 4,
          opacity: 0.8,
          smoothFactor: 1
        }).addTo(this.routesLayer);
      }

      // 화면에 모든 마커가 보이도록 FitBounds (단, 선택된 아이템이 없을 때)
      if (!selectedItemId && validPoints.length > 0) {
        this.map.fitBounds(validPoints, { padding: [40, 40], maxZoom: 15 });
      }
    }

    /**
     * 특정 일정 아이템으로 지도 카메라 부드럽게 이동 및 팝업 오픈
     * @param {object} item 
     */
    flyToItem(item) {
      if (!this.map || !item) return;
      if (typeof item.lat !== 'number' || typeof item.lng !== 'number') return;

      this.map.flyTo([item.lat, item.lng], 16, {
        duration: 1.0
      });

      const marker = this.markerMap.get(item.id);
      if (marker) {
        setTimeout(() => {
          marker.openPopup();
        }, 600);
      }
    }

    /**
     * 지도 컨테이너 크기 재계산 (탭 전환, 바텀시트 리사이즈 대응)
     */
    invalidateSize() {
      if (this.map) {
        this.map.invalidateSize();
      }
    }
  }

  const mapInstance = new TripMapManager();

  return {
    TripMapManager,
    mapManager: mapInstance,
    getDayColor
  };
});
