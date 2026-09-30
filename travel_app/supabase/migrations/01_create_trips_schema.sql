-- @intent Supabase trips, trip_members, trip_items 테이블 정의 및 다중 사용자 격리 RLS 보안 정책 마이그레이션
-- @agent Gemini/manager-develop
-- @branch feat/v2.0.0-commercial
-- @author @developer_name
-- @date 2026-09-30

-- 1. 여행 메타데이터 및 전체 스냅샷 테이블
CREATE TABLE IF NOT EXISTS public.trips (
    id TEXT PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    base_currency TEXT DEFAULT 'KRW',
    data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 여행 멤버/공유 협업자 테이블
CREATE TABLE IF NOT EXISTS public.trip_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_trip_member UNIQUE (trip_id, user_id)
);

-- 3. 여행 상세 일정 아이템 테이블 (대안 플랜/슬롯 그룹핑 호환)
CREATE TABLE IF NOT EXISTS public.trip_items (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    day INTEGER NOT NULL DEFAULT 1,
    slot_group_id TEXT,
    candidate_label INTEGER DEFAULT 1,
    is_selected BOOLEAN DEFAULT TRUE,
    title TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'ATTRACTION',
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    address TEXT,
    time TEXT,
    cost DOUBLE PRECISION DEFAULT 0,
    currency TEXT DEFAULT 'KRW',
    data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. 인덱스 최적화
CREATE INDEX IF NOT EXISTS idx_trips_owner_id ON public.trips(owner_id);
CREATE INDEX IF NOT EXISTS idx_trips_updated_at ON public.trips(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_trip_members_user_id ON public.trip_members(user_id);
CREATE INDEX IF NOT EXISTS idx_trip_members_trip_id ON public.trip_members(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_items_trip_id ON public.trip_items(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_items_slot ON public.trip_items(trip_id, slot_group_id);

-- 5. Row Level Security (RLS) 활성화
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_items ENABLE ROW LEVEL SECURITY;

-- 6. trips RLS 정책
DROP POLICY IF EXISTS "Trips select policy" ON public.trips;
CREATE POLICY "Trips select policy" ON public.trips
    FOR SELECT
    USING (
        owner_id = auth.uid()
        OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Trips insert policy" ON public.trips;
CREATE POLICY "Trips insert policy" ON public.trips
    FOR INSERT
    WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Trips update policy" ON public.trips;
CREATE POLICY "Trips update policy" ON public.trips
    FOR UPDATE
    USING (
        owner_id = auth.uid()
        OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid() AND role IN ('owner', 'editor'))
    );

DROP POLICY IF EXISTS "Trips delete policy" ON public.trips;
CREATE POLICY "Trips delete policy" ON public.trips
    FOR DELETE
    USING (owner_id = auth.uid());

-- 7. trip_members RLS 정책
DROP POLICY IF EXISTS "Trip members select policy" ON public.trip_members;
CREATE POLICY "Trip members select policy" ON public.trip_members
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR trip_id IN (SELECT id FROM public.trips WHERE owner_id = auth.uid())
    );

DROP POLICY IF EXISTS "Trip members insert policy" ON public.trip_members;
CREATE POLICY "Trip members insert policy" ON public.trip_members
    FOR INSERT
    WITH CHECK (
        trip_id IN (SELECT id FROM public.trips WHERE owner_id = auth.uid())
    );

DROP POLICY IF EXISTS "Trip members delete policy" ON public.trip_members;
CREATE POLICY "Trip members delete policy" ON public.trip_members
    FOR DELETE
    USING (
        trip_id IN (SELECT id FROM public.trips WHERE owner_id = auth.uid())
    );

-- 8. trip_items RLS 정책
DROP POLICY IF EXISTS "Trip items select policy" ON public.trip_items;
CREATE POLICY "Trip items select policy" ON public.trip_items
    FOR SELECT
    USING (
        trip_id IN (
            SELECT id FROM public.trips 
            WHERE owner_id = auth.uid() 
            OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Trip items insert policy" ON public.trip_items;
CREATE POLICY "Trip items insert policy" ON public.trip_items
    FOR INSERT
    WITH CHECK (
        trip_id IN (
            SELECT id FROM public.trips 
            WHERE owner_id = auth.uid() 
            OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid() AND role IN ('owner', 'editor'))
        )
    );

DROP POLICY IF EXISTS "Trip items update policy" ON public.trip_items;
CREATE POLICY "Trip items update policy" ON public.trip_items
    FOR UPDATE
    USING (
        trip_id IN (
            SELECT id FROM public.trips 
            WHERE owner_id = auth.uid() 
            OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid() AND role IN ('owner', 'editor'))
        )
    );

DROP POLICY IF EXISTS "Trip items delete policy" ON public.trip_items;
CREATE POLICY "Trip items delete policy" ON public.trip_items
    FOR DELETE
    USING (
        trip_id IN (
            SELECT id FROM public.trips 
            WHERE owner_id = auth.uid() 
            OR id IN (SELECT trip_id FROM public.trip_members WHERE user_id = auth.uid() AND role IN ('owner', 'editor'))
        )
    );
