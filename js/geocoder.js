/**
 * @intent Google Maps Geocoder 및 OpenStreetMap Nominatim 폴백 지오코딩/역지오코딩 모듈
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
   * Google Maps Geocoder 서비스 인스턴스 반환 가능 여부 확인
   * @returns {boolean}
   */
  function isGoogleGeocoderAvailable() {
    return Boolean(
      typeof window !== 'undefined' &&
      window.google &&
      window.google.maps &&
      window.google.maps.Geocoder
    );
  }

  /**
   * Google Geocoder를 통한 장소/주소 검색
   * @param {string} query 
   * @param {number} limit 
   * @returns {Promise<Array<{name: string, displayName: string, lat: number, lng: number, type: string, raw: object}>>}
   */
  function searchViaGoogle(query, limit = 5) {
    return new Promise((resolve) => {
      try {
        const geocoder = new google.maps.Geocoder();
        geocoder.geocode({ address: query, language: 'ko', region: 'KR' }, (results, status) => {
          if (status === google.maps.GeocoderStatus.OK && Array.isArray(results) && results.length > 0) {
            const mapped = results.slice(0, limit).map((item) => {
              const loc = item.geometry.location;
              const lat = typeof loc.lat === 'function' ? loc.lat() : Number(loc.lat);
              const lng = typeof loc.lng === 'function' ? loc.lng() : Number(loc.lng);
              const name = (item.address_components && item.address_components[0])
                ? item.address_components[0].long_name
                : item.formatted_address;

              return {
                name,
                displayName: item.formatted_address,
                lat,
                lng,
                type: (item.types && item.types[0]) || 'place',
                raw: item
              };
            });
            resolve(mapped);
          } else {
            resolve([]);
          }
        });
      } catch (err) {
        console.warn('Google Geocoder search failed, fallback will be used:', err.message);
        resolve([]);
      }
    });
  }

  /**
   * Nominatim(OpenStreetMap)을 통한 장소/주소 검색 (Google API 키 미설정 또는 실패 시 폴백)
   * @param {string} query 
   * @param {number} limit 
   * @returns {Promise<Array<{name: string, displayName: string, lat: number, lng: number, type: string, raw: object}>>}
   */
  async function searchViaNominatim(query, limit = 5) {
    const url = `${NOMINATIM_BASE}/search?format=json&q=${encodeURIComponent(query)}&limit=${limit}&addressdetails=1&accept-language=ko`;

    try {
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8'
        }
      });


      if (!response.ok) {
        throw new Error(`Nominatim HTTP ${response.status}`);
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
      console.warn('Nominatim search error:', err.message);
      return [];
    }
  }

  /**
   * 장소/주소 통합 검색 (Google Geocoder 우선 -> Nominatim 폴백)
   * @param {string} query - 검색어
   * @param {number} limit - 최대 반환 건수
   * @returns {Promise<Array<{name: string, displayName: string, lat: number, lng: number, type: string, raw: object}>>}
   */
  async function searchPlaces(query, limit = 5) {
    const q = (query || '').trim();
    if (!q || q.length < 2) return [];

    // 1. Google Geocoder 사용 시도
    if (isGoogleGeocoderAvailable()) {
      try {
        const googleResults = await searchViaGoogle(q, limit);
        if (googleResults && googleResults.length > 0) {
          return googleResults;
        }
      } catch (e) {
        console.warn('Google Geocoder exception, using Nominatim fallback:', e.message);
      }
    }

    // 2. Nominatim 폴백 검색
    return await searchViaNominatim(q, limit);
  }

  /**
   * Google Geocoder를 통한 역지오코딩
   * @param {number} lat 
   * @param {number} lng 
   * @returns {Promise<{name: string, displayName: string, lat: number, lng: number, raw: object}>}
   */
  function reverseViaGoogle(lat, lng) {
    return new Promise((resolve, reject) => {
      try {
        const geocoder = new google.maps.Geocoder();
        geocoder.geocode({ location: { lat, lng }, language: 'ko', region: 'KR' }, (results, status) => {
          if (status === google.maps.GeocoderStatus.OK && Array.isArray(results) && results.length > 0) {
            const first = results[0];
            const name = (first.address_components && first.address_components[0])
              ? first.address_components[0].long_name
              : first.formatted_address;

            resolve({
              name,
              displayName: first.formatted_address,
              lat,
              lng,
              raw: first
            });
          } else {
            reject(new Error(`Google reverse geocode status: ${status}`));
          }
        });
      } catch (err) {
        reject(err);
      }
    });
  }

  /**
   * Nominatim을 통한 역지오코딩 (폴백)
   * @param {number} lat 
   * @param {number} lng 
   * @returns {Promise<{name: string, displayName: string, lat: number, lng: number, raw: object}>}
   */
  async function reverseViaNominatim(lat, lng) {
    const url = `${NOMINATIM_BASE}/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&accept-language=ko`;

    const response = await fetch(url, {
      headers: {
        'Accept': 'application/json',
        'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8'
      }
    });


    if (!response.ok) {
      throw new Error(`Nominatim reverse HTTP ${response.status}`);
    }

    const data = await response.json();
    const placeName = data.name || (data.display_name ? data.display_name.split(',')[0] : '지정된 위치');
    return {
      name: placeName,
      displayName: data.display_name || `${lat.toFixed(4)}, ${lng.toFixed(4)}`,
      lat,
      lng,
      raw: data
    };
  }

  /**
   * 위경도 좌표 역지오코딩 (Google Geocoder 우선 -> Nominatim 폴백)
   * @param {number} lat - 위도
   * @param {number} lng - 경도
   * @returns {Promise<{name: string, displayName: string, lat: number, lng: number}>}
   */
  async function reverseGeocode(lat, lng) {
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (isNaN(latitude) || isNaN(longitude)) {
      throw new Error('Invalid coordinates for reverse geocoding');
    }

    if (isGoogleGeocoderAvailable()) {
      try {
        return await reverseViaGoogle(latitude, longitude);
      } catch (err) {
        console.warn('Google reverse geocode failed, using Nominatim fallback:', err.message);
      }
    }

    try {
      return await reverseViaNominatim(latitude, longitude);
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
   * @param {Function} fn 
   * @param {number} waitMs 
   * @returns {Function}
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
    debounce,
    isGoogleGeocoderAvailable
  };
});
