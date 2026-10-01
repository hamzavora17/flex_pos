-- Migration: 004_held_sales_schema.sql
-- Description: Creates held_sales and held_sale_items tables for persisting paused cashier carts.

-- 1. Create held_sales table
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

-- 2. Create held_sale_items table
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

-- 3. Enable RLS
ALTER TABLE public.held_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.held_sale_items ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies for held_sales
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

-- 5. RLS Policies for held_sale_items
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
