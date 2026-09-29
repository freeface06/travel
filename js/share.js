/**
 * @intent lz-string 기반 URL Hash 무서버 일정 압축 공유 및 JSON 백업 내보내기/가져오기 엔진
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripShare = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * 전역 또는 모듈 LZString 라이브러리 참조 획득
   */
  function getLZString() {
    if (typeof LZString !== 'undefined') {
      return LZString;
    }
    if (typeof window !== 'undefined' && window.LZString) {
      return window.LZString;
    }
    return null;
  }

  /**
   * 공유를 위한 데이터 경량화 (대용량 사진 Base64는 URL 길이 한계로 제외)
   * @param {object} tripData 
   * @returns {object}
   */
  function sanitizeForSharing(tripData) {
    if (!tripData) return {};
    const sanitized = JSON.parse(JSON.stringify(tripData));
    if (Array.isArray(sanitized.items)) {
      sanitized.items = sanitized.items.map((item) => {
        const itemCopy = Object.assign({}, item);
        delete itemCopy.photoDataUrl; // 사진 본문 데이터 제거 (photoId만 보존)
        return itemCopy;
      });
    }
    return sanitized;
  }

  /**
   * 여행 데이터를 압축하여 공유용 전체 URL 생성
   * @param {object} tripData 
   * @param {string} baseUrl 
   * @returns {string} 완성된 공유 URL
   */
  function generateShareUrl(tripData, baseUrl = '') {
    const lz = getLZString();
    const lightweight = sanitizeForSharing(tripData);
    const jsonStr = JSON.stringify(lightweight);

    let hashPayload = '';
    if (lz && typeof lz.compressToEncodedURIComponent === 'function') {
      hashPayload = 'lz=' + lz.compressToEncodedURIComponent(jsonStr);
    } else {
      // LZString 미로드 시 base64 fallback
      if (typeof btoa !== 'undefined') {
        hashPayload = 'b64=' + encodeURIComponent(btoa(unescape(encodeURIComponent(jsonStr))));
      } else {
        hashPayload = 'raw=' + encodeURIComponent(jsonStr);
      }
    }

    const base = baseUrl || (typeof window !== 'undefined' ? window.location.origin + window.location.pathname : '');
    return `${base}#${hashPayload}`;
  }

  /**
   * URL Hash로부터 여행 데이터 복원
   * @param {string} hash - window.location.hash 문자열
   * @returns {object|null} 복원된 여행 객체
   */
  function parseShareHash(hash) {
    if (!hash) return null;
    const cleanHash = hash.startsWith('#') ? hash.slice(1) : hash;
    if (!cleanHash) return null;

    const lz = getLZString();

    try {
      if (cleanHash.startsWith('lz=')) {
        const compressed = cleanHash.slice(3);
        if (lz && typeof lz.decompressFromEncodedURIComponent === 'function') {
          const decompressed = lz.decompressFromEncodedURIComponent(compressed);
          if (decompressed) {
            return JSON.parse(decompressed);
          }
        }
      } else if (cleanHash.startsWith('b64=')) {
        const b64Data = decodeURIComponent(cleanHash.slice(4));
        if (typeof atob !== 'undefined') {
          const jsonStr = decodeURIComponent(escape(atob(b64Data)));
          return JSON.parse(jsonStr);
        }
      } else if (cleanHash.startsWith('raw=')) {
        const jsonStr = decodeURIComponent(cleanHash.slice(4));
        return JSON.parse(jsonStr);
      }
    } catch (e) {
      console.warn('Failed to parse share hash:', e);
    }
    return null;
  }

  /**
   * 전체 여행 데이터를 .json 파일로 다운로드 내보내기
   * @param {object} tripData 
   * @param {string} filename 
   */
  function exportTripAsJson(tripData, filename = null) {
    if (typeof document === 'undefined') return;

    const title = (tripData.metadata && tripData.metadata.title) || 'mytriplog';
    const cleanTitle = title.replace(/[^a-zA-Z0-9가-힣_-]/g, '_');
    const actualFilename = filename || `${cleanTitle}_backup.json`;

    const blob = new Blob([JSON.stringify(tripData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = actualFilename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  /**
   * JSON 파일 읽기 및 객체 파싱
   * @param {File} file 
   * @returns {Promise<object>}
   */
  function importTripFromJsonFile(file) {
    return new Promise((resolve, reject) => {
      if (!file) {
        return reject(new Error('선택된 파일이 없습니다.'));
      }
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const parsed = JSON.parse(e.target.result);
          if (!parsed.metadata || !Array.isArray(parsed.items)) {
            throw new Error('유효한 MyTripLog 데이터 형식이 아닙니다.');
          }
          resolve(parsed);
        } catch (err) {
          reject(new Error('JSON 파일 구문 분석 실패: ' + err.message));
        }
      };
      reader.onerror = () => reject(new Error('파일 읽기 실패'));
      reader.readAsText(file);
    });
  }

  /**
   * 클립보드 복사 헬퍼
   * @param {string} text 
   * @returns {Promise<boolean>}
   */
  async function copyToClipboard(text) {
    if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (e) {
        console.warn('Clipboard API failed, trying execCommand fallback:', e);
      }
    }

    if (typeof document !== 'undefined') {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      const success = document.execCommand('copy');
      document.body.removeChild(textarea);
      return success;
    }

    return false;
  }

  return {
    sanitizeForSharing,
    generateShareUrl,
    parseShareHash,
    exportTripAsJson,
    importTripFromJsonFile,
    copyToClipboard
  };
});
