/**
 * @intent Google Maps JavaScript API 기반 대화형 지도 렌더러 - 번호 SVG 마커, 일차별 Polyline, 항공 점선 경로, InfoWindow
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

  /**
   * 일차 번호에 대응하는 테마 색상 반환
   * @param {number} dayNumber 
   * @returns {string} HEX 색상 코드
   */
  function getDayColor(dayNumber) {
    const idx = (Math.max(1, Number(dayNumber) || 1) - 1) % DAY_COLORS.length;
    return DAY_COLORS[idx];
  }

  /**
   * Google Maps Marker용 커스텀 번호 SVG 아이콘 객체 생성
   * @param {number} order - 방문 순번 (1, 2, 3...)
   * @param {string} color - 핀 테마 색상
   * @param {boolean} isSelected - 선택 상태 여부
   * @returns {object} Google Maps Icon 사양 객체
   */
  function createNumberedMarkerIcon(order, color = '#2563eb', isSelected = false) {
    const width = isSelected ? 38 : 32;
    const height = isSelected ? 48 : 42;
    const strokeWidth = isSelected ? 2.5 : 1.5;
    const strokeColor = '#ffffff';

    const svg = `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 42" width="${width}" height="${height}">
        <path d="M16 1C7.716 1 1 7.716 1 16c0 10.5 15 25 15 25s15-14.5 15-25c0-8.284-6.716-15-15-15z" 
              fill="${color}" stroke="${strokeColor}" stroke-width="${strokeWidth}" />
        <circle cx="16" cy="16" r="10" fill="#ffffff" />
        <text x="16" y="20.5" font-size="12" font-weight="700" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" 
              fill="${color}" text-anchor="middle" dominant-baseline="central">${order}</text>
      </svg>
    `.trim();

    const dataUrl = `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;

    if (typeof google !== 'undefined' && google.maps) {
      return {
        url: dataUrl,
        scaledSize: new google.maps.Size(width, height),
        origin: new google.maps.Point(0, 0),
        anchor: new google.maps.Point(width / 2, height)
      };
    }

    return {
      url: dataUrl,
      width,
      height
    };
  }

  /**
   * Google Maps 관리자 클래스
   */
  class TripMapManager {
    constructor() {
      this.map = null;
      this.infoWindow = null;
      this.markers = [];
      this.polylines = [];
      this.pinDropMarker = null;
      this.markerMap = new Map(); // id -> google.maps.Marker
      this.onMarkerClickListener = null;
      this.onPinDropListener = null;
      this.isPinDropActive = false;
      this.containerId = 'map-container';
    }

    /**
     * API 키 안내 배너 표시/숨김 토글
     * @param {boolean} visible 
     */
    setApiKeyBannerVisible(visible) {
      if (typeof document === 'undefined') return;
      const banner = document.getElementById('map-api-key-banner');
      if (banner) {
        banner.classList.toggle('hidden', !visible);
      }
    }

    /**
     * Google Maps 사용 가능 상태 검증
     * @returns {boolean}
     */
    isGoogleMapsReady() {
      if (typeof window === 'undefined') return false;

      // index.html 스크립트 태그 내 placeholder 키 사용 여부 검사
      const scriptTag = document.querySelector('script[src*="maps.googleapis.com"]');
      if (scriptTag && scriptTag.src.includes('key=YOUR_GOOGLE_MAPS_API_KEY')) {
        return false;
      }

      return Boolean(typeof google !== 'undefined' && google.maps && google.maps.Map);
    }

    /**
     * 지도 초기화
     * @param {string} containerId - 컨테이너 DOM ID
     * @param {Array<number>} initialCenter - [lat, lng]
     * @param {number} initialZoom - 기본 줌 레벨
     */
    init(containerId = 'map-container', initialCenter = [35.6895, 139.6917], initialZoom = 12, retryCount = 0) {
      this.containerId = containerId;

      if (typeof document === 'undefined') return;

      const container = document.getElementById(containerId);
      if (!container) {
        console.warn(`Map container #${containerId} not found`);
        return;
      }

      // Google 인증 실패 전역 훅 등록
      if (typeof window !== 'undefined') {
        window.gm_authFailure = () => {
          console.warn('Google Maps authentication failed: Invalid or missing API key.');
          this.setApiKeyBannerVisible(true);
        };
      }

      // Google Maps 라이브러리 준비 상태 확인
      const scriptTag = document.querySelector('script[src*="maps.googleapis.com"]');
      const isPlaceholder = scriptTag && scriptTag.src.includes('key=YOUR_GOOGLE_MAPS_API_KEY');

      if (isPlaceholder) {
        this.setApiKeyBannerVisible(true);
        return;
      }

      // 실제 키가 지정되어 있으나 스크립트가 아직 비동기 로딩 중인 경우 최대 10회 재시도
      if (!this.isGoogleMapsReady()) {
        if (retryCount < 10) {
          setTimeout(() => {
            this.init(containerId, initialCenter, initialZoom, retryCount + 1);
          }, 100);
          return;
        }
        this.setApiKeyBannerVisible(true);
        return;
      }

      this.setApiKeyBannerVisible(false);

      try {
        const centerLatLng = { lat: initialCenter[0], lng: initialCenter[1] };

        this.map = new google.maps.Map(container, {
          center: centerLatLng,
          zoom: initialZoom,
          mapTypeId: google.maps.MapTypeId.ROADMAP,
          zoomControl: true,
          mapTypeControl: false,
          scaleControl: true,
          streetViewControl: false,
          rotateControl: false,
          fullscreenControl: false,
          gestureHandling: 'greedy'
        });

        this.infoWindow = new google.maps.InfoWindow();

        // 지도 클릭 시 핀 드롭 이벤트 리스너 연동
        this.map.addListener('click', (e) => {
          if (!e || !e.latLng) return;
          const lat = e.latLng.lat();
          const lng = e.latLng.lng();

          if (this.isPinDropActive) {
            this.setPinDropPreview(lat, lng);
            if (this.onPinDropListener) {
              this.onPinDropListener(lat, lng);
            }
          }
        });
      } catch (err) {
        console.warn('Failed to initialize Google Maps:', err.message);
        this.setApiKeyBannerVisible(true);
      }
    }

    setMarkerClickListener(listener) {
      this.onMarkerClickListener = listener;
    }

    setPinDropListener(listener) {
      this.onPinDropListener = listener;
    }

    /**
     * 지도 직접 클릭 핀 드롭 모드 활성화/비활성화
     * @param {boolean} enabled 
     */
    setPinDropMode(enabled) {
      this.isPinDropActive = Boolean(enabled);

      if (this.map) {
        this.map.setOptions({
          draggableCursor: this.isPinDropActive ? 'crosshair' : null
        });
      }

      if (!this.isPinDropActive && this.pinDropMarker) {
        this.pinDropMarker.setMap(null);
        this.pinDropMarker = null;
      }
    }

    /**
     * 핀 드롭 선택 지점 미리보기 마커 표시
     * @param {number} lat 
     * @param {number} lng 
     */
    setPinDropPreview(lat, lng) {
      if (!this.map || typeof google === 'undefined' || !google.maps) return;

      if (this.pinDropMarker) {
        this.pinDropMarker.setMap(null);
      }

      const position = { lat, lng };

      this.pinDropMarker = new google.maps.Marker({
        position,
        map: this.map,
        title: '선택한 위치',
        zIndex: 1000,
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 7,
          fillColor: '#ef4444',
          fillOpacity: 1,
          strokeColor: '#ffffff',
          strokeWeight: 2
        }
      });

      if (this.infoWindow) {
        const popupDiv = document.createElement('div');
        popupDiv.style.cssText = 'padding: 4px 6px; font-size: 13px; font-weight: 600; color: #1e293b;';

        const boldEl = document.createElement('div');
        boldEl.textContent = '선택한 위치';
        popupDiv.appendChild(boldEl);

        const subEl = document.createElement('div');
        subEl.style.cssText = 'font-size: 11px; font-weight: 400; color: #64748b; margin-top: 2px;';
        subEl.textContent = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
        popupDiv.appendChild(subEl);

        this.infoWindow.setContent(popupDiv);
        this.infoWindow.open(this.map, this.pinDropMarker);
      }
    }

    /**
     * 일정 아이템 InfoWindow 오픈 (XSS 방어 안전 노드 생성)
     * @param {google.maps.Marker} marker 
     * @param {object} item 
     * @param {number} order 
     */
    openItemInfoWindow(marker, item, order) {
      if (!this.infoWindow || !this.map) return;

      const container = document.createElement('div');
      container.style.cssText = 'padding: 6px 4px; min-width: 170px; max-width: 260px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;';

      const titleEl = document.createElement('div');
      titleEl.style.cssText = 'font-weight: 700; font-size: 14px; color: #0f172a; margin-bottom: 4px; word-break: break-word;';
      titleEl.textContent = `[${order}] ${item.title || '일정'}`;
      container.appendChild(titleEl);

      if (item.category) {
        const catBadge = document.createElement('span');
        catBadge.style.cssText = 'display: inline-block; padding: 2px 6px; font-size: 11px; font-weight: 600; color: #2563eb; background: #eff6ff; border-radius: 4px; margin-bottom: 6px;';
        catBadge.textContent = item.category;
        container.appendChild(catBadge);
      }

      if (item.time) {
        const timeEl = document.createElement('div');
        timeEl.style.cssText = 'font-size: 12px; color: #64748b; margin-bottom: 4px;';
        timeEl.textContent = `시간: ${item.time}`;
        container.appendChild(timeEl);
      }

      if (item.memo) {
        const memoEl = document.createElement('div');
        memoEl.style.cssText = 'font-size: 12px; color: #334155; line-height: 1.4; word-break: break-word; background: #f8fafc; padding: 6px; border-radius: 4px; border: 1px solid #e2e8f0; margin-top: 4px;';
        memoEl.textContent = item.memo;
        container.appendChild(memoEl);
      }

      this.infoWindow.setContent(container);
      this.infoWindow.open(this.map, marker);
    }

    /**
     * 일차별 마커 및 이동 경로 Polyline 렌더링
     * @param {Array<object>} items - 전체 일정 목록
     * @param {number} selectedDay - 선택된 일차
     * @param {string|null} selectedItemId - 현재 선택/하이라이트된 아이템 ID
     */
    render(items = [], selectedDay = 1, selectedItemId = null) {
      if (!this.map || typeof google === 'undefined' || !google.maps) return;

      // 기존 마커 및 경로선 정리
      this.markers.forEach((m) => m.setMap(null));
      this.markers = [];
      this.polylines.forEach((p) => p.setMap(null));
      this.polylines = [];
      this.markerMap.clear();

      if (this.infoWindow) {
        this.infoWindow.close();
      }

      const dayItems = items.filter((item) => Number(item.day) === Number(selectedDay));
      const validPoints = [];
      const dayColor = getDayColor(selectedDay);
      const bounds = new google.maps.LatLngBounds();

      let order = 1;
      dayItems.forEach((item) => {
        if (typeof item.lat === 'number' && typeof item.lng === 'number' && !isNaN(item.lat) && !isNaN(item.lng)) {
          const isSelected = item.id === selectedItemId;
          const currentOrder = order;
          const icon = createNumberedMarkerIcon(currentOrder, dayColor, isSelected);
          const position = { lat: item.lat, lng: item.lng };

          const marker = new google.maps.Marker({
            position,
            map: this.map,
            icon,
            title: item.title || `스팟 ${currentOrder}`,
            zIndex: isSelected ? 999 : currentOrder
          });

          marker.addListener('click', () => {
            this.openItemInfoWindow(marker, item, currentOrder);
            if (this.onMarkerClickListener) {
              this.onMarkerClickListener(item.id);
            }
          });

          this.markers.push(marker);
          this.markerMap.set(item.id, marker);
          validPoints.push(position);
          bounds.extend(position);

          // 항공 구간(FLIGHT) 전용 점선(Dashed) 경로선 렌더링
          if (item.category === 'FLIGHT' && typeof item.destLat === 'number' && typeof item.destLng === 'number') {
            const destPos = { lat: item.destLat, lng: item.destLng };
            bounds.extend(destPos);

            const lineSymbol = {
              path: 'M 0,-1 0,1',
              strokeOpacity: 1,
              scale: 3,
              strokeColor: '#3b82f6'
            };

            const flightLine = new google.maps.Polyline({
              path: [position, destPos],
              strokeColor: '#3b82f6',
              strokeOpacity: 0,
              icons: [{
                icon: lineSymbol,
                offset: '0',
                repeat: '16px'
              }],
              map: this.map
            });

            this.polylines.push(flightLine);
          }

          order++;
        }
      });

      // 일반 방문지 간 일차별 실선 Polyline 연결
      if (validPoints.length >= 2) {
        const routePolyline = new google.maps.Polyline({
          path: validPoints,
          geodesic: true,
          strokeColor: dayColor,
          strokeOpacity: 0.85,
          strokeWeight: 4,
          map: this.map
        });

        this.polylines.push(routePolyline);
      }

      // 화면에 모든 마커가 보이도록 FitBounds (선택된 아이템이 없을 때)
      if (!selectedItemId && validPoints.length > 0) {
        if (validPoints.length === 1) {
          this.map.setCenter(validPoints[0]);
          this.map.setZoom(15);
        } else {
          this.map.fitBounds(bounds, {
            top: 50,
            right: 50,
            bottom: 50,
            left: 50
          });
        }
      }

      // 선택된 아이템이 존재하는 경우 InfoWindow 자동 오픈
      if (selectedItemId && this.markerMap.has(selectedItemId)) {
        const selMarker = this.markerMap.get(selectedItemId);
        const selItem = dayItems.find((it) => it.id === selectedItemId);
        if (selItem) {
          const selOrder = dayItems.filter((it) => typeof it.lat === 'number' && typeof it.lng === 'number' && !isNaN(it.lat) && !isNaN(it.lng)).indexOf(selItem) + 1;
          this.openItemInfoWindow(selMarker, selItem, selOrder || 1);
        }
      }
    }

    /**
     * 특정 일정 아이템으로 지도 카메라 부드럽게 이동 및 InfoWindow 오픈
     * @param {object} item 
     */
    flyToItem(item) {
      if (!this.map || !item || typeof google === 'undefined' || !google.maps) return;
      if (typeof item.lat !== 'number' || typeof item.lng !== 'number') return;

      const position = { lat: item.lat, lng: item.lng };

      this.map.panTo(position);
      if (this.map.getZoom() < 15) {
        this.map.setZoom(15);
      }

      const marker = this.markerMap.get(item.id);
      if (marker) {
        setTimeout(() => {
          this.openItemInfoWindow(marker, item, 1);
        }, 300);
      }
    }

    /**
     * 지도 컨테이너 크기 재계산 (탭 전환, 바텀시트 제스처 대응)
     */
    invalidateSize() {
      if (this.map && typeof google !== 'undefined' && google.maps && google.maps.event) {
        google.maps.event.trigger(this.map, 'resize');
      }
    }
  }

  const mapInstance = new TripMapManager();

  return {
    TripMapManager,
    mapManager: mapInstance,
    getDayColor,
    createNumberedMarkerIcon
  };
});
