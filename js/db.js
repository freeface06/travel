/**
 * @intent 클라이언트 사이드 이미지 리사이징 및 IndexedDB 대용량 미디어 스토리지 엔진
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripDB = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DB_NAME = 'MyTripLogDB';
  const DB_VERSION = 1;
  const STORE_PHOTOS = 'photos';

  let dbInstance = null;

  /**
   * IndexedDB 연결 초기화
   * @returns {Promise<IDBDatabase>}
   */
  function initDB() {
    return new Promise((resolve, reject) => {
      if (dbInstance) {
        return resolve(dbInstance);
      }
      if (typeof indexedDB === 'undefined') {
        return reject(new Error('IndexedDB is not supported in this environment'));
      }

      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onupgradeneeded = function (e) {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(STORE_PHOTOS)) {
          db.createObjectStore(STORE_PHOTOS, { keyPath: 'id' });
        }
      };

      request.onsuccess = function (e) {
        dbInstance = e.target.result;
        resolve(dbInstance);
      };

      request.onerror = function (e) {
        reject(e.target.error);
      };
    });
  }

  /**
   * 클라이언트 측 Canvas 기반 이미지 리사이징 및 압축
   * @param {File|Blob} file 
   * @param {number} maxWidth 
   * @param {number} quality 
   * @returns {Promise<{dataUrl: string, width: number, height: number, mimeType: string}>}
   */
  function resizeImage(file, maxWidth = 1200, quality = 0.75) {
    return new Promise((resolve, reject) => {
      if (typeof Image === 'undefined' || typeof document === 'undefined') {
        return reject(new Error('Canvas/Image is not available in non-browser environment'));
      }

      const reader = new FileReader();
      reader.onload = function (e) {
        const img = new Image();
        img.onload = function () {
          let { width, height } = img;
          if (width > maxWidth) {
            height = Math.round((height * maxWidth) / width);
            width = maxWidth;
          }

          const canvas = document.createElement('canvas');
          canvas.width = width;
          canvas.height = height;

          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, width, height);

          // 브라우저가 WebP를 지원하면 image/webp, 아니면 image/jpeg 사용
          let mimeType = 'image/jpeg';
          try {
            const testCanvas = document.createElement('canvas');
            if (testCanvas.toDataURL('image/webp').indexOf('data:image/webp') === 0) {
              mimeType = 'image/webp';
            }
          } catch (err) {
            mimeType = 'image/jpeg';
          }

          const dataUrl = canvas.toDataURL(mimeType, quality);
          resolve({
            dataUrl,
            width,
            height,
            mimeType
          });
        };
        img.onerror = function () {
          reject(new Error('Failed to load image file'));
        };
        img.src = e.target.result;
      };
      reader.onerror = function () {
        reject(new Error('Failed to read file buffer'));
      };
      reader.readAsDataURL(file);
    });
  }

  /**
   * 사진 객체 저장
   * @param {string} id 
   * @param {string} dataUrl 
   * @param {string} filename 
   * @returns {Promise<string>}
   */
  async function savePhoto(id, dataUrl, filename = 'photo') {
    const db = await initDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_PHOTOS, 'readwrite');
      const store = tx.objectStore(STORE_PHOTOS);
      const record = {
        id,
        filename,
        dataUrl,
        createdAt: new Date().toISOString()
      };
      const req = store.put(record);
      req.onsuccess = () => resolve(id);
      req.onerror = () => reject(req.error);
    });
  }

  /**
   * 사진 조회
   * @param {string} id 
   * @returns {Promise<object|null>}
   */
  async function getPhoto(id) {
    const db = await initDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_PHOTOS, 'readonly');
      const store = tx.objectStore(STORE_PHOTOS);
      const req = store.get(id);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
  }

  /**
   * 사진 삭제
   * @param {string} id 
   * @returns {Promise<boolean>}
   */
  async function deletePhoto(id) {
    const db = await initDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_PHOTOS, 'readwrite');
      const store = tx.objectStore(STORE_PHOTOS);
      const req = store.delete(id);
      req.onsuccess = () => resolve(true);
      req.onerror = () => reject(req.error);
    });
  }

  /**
   * 전체 사진 목록 조회 (ID 기준)
   * @returns {Promise<Array<object>>}
   */
  async function getAllPhotos() {
    const db = await initDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_PHOTOS, 'readonly');
      const store = tx.objectStore(STORE_PHOTOS);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
  }

  return {
    initDB,
    resizeImage,
    savePhoto,
    getPhoto,
    deletePhoto,
    getAllPhotos
  };
});
