/**
 * @intent Google Places 및 Geocoder API 기반 장소 검색/자동완성 및 OpenStreetMap Nominatim 폴백 지오코딩 엔진
 *         - Google Places AutocompleteService를 활용한 초고속 실시간 장소 검색
 *         - Geocoder를 통한 placeId 기반 위도/경도(lat/lng) 정밀 좌표 변환
 *         - API 장애 또는 오프라인 시 OpenStreetMap Nominatim으로 무오류 안전 폴백
 *         - 한국어(ko-KR) 표기 강제 적용
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
   * @intent Google Places API 사용 가능 여부 판별
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @returns {boolean}
   */
  function isGooglePlacesAvailable() {
    return Boolean(
      typeof window !== 'undefined' &&
      window.google &&
      window.google.maps &&
      window.google.maps.places
    );
  }

  /**
   * @intent Google Geocoder 서비스 사용 가능 여부 판별
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
   * @intent Google Places AutocompleteService를 통한 실시간 장소 자동완성 검색
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} query - 검색어
   * @param {number} limit - 최대 반환 건수
   * @returns {Promise<Array<{placeId: string, name: string, displayName: string, secondaryText: string, lat: number|null, lng: number|null, type: string}>>}
   */
  function searchPlacesViaGoogle(query, limit = 5) {
    return new Promise((resolve) => {
      try {
        if (!isGooglePlacesAvailable()) {
          return resolve([]);
        }

        const service = new google.maps.places.AutocompleteService();
        service.getPlacePredictions(
          {
            input: query,
            language: 'ko',
            types: ['geocode', 'establishment']
          },
          (predictions, status) => {
            if (
              status === google.maps.places.PlacesServiceStatus.OK &&
              Array.isArray(predictions) &&
              predictions.length > 0
            ) {
              const mapped = predictions.slice(0, limit).map((p) => {
                const sf = p.structured_formatting || {};
                const name = sf.main_text || p.description;
                const secondaryText = sf.secondary_text || '';
                return {
                  placeId: p.place_id,
                  name: name,
                  displayName: p.description,
                  secondaryText: secondaryText,
                  lat: null,
                  lng: null,
                  type: (p.types && p.types[0]) || 'establishment'
                };
              });
              resolve(mapped);
            } else {
              resolve([]);
            }
          }
        );
      } catch (err) {
        console.warn('Google Places search error:', err.message);
        resolve([]);
      }
    });
  }

  /**
   * @intent Google Geocoder를 통한 placeId 기반 정밀 좌표 및 주소 조회
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} placeId - Google Places ID
   * @returns {Promise<{placeId: string, lat: number, lng: number, name: string, displayName: string, raw: object}>}
   */
  function getPlaceCoordinates(placeId) {
    return new Promise((resolve, reject) => {
      if (!placeId) return reject(new Error('Missing placeId'));

      if (isGoogleGeocoderAvailable()) {
        try {
          const geocoder = new google.maps.Geocoder();
          geocoder.geocode({ placeId, language: 'ko', region: 'KR' }, (results, status) => {
            if (status === google.maps.GeocoderStatus.OK && Array.isArray(results) && results[0]) {
              const first = results[0];
              const loc = first.geometry.location;
              const lat = typeof loc.lat === 'function' ? loc.lat() : Number(loc.lat);
              const lng = typeof loc.lng === 'function' ? loc.lng() : Number(loc.lng);
              const name = (first.address_components && first.address_components[0])
                ? first.address_components[0].long_name
                : first.formatted_address;

              resolve({
                placeId,
                lat,
                lng,
                name,
                displayName: first.formatted_address,
                raw: first
              });
            } else {
              reject(new Error(`Google Geocoder failed for placeId: ${status}`));
            }
          });
          return;
        } catch (err) {
          return reject(err);
        }
      }

      reject(new Error('Google Geocoder is not available'));
    });
  }

  /**
   * @intent OpenStreetMap Nominatim을 통한 장소/주소 검색 (Google Places 미지원 시 폴백)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
        placeId: null,
        name: item.display_name.split(',')[0].trim(),
        displayName: item.display_name,
        secondaryText: item.display_name.split(',').slice(1).join(',').trim(),
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
   * @intent 장소/주소 통합 검색 (Google Places 우선 -> OpenStreetMap Nominatim 폴백)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string} query - 검색어
   * @param {number} limit - 최대 반환 건수
   * @returns {Promise<Array<{name: string, displayName: string, lat: number|null, lng: number|null, type: string}>>}
   */
  async function searchPlaces(query, limit = 5) {
    const q = (query || '').trim();
    if (!q || q.length < 2) return [];

    // 1. Google Places 사용 시도
    if (isGooglePlacesAvailable()) {
      try {
        const googleResults = await searchPlacesViaGoogle(q, limit);
        if (googleResults && googleResults.length > 0) {
          return googleResults;
        }
      } catch (e) {
        console.warn('Google Places exception, fallback to Nominatim:', e.message);
      }
    }

    // 2. Nominatim 폴백 검색
    return await searchViaNominatim(q, limit);
  }

  /**
   * @intent Google Geocoder를 통한 역지오코딩
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
   * @intent OpenStreetMap Nominatim을 통한 역지오코딩 (폴백)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
   * @intent 위경도 좌표 역지오코딩 (Google Geocoder 우선 -> Nominatim 폴백)
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
   * @intent 함수 호출 디바운스(Debounce) 헬퍼
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
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
    searchPlacesViaGoogle,
    getPlaceCoordinates,
    searchViaNominatim,
    reverseGeocode,
    reverseViaGoogle,
    reverseViaNominatim,
    debounce,
    isGooglePlacesAvailable,
    isGoogleGeocoderAvailable
  };
});
