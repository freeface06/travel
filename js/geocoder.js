/**
 * @intent OpenStreetMap Nominatim 지오코딩 및 역지오코딩 모듈
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripGeocoder = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const NOMINATIM_BASE = 'https://nominatim.openstreetmap.org';

  /**
   * 장소/주소 텍스트 검색
   * @param {string} query - 검색어
   * @param {number} limit - 최대 반환 건수
   * @returns {Promise<Array<{name: string, lat: number, lng: number, address: string}>>}
   */
  async function searchPlaces(query, limit = 5) {
    const q = (query || '').trim();
    if (!q || q.length < 2) return [];

    const url = `${NOMINATIM_BASE}/search?format=json&q=${encodeURIComponent(q)}&limit=${limit}&addressdetails=1`;

    try {
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ko,en'
        }
      });

      if (!response.ok) {
        throw new Error(`Nominatim search failed with HTTP ${response.status}`);
      }

      const data = await response.json();
      return (data || []).map((item) => ({
        name: item.display_name.split(',')[0].trim(),
        displayName: item.display_name,
        lat: parseFloat(item.lat),
        lng: parseFloat(item.lon),
        type: item.type || 'place',
        raw: item
      }));
    } catch (err) {
      console.warn('Geocoding search error:', err.message);
      return [];
    }
  }

  /**
   * 위경도 좌표 역지오코딩 (Reverse Geocoding)
   * @param {number} lat - 위도
   * @param {number} lng - 경도
   * @returns {Promise<{name: string, address: string, lat: number, lng: number}>}
   */
  async function reverseGeocode(lat, lng) {
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (isNaN(latitude) || isNaN(longitude)) {
      throw new Error('Invalid coordinates for reverse geocoding');
    }

    const url = `${NOMINATIM_BASE}/reverse?format=json&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`;

    try {
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ko,en'
        }
      });

      if (!response.ok) {
        throw new Error(`Nominatim reverse failed with HTTP ${response.status}`);
      }

      const data = await response.json();
      const placeName = data.name || (data.display_name ? data.display_name.split(',')[0] : '지정된 위치');
      return {
        name: placeName,
        displayName: data.display_name || `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`,
        lat: latitude,
        lng: longitude,
        raw: data
      };
    } catch (err) {
      console.warn('Reverse geocoding error:', err.message);
      return {
        name: `지정된 좌표 (${latitude.toFixed(4)}, ${longitude.toFixed(4)})`,
        displayName: `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`,
        lat: latitude,
        lng: longitude
      };
    }
  }

  /**
   * 함수 호출 디바운스(Debounce) 헬퍼
   */
  function debounce(fn, waitMs = 400) {
    let timer = null;
    return function (...args) {
      clearTimeout(timer);
      timer = setTimeout(() => {
        fn.apply(this, args);
      }, waitMs);
    };
  }

  return {
    searchPlaces,
    reverseGeocode,
    debounce
  };
});
