-- Migration: 007_shifts_and_attendance_schema.sql
-- Description: Creates shifts and attendance tables for tracking real cashier shifts, opening floats, and daily attendance.

-- ----------------------------------------------------------------------------
-- 1. TABLES DEFINITIONS
-- ----------------------------------------------------------------------------

-- SHIFTS
CREATE TABLE IF NOT EXISTS public.shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    opening_float NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (opening_float >= 0),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended', 'not_started')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger for shifts updated_at
DROP TRIGGER IF EXISTS update_shifts_updated_at ON public.shifts;
CREATE TRIGGER update_shifts_updated_at
    BEFORE UPDATE ON public.shifts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ATTENDANCE
CREATE TABLE IF NOT EXISTS public.attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reporting_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'absent', 'late', 'not_recorded')),
    work_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_employee_work_date UNIQUE (employee_id, work_date)
);

-- ----------------------------------------------------------------------------
-- 2. INDEXES
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_shifts_business ON public.shifts(business_id);
CREATE INDEX IF NOT EXISTS idx_shifts_employee ON public.shifts(employee_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON public.shifts(status);
CREATE INDEX IF NOT EXISTS idx_shifts_start_time ON public.shifts(start_time DESC);

CREATE INDEX IF NOT EXISTS idx_attendance_business ON public.attendance(business_id);
CREATE INDEX IF NOT EXISTS idx_attendance_employee ON public.attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_work_date ON public.attendance(work_date);

-- ----------------------------------------------------------------------------
-- 3. ENABLE ROW LEVEL SECURITY (RLS)
-- ----------------------------------------------------------------------------

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4. RLS POLICIES FOR SHIFTS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "Cashiers view own shifts, admins view store shifts" ON public.shifts;
CREATE POLICY "Cashiers view own shifts, admins view store shifts" ON public.shifts
    FOR SELECT USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Cashiers create own shifts" ON public.shifts;
CREATE POLICY "Cashiers create own shifts" ON public.shifts
    FOR INSERT WITH CHECK (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers update own shifts, admins update store shifts" ON public.shifts;
CREATE POLICY "Cashiers update own shifts, admins update store shifts" ON public.shifts
    FOR UPDATE USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    ) WITH CHECK (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );

-- ----------------------------------------------------------------------------
-- 5. RLS POLICIES FOR ATTENDANCE
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "Cashiers view own attendance, admins view store attendance" ON public.attendance;
CREATE POLICY "Cashiers view own attendance, admins view store attendance" ON public.attendance
    FOR SELECT USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Cashiers insert own attendance" ON public.attendance;
CREATE POLICY "Cashiers insert own attendance" ON public.attendance
    FOR INSERT WITH CHECK (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers update own attendance, admins update store attendance" ON public.attendance;
CREATE POLICY "Cashiers update own attendance, admins update store attendance" ON public.attendance
    FOR UPDATE USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    ) WITH CHECK (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );
