-- Migration: 015_held_sales_shifts_and_profile_security.sql
-- Description: Creates held_sales schema, prevents duplicate active shifts via partial unique index on status='open', isolates shift access by business for Admin, and enforces own-profile SELECT and own-name-only UPDATE for non-admins.

-- ----------------------------------------------------------------------------
-- 1. HELD SALES & HELD SALE ITEMS TABLES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.held_sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reference_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'resumed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger for held_sales updated_at
DROP TRIGGER IF EXISTS update_held_sales_updated_at ON public.held_sales;
CREATE TRIGGER update_held_sales_updated_at
    BEFORE UPDATE ON public.held_sales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.held_sale_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    held_sale_id UUID NOT NULL REFERENCES public.held_sales(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    product_name_snapshot TEXT NOT NULL,
    sku_snapshot TEXT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS for held sales
ALTER TABLE public.held_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.held_sale_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies for held_sales
DROP POLICY IF EXISTS "Cashiers can view their own held sales" ON public.held_sales;
CREATE POLICY "Cashiers can view their own held sales" ON public.held_sales
    FOR SELECT USING (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers can create held sales for themselves" ON public.held_sales;
CREATE POLICY "Cashiers can create held sales for themselves" ON public.held_sales
    FOR INSERT WITH CHECK (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers can update their own held sales" ON public.held_sales;
CREATE POLICY "Cashiers can update their own held sales" ON public.held_sales
    FOR UPDATE USING (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    ) WITH CHECK (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers can delete their own held sales" ON public.held_sales;
CREATE POLICY "Cashiers can delete their own held sales" ON public.held_sales
    FOR DELETE USING (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

-- RLS Policies for held_sale_items
DROP POLICY IF EXISTS "Cashiers can view their held sale items" ON public.held_sale_items;
CREATE POLICY "Cashiers can view their held sale items" ON public.held_sale_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.held_sales hs
            WHERE hs.id = held_sale_items.held_sale_id
              AND hs.business_id = public.get_user_business_id()
              AND hs.employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Cashiers can insert their held sale items" ON public.held_sale_items;
CREATE POLICY "Cashiers can insert their held sale items" ON public.held_sale_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.held_sales hs
            WHERE hs.id = held_sale_items.held_sale_id
              AND hs.business_id = public.get_user_business_id()
              AND hs.employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Cashiers can delete their held sale items" ON public.held_sale_items;
CREATE POLICY "Cashiers can delete their held sale items" ON public.held_sale_items
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM public.held_sales hs
            WHERE hs.id = held_sale_items.held_sale_id
              AND hs.business_id = public.get_user_business_id()
              AND hs.employee_id = auth.uid()
        )
    );

-- ----------------------------------------------------------------------------
-- 2. PREVENT DUPLICATE ACTIVE SHIFTS (PARTIAL UNIQUE INDEX FOR STATUS='OPEN')
-- ----------------------------------------------------------------------------

DROP INDEX IF EXISTS public.idx_one_active_shift_per_employee;
CREATE UNIQUE INDEX idx_one_active_shift_per_employee
ON public.shifts (employee_id)
WHERE (status = 'open');

-- ----------------------------------------------------------------------------
-- 3. SHIFTS TABLE RLS (BUSINESS ISOLATED FOR ADMIN, OWN SHIFTS ONLY FOR CASHIER)
-- ----------------------------------------------------------------------------

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cashiers view own shifts, admins view store shifts" ON public.shifts;
DROP POLICY IF EXISTS "Shifts select policy" ON public.shifts;
CREATE POLICY "Shifts select policy" ON public.shifts
    FOR SELECT USING (
        employee_id = auth.uid()
        OR (
            public.is_admin()
            AND EXISTS (
                SELECT 1 FROM public.employees e
                WHERE e.profile_id = shifts.employee_id
                  AND e.business_id = public.get_user_business_id()
            )
        )
    );

DROP POLICY IF EXISTS "Cashiers create own shifts" ON public.shifts;
DROP POLICY IF EXISTS "Shifts insert policy" ON public.shifts;
CREATE POLICY "Shifts insert policy" ON public.shifts
    FOR INSERT WITH CHECK (
        employee_id = auth.uid()
        OR (
            public.is_admin()
            AND EXISTS (
                SELECT 1 FROM public.employees e
                WHERE e.profile_id = shifts.employee_id
                  AND e.business_id = public.get_user_business_id()
            )
        )
    );

DROP POLICY IF EXISTS "Cashiers update own shifts, admins update store shifts" ON public.shifts;
DROP POLICY IF EXISTS "Shifts update policy" ON public.shifts;
CREATE POLICY "Shifts update policy" ON public.shifts
    FOR UPDATE USING (
        employee_id = auth.uid()
        OR (
            public.is_admin()
            AND EXISTS (
                SELECT 1 FROM public.employees e
                WHERE e.profile_id = shifts.employee_id
                  AND e.business_id = public.get_user_business_id()
            )
        )
    ) WITH CHECK (
        employee_id = auth.uid()
        OR (
            public.is_admin()
            AND EXISTS (
                SELECT 1 FROM public.employees e
                WHERE e.profile_id = shifts.employee_id
                  AND e.business_id = public.get_user_business_id()
            )
        )
    );

-- ----------------------------------------------------------------------------
-- 4. PROFILES RLS & FIELD IMMUTABILITY TRIGGER (RESTRICT SELECT TO OWN OR ADMIN)
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile or admins can view business profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view profiles" ON public.profiles;
CREATE POLICY "Users can view profiles" ON public.profiles
    FOR SELECT USING (
        id = auth.uid() OR public.is_admin()
    );

DROP POLICY IF EXISTS "Users can update own profile or admins can update profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update profiles" ON public.profiles;
CREATE POLICY "Users can update profiles" ON public.profiles
    FOR UPDATE USING (
        id = auth.uid() OR public.is_admin()
    ) WITH CHECK (
        id = auth.uid() OR public.is_admin()
    );

CREATE OR REPLACE FUNCTION public.enforce_profile_role_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT public.is_admin() THEN
            NEW.role := 'cashier';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NOT public.is_admin() THEN
            IF NEW.id IS DISTINCT FROM OLD.id THEN
                RAISE EXCEPTION 'Unauthorized: profile id cannot be changed.';
            END IF;

            IF NEW.role IS DISTINCT FROM OLD.role THEN
                RAISE EXCEPTION 'Unauthorized: only an admin can change role.';
            END IF;

            IF NEW.email IS DISTINCT FROM OLD.email THEN
                RAISE EXCEPTION 'Unauthorized: only an admin can change email.';
            END IF;

            IF NEW.phone IS DISTINCT FROM OLD.phone THEN
                RAISE EXCEPTION 'Unauthorized: only an admin can change phone.';
            END IF;

            IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
                RAISE EXCEPTION 'Unauthorized: created_at cannot be changed.';
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_profile_role_security_trigger ON public.profiles;
CREATE TRIGGER enforce_profile_role_security_trigger
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_profile_role_security();
