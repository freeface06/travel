/**
 * @intent Supabase 클라우드 PostgreSQL DB 및 Storage 연동 관리자 모듈
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripSupabase = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const STORAGE_KEY_URL = 'mytriplog_supabase_url';
  const STORAGE_KEY_KEY = 'mytriplog_supabase_anon_key';

  // 프로젝트 기본 내장 Supabase 인프라 연결 정보 (영구 무중단 클라우드 자동 동기화 SSOT)
  const DEFAULT_SUPABASE_URL = 'https://vmmacaxaivpttopqqfeq.supabase.co';
  const DEFAULT_SUPABASE_KEY = 'sb_publishable__rI7DG40RlhkBCN2nAl4vA_Puf6ad9T';

  // 과거 레거시 더미 데이터 식별자 세트
  const DUMMY_ITEM_IDS = new Set([
    'item-001', 'item-002', 'item-003', 'item-004',
    'item-005', 'item-006', 'item-007', 'item-008'
  ]);

  /**
   * @intent Base64 DataURL 문자열을 표준 Blob 객체로 변환
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   * @param {string|Blob} dataUrlOrBlob 
   * @param {string} [defaultType='image/jpeg']
   * @returns {Blob|null}
   */
  function base64ToBlob(dataUrlOrBlob, defaultType = 'image/jpeg') {
    if (!dataUrlOrBlob) return null;
    if (typeof Blob !== 'undefined' && dataUrlOrBlob instanceof Blob) {
      return dataUrlOrBlob;
    }
    if (typeof dataUrlOrBlob !== 'string') return null;

    try {
      const parts = dataUrlOrBlob.split(';base64,');
      let contentType = defaultType;
      let rawBase64 = dataUrlOrBlob;

      if (parts.length === 2) {
        contentType = parts[0].replace(/^data:/, '') || defaultType;
        rawBase64 = parts[1];
      }

      if (typeof atob === 'function' && typeof Blob !== 'undefined') {
        const byteCharacters = atob(rawBase64);
        const byteArrays = [];
        for (let offset = 0; offset < byteCharacters.length; offset += 512) {
          const slice = byteCharacters.slice(offset, offset + 512);
          const byteNumbers = new Array(slice.length);
          for (let i = 0; i < slice.length; i++) {
            byteNumbers[i] = slice.charCodeAt(i);
          }
          byteArrays.push(new Uint8Array(byteNumbers));
        }
        return new Blob(byteArrays, { type: contentType });
      } else if (typeof Buffer !== 'undefined' && typeof Blob !== 'undefined') {
        const buffer = Buffer.from(rawBase64, 'base64');
        return new Blob([buffer], { type: contentType });
      }
    } catch (e) {
      console.error('base64ToBlob conversion error:', e);
    }
    return null;
  }

  /**
   * @intent Supabase PostgreSQL DB 및 Storage 클라이언트 라이프사이클 관리자
   * @agent  Gemini/manager-develop
   * @branch feat/mytriplog-core
   * @author @developer_name
   * @date   2026-09-29
   */
  class SupabaseClientManager {
    constructor() {
      this.client = null;
      this.syncState = 'synced'; // 'idle' | 'syncing' | 'synced' | 'error'
      this.syncMessage = '클라우드 자동 저장됨';
      this.stateListeners = [];
    }

    /**
     * @intent 동기화 상태 변경 구독 리스너 등록
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {function({ state: string, message: string }): void} listener 
     * @returns {function(): void} 구독 해제 콜백
     */
    onSyncStateChange(listener) {
      if (typeof listener === 'function') {
        this.stateListeners.push(listener);
        try {
          listener({ state: this.syncState, message: this.syncMessage });
        } catch (e) {
          console.error('Initial sync state listener error:', e);
        }
      }
      return () => {
        this.stateListeners = this.stateListeners.filter((l) => l !== listener);
      };
    }

    /**
     * @intent 동기화 상태 갱신 및 구독자 전원 통지
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {'idle'|'syncing'|'synced'|'error'} state 
     * @param {string} [message] 
     */
    setSyncState(state, message = '') {
      this.syncState = state;
      if (message) {
        this.syncMessage = message;
      } else if (state === 'syncing') {
        this.syncMessage = '클라우드 동기화 중...';
      } else if (state === 'synced') {
        this.syncMessage = '클라우드 자동 저장됨';
      } else if (state === 'error') {
        this.syncMessage = '동기화 일시 오류 (오프라인 모드)';
      }
      const payload = { state: this.syncState, message: this.syncMessage };
      this.stateListeners.forEach((fn) => {
        try {
          fn(payload);
        } catch (err) {
          console.error('Error in syncState listener:', err);
        }
      });
    }

    /**
     * @intent 현재 동기화 상태 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {{ state: string, message: string }}
     */
    getSyncState() {
      return { state: this.syncState, message: this.syncMessage };
    }

    /**
     * @intent 로컬스토리지 또는 프로젝트 기본 내장 설정에서 Supabase 연결 설정 로드
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {{ url: string, anonKey: string }}
     */
    getConfig() {
      let userUrl = '';
      let userKey = '';
      if (typeof localStorage !== 'undefined') {
        userUrl = (localStorage.getItem(STORAGE_KEY_URL) || '').trim();
        userKey = (localStorage.getItem(STORAGE_KEY_KEY) || '').trim();
      }
      return {
        url: userUrl || DEFAULT_SUPABASE_URL,
        anonKey: userKey || DEFAULT_SUPABASE_KEY
      };
    }

    /**
     * @intent Supabase 연결 설정 저장 및 인스턴스 초기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string} url - Supabase Project URL
     * @param {string} anonKey - Supabase anon public API key
     * @returns {{ url: string, anonKey: string }}
     */
    saveConfig(url, anonKey) {
      const cleanUrl = String(url || '').trim();
      const cleanKey = String(anonKey || '').trim();

      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(STORAGE_KEY_URL, cleanUrl);
        localStorage.setItem(STORAGE_KEY_KEY, cleanKey);
      }

      this.client = null;
      if (cleanUrl && cleanKey) {
        this.getClient();
      }
      return { url: cleanUrl, anonKey: cleanKey };
    }

    /**
     * @intent Supabase 설정 제거 및 클라이언트 초기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     */
    clearConfig() {
      if (typeof localStorage !== 'undefined') {
        localStorage.removeItem(STORAGE_KEY_URL);
        localStorage.removeItem(STORAGE_KEY_KEY);
      }
      this.client = null;
    }

    /**
     * @intent 유효한 Supabase 설정이 구성되어 있는지 확인 (기본 내장 키 포함)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {boolean}
     */
    isConfigured() {
      const { url, anonKey } = this.getConfig();
      return Boolean(url && anonKey && url.startsWith('http'));
    }

    /**
     * @intent 단일 여행 계획을 백그라운드로 안전하게 클라우드 동기화하고 상태 배지 통지
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object} trip 
     * @returns {Promise<{ ok: boolean, error?: string, data?: any }>}
     */
    async autoSyncTrip(trip) {
      if (!trip || !trip.metadata || !trip.metadata.id) {
        return { ok: false, error: '유효한 여행 데이터가 아닙니다.' };
      }
      this.setSyncState('syncing', '클라우드 자동 저장 중...');
      try {
        const result = await this.syncTrip(trip);
        if (result && result.ok) {
          this.setSyncState('synced', '클라우드 자동 저장됨');
        } else {
          this.setSyncState('error', '클라우드 동기화 실패 (로컬 안전 보관)');
        }
        return result;
      } catch (err) {
        this.setSyncState('error', '클라우드 연결 오류 (로컬 안전 보관)');
        return { ok: false, error: err.message };
      }
    }

    /**
     * @intent 앱 구동 시 클라우드에서 여행 데이터를 자동 조회하여 복원하거나 초기 Seed 백업 실행
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object} storeInstance - TripStore 인스턴스
     * @returns {Promise<{ action: string, count: number, trips?: Array<object>, error?: string }>}
     */
    async autoFetchAndRestore(storeInstance) {
      if (!this.isConfigured()) {
        return { action: 'unconfigured', count: 0 };
      }

      this.setSyncState('syncing', '클라우드 동기화 확인 중...');
      try {
        const cloudTrips = await this.fetchTrips();
        if (Array.isArray(cloudTrips) && cloudTrips.length > 0) {
          // 클라우드 데이터 중 과거 더미(id: 'trip-honeymoon-2026' 또는 더미 아이템 포함 레거시) 감지 시 정제 및 클라우드 재동기화
          let cleanedAny = false;
          for (const trip of cloudTrips) {
            if (!trip || !trip.metadata) continue;
            const isDummyTrip = trip.metadata.id === 'trip-honeymoon-2026' ||
              trip.metadata.title === '우리의 로맨틱 신혼여행' ||
              trip.metadata.title === '도쿄 3박 4일 감성 힐링 여행';
            const hasDummyItems = Array.isArray(trip.items) && trip.items.some((it) => it && (DUMMY_ITEM_IDS.has(it.id) || (typeof it.title === 'string' && (it.title.includes('에어서울 RS701') || it.title.includes('나리타 국제공항')))));

            if (isDummyTrip || hasDummyItems) {
              if (isDummyTrip) {
                trip.metadata.id = 'trip-my-first-trip';
                trip.metadata.title = '나의 여행 계획';
                trip.metadata.startDate = '';
                trip.metadata.endDate = '';
                trip.items = [];
              } else if (hasDummyItems) {
                trip.items = trip.items.filter((it) => it && !DUMMY_ITEM_IDS.has(it.id) && !(typeof it.title === 'string' && (it.title.includes('에어서울 RS701') || it.title.includes('나리타 국제공항'))));
              }
              await this.syncTrip(trip);
              if (isDummyTrip) {
                await this.deleteTrip('trip-honeymoon-2026').catch(() => {});
              }
              cleanedAny = true;
            }
          }

          if (storeInstance && typeof storeInstance.importFromCloud === 'function') {
            await storeInstance.importFromCloud();
          }
          this.setSyncState('synced', cleanedAny ? '클라우드 더미 정리 및 데이터 복원 완료' : '클라우드 데이터 자동 복원됨');
          return { action: 'imported', count: cloudTrips.length, trips: cloudTrips };
        } else {
          // 클라우드가 비어있고 로컬에 기존 여행 계획이 있다면 클라우드로 즉시 1회 자동 업로드(Seed)
          if (storeInstance && typeof storeInstance.getTrips === 'function') {
            const localTrips = storeInstance.getTrips();
            if (Array.isArray(localTrips) && localTrips.length > 0 && typeof storeInstance.syncAllToCloud === 'function') {
              const count = await storeInstance.syncAllToCloud();
              this.setSyncState('synced', '클라우드 초기 백업 완료');
              return { action: 'seeded', count };
            }
          }
          this.setSyncState('synced', '클라우드 연동 준비 완료');
          return { action: 'idle', count: 0 };
        }
      } catch (err) {
        console.warn('autoFetchAndRestore exception:', err);
        this.setSyncState('error', '동기화 일시 오류 (오프라인 모드)');
        return { action: 'error', error: err.message, count: 0 };
      }
    }

    /**
     * @intent 테스트 및 모킹용 클라이언트 직접 주입
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object|null} mockClient 
     */
    setClient(mockClient) {
      this.client = mockClient;
    }

    /**
     * @intent Supabase 클라이언트 인스턴스 반환 (캐싱 및 지연 초기화)
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {object|null}
     */
    getClient() {
      if (this.client) {
        return this.client;
      }

      if (!this.isConfigured()) {
        return null;
      }

      const { url, anonKey } = this.getConfig();
      const createClientFn =
        (typeof window !== 'undefined' && window.supabase && window.supabase.createClient) ||
        (typeof global !== 'undefined' && global.supabase && global.supabase.createClient) ||
        null;

      if (typeof createClientFn === 'function') {
        try {
          this.client = createClientFn(url, anonKey, {
            auth: {
              persistSession: false,
              autoRefreshToken: false
            }
          });
          return this.client;
        } catch (err) {
          console.error('Failed to create Supabase client:', err);
          return null;
        }
      }

      return null;
    }

    /**
     * @intent Supabase 연결 및 trips 테이블 조회 가능 여부 검증
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Promise<{ ok: boolean, error?: string }>}
     */
    async testConnection() {
      if (!this.isConfigured()) {
        return { ok: false, error: 'Supabase URL과 Anon API Key가 설정되지 않았습니다.' };
      }

      const client = this.getClient();
      if (!client) {
        return { ok: false, error: 'Supabase 라이브러리가 로드되지 않았거나 초기화에 실패했습니다.' };
      }

      try {
        const { data, error } = await client.from('trips').select('id').limit(1);
        if (error) {
          return { ok: false, error: error.message || '데이터베이스 테이블 조회 실패' };
        }
        return { ok: true, data };
      } catch (err) {
        return { ok: false, error: err.message || 'Supabase 연결 중 네트워크 오류가 발생했습니다.' };
      }
    }

    /**
     * @intent 단일 여행 계획을 Supabase trips 테이블에 upsert 동기화
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {object} trip - 동기화 대상 여행 계획 객체
     * @returns {Promise<{ ok: boolean, error?: string, data?: any }>}
     */
    async syncTrip(trip) {
      if (!trip || !trip.metadata || !trip.metadata.id) {
        return { ok: false, error: '유효한 여행 데이터가 아닙니다.' };
      }

      if (!this.isConfigured()) {
        return { ok: false, error: 'Supabase 미설정 상태입니다.' };
      }

      const client = this.getClient();
      if (!client) {
        return { ok: false, error: 'Supabase 클라이언트를 사용할 수 없습니다.' };
      }

      try {
        const record = {
          id: trip.metadata.id,
          title: trip.metadata.title || '새 여행 계획',
          start_date: trip.metadata.startDate || '',
          end_date: trip.metadata.endDate || '',
          base_currency: trip.metadata.baseCurrency || 'KRW',
          data: trip,
          updated_at: new Date().toISOString()
        };

        const { data, error } = await client.from('trips').upsert(record, { onConflict: 'id' });
        if (error) {
          console.error('Supabase syncTrip error:', error);
          return { ok: false, error: error.message };
        }
        return { ok: true, data };
      } catch (err) {
        console.error('Supabase syncTrip exception:', err);
        return { ok: false, error: err.message };
      }
    }

    /**
     * @intent Supabase trips 테이블에서 특정 여행 계획 삭제
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string} tripId - 삭제 대상 여행 ID
     * @returns {Promise<{ ok: boolean, error?: string }>}
     */
    async deleteTrip(tripId) {
      if (!tripId) return { ok: false, error: 'tripId가 지정되지 않았습니다.' };
      if (!this.isConfigured()) return { ok: false, error: 'Supabase 미설정 상태입니다.' };

      const client = this.getClient();
      if (!client) return { ok: false, error: 'Supabase 클라이언트를 사용할 수 없습니다.' };

      try {
        const { error } = await client.from('trips').delete().eq('id', tripId);
        if (error) {
          console.error('Supabase deleteTrip error:', error);
          return { ok: false, error: error.message };
        }
        return { ok: true };
      } catch (err) {
        console.error('Supabase deleteTrip exception:', err);
        return { ok: false, error: err.message };
      }
    }

    /**
     * @intent Supabase trips 테이블에서 전체 여행 계획 목록 조회
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {Promise<Array<object>>} 복원된 여행 객체 배열
     */
    async fetchTrips() {
      if (!this.isConfigured()) return [];

      const client = this.getClient();
      if (!client) return [];

      try {
        const { data, error } = await client.from('trips').select('*').order('updated_at', { ascending: false });
        if (error) {
          console.error('Supabase fetchTrips error:', error);
          return [];
        }
        if (!Array.isArray(data)) return [];
        return data.map((row) => row.data).filter((item) => Boolean(item && item.metadata));
      } catch (err) {
        console.error('Supabase fetchTrips exception:', err);
        return [];
      }
    }

    /**
     * @intent 첨부 사진을 Supabase Storage 버킷('trip-photos')에 업로드하고 영구 CDN 공개 URL 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @param {string|Blob} blobOrDataUrl - 업로드할 사진 데이터
     * @param {string} [filename='photo.jpg'] - 원본 파일명
     * @returns {Promise<string|null>} CDN 공개 URL 또는 실패 시 null
     */
    async uploadPhoto(blobOrDataUrl, filename = 'photo.jpg') {
      if (!this.isConfigured()) return null;

      const client = this.getClient();
      if (!client || !client.storage) return null;

      try {
        const blob = base64ToBlob(blobOrDataUrl);
        if (!blob) return null;

        const ext = (filename && filename.includes('.')) ? filename.split('.').pop().toLowerCase() : 'jpg';
        const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext) ? ext : 'jpg';
        const randomStr = Math.random().toString(36).substring(2, 8);
        const path = `trip-photos/${Date.now()}_${randomStr}.${safeExt}`;
        const mimeType = blob.type || (safeExt === 'png' ? 'image/png' : safeExt === 'webp' ? 'image/webp' : 'image/jpeg');

        const { data: uploadData, error: uploadErr } = await client.storage
          .from('trip-photos')
          .upload(path, blob, {
            contentType: mimeType,
            upsert: true
          });

        if (uploadErr) {
          console.error('Supabase uploadPhoto storage error:', uploadErr);
          return null;
        }

        const { data: publicUrlData } = client.storage.from('trip-photos').getPublicUrl(path);
        return (publicUrlData && publicUrlData.publicUrl) ? publicUrlData.publicUrl : null;
      } catch (err) {
        console.error('Supabase uploadPhoto exception:', err);
        return null;
      }
    }

    /**
     * @intent Supabase 대시보드 SQL Editor에 붙여넣을 표준 테이블 및 스토리지 버킷 원클릭 DDL 스크립트 반환
     * @agent  Gemini/manager-develop
     * @branch feat/mytriplog-core
     * @author @developer_name
     * @date   2026-09-29
     * @returns {string} SQL DDL
     */
    getSetupSqlScript() {
      return [
        '-- 1. 여행 계획 테이블 생성',
        'CREATE TABLE IF NOT EXISTS public.trips (',
        '  id TEXT PRIMARY KEY,',
        '  title TEXT NOT NULL,',
        '  start_date TEXT,',
        '  end_date TEXT,',
        '  base_currency TEXT DEFAULT \'KRW\',',
        '  data JSONB NOT NULL,',
        '  updated_at TIMESTAMPTZ DEFAULT timezone(\'utc\'::text, now()) NOT NULL',
        ');',
        '',
        '-- 2. RLS 활성화 및 익명(anon) 접근 정책 허용',
        'ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;',
        'CREATE POLICY "Public trips access" ON public.trips FOR ALL USING (true) WITH CHECK (true);',
        '',
        '-- 3. 사진 보관 스토리지 버킷 생성 및 공개 접근 허용',
        'INSERT INTO storage.buckets (id, name, public)',
        'VALUES (\'trip-photos\', \'trip-photos\', true)',
        'ON CONFLICT (id) DO UPDATE SET public = true;',
        '',
        'CREATE POLICY "Public photos access" ON storage.objects FOR ALL USING (bucket_id = \'trip-photos\') WITH CHECK (bucket_id = \'trip-photos\');'
      ].join('\n');
    }
  }

  const supabaseManager = new SupabaseClientManager();

  return {
    SupabaseClientManager,
    supabaseManager,
    DEFAULT_SUPABASE_URL,
    DEFAULT_SUPABASE_KEY,
    STORAGE_KEY_URL,
    STORAGE_KEY_KEY,
    base64ToBlob
  };
});
