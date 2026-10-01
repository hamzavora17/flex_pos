-- Migration: 006_returns_refunds_schema.sql
-- Description: Creates sale_returns, sale_return_items, and process_return RPC for handling product return inspections, refund calculations, and inventory restorations.

-- 1. Create sale_returns table
CREATE TABLE IF NOT EXISTS public.sale_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    refund_amount NUMERIC(12, 2) NOT NULL CHECK (refund_amount >= 0),
    payment_method TEXT NOT NULL DEFAULT 'cash',
    is_damaged BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved', 'rejected')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create sale_return_items table
CREATE TABLE IF NOT EXISTS public.sale_return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_return_id UUID NOT NULL REFERENCES public.sale_returns(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    refund_total NUMERIC(12, 2) NOT NULL CHECK (refund_total >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Enable RLS
ALTER TABLE public.sale_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_return_items ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies
DROP POLICY IF EXISTS "Cashiers view own sale returns, admins view store returns" ON public.sale_returns;
CREATE POLICY "Cashiers view own sale returns, admins view store returns" ON public.sale_returns
    FOR SELECT USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Cashiers create sale returns for their store" ON public.sale_returns;
CREATE POLICY "Cashiers create sale returns for their store" ON public.sale_returns
    FOR INSERT WITH CHECK (
        business_id = public.get_user_business_id() AND employee_id = auth.uid()
    );

DROP POLICY IF EXISTS "Cashiers view own return items, admins view store return items" ON public.sale_return_items;
CREATE POLICY "Cashiers view own return items, admins view store return items" ON public.sale_return_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.sale_returns sr
            WHERE sr.id = sale_return_items.sale_return_id
              AND sr.business_id = public.get_user_business_id()
              AND (public.is_admin() OR sr.employee_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Cashiers insert return items" ON public.sale_return_items;
CREATE POLICY "Cashiers insert return items" ON public.sale_return_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.sale_returns sr
            WHERE sr.id = sale_return_items.sale_return_id
              AND sr.business_id = public.get_user_business_id()
              AND sr.employee_id = auth.uid()
        )
    );

-- 5. RPC to process return atomically
CREATE OR REPLACE FUNCTION public.process_return(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_user_id UUID;
    v_business_id UUID;
    v_sale_id UUID;
    v_branch_id UUID;
    v_is_damaged BOOLEAN;
    v_refund_amount NUMERIC := 0;
    v_payment_method TEXT;

    v_item jsonb;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC;
    v_item_total NUMERIC;

    v_return_id UUID;
    v_result jsonb;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_business_id := public.get_user_business_id();
    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Not authorized for any business';
    END IF;

    v_sale_id := (payload->>'sale_id')::UUID;
    v_is_damaged := (payload->>'is_damaged')::BOOLEAN;
    v_payment_method := COALESCE(payload->>'payment_method', 'cash');

    IF v_is_damaged THEN
        RAISE EXCEPTION 'Return Rejected: Damaged items are not eligible for return or refund.';
    END IF;

    -- Get branch_id from sale
    SELECT branch_id INTO v_branch_id FROM public.sales WHERE id = v_sale_id AND business_id = v_business_id;

    -- Calculate total refund amount
    FOR v_item IN SELECT * FROM jsonb_array_elements(payload->'items')
    LOOP
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (v_item->>'unit_price')::NUMERIC;
        v_item_total := v_quantity * v_unit_price;
        v_refund_amount := v_refund_amount + v_item_total;
    END LOOP;

    -- Insert sale_returns
    INSERT INTO public.sale_returns (
        business_id, branch_id, sale_id, employee_id, refund_amount, payment_method, is_damaged, status
    ) VALUES (
        v_business_id, v_branch_id, v_sale_id, v_user_id, v_refund_amount, v_payment_method, false, 'approved'
    ) RETURNING id INTO v_return_id;

    -- Insert items & restore inventory stock
    FOR v_item IN SELECT * FROM jsonb_array_elements(payload->'items')
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (v_item->>'unit_price')::NUMERIC;
        v_item_total := v_quantity * v_unit_price;

        INSERT INTO public.sale_return_items (
            sale_return_id, product_id, quantity, unit_price, refund_total
        ) VALUES (
            v_return_id, v_product_id, v_quantity, v_unit_price, v_item_total
        );

        -- Restore inventory stock (+v_quantity)
        UPDATE public.products
        SET stock_quantity = stock_quantity + v_quantity,
            updated_at = NOW()
        WHERE id = v_product_id AND business_id = v_business_id;

        -- Record inventory log
        INSERT INTO public.inventory (
            business_id, product_id, quantity, movement_type, reference
        ) VALUES (
            v_business_id, v_product_id, v_quantity, 'return', 'RETURN-' || v_return_id
        );
    END LOOP;

    v_result := jsonb_build_object(
        'return_id', v_return_id,
        'refund_amount', v_refund_amount,
        'status', 'approved'
    );

    RETURN v_result;
END;
$$;
