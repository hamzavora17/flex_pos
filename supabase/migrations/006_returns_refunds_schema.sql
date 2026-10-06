-- Migration: 006_returns_refunds_schema.sql
-- Description: Creates sale_returns, sale_return_items, and hardened process_return RPC for handling product return inspections, refund calculations, and inventory restorations.

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

-- 5. Hardened RPC to process return atomically
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
    v_orig_quantity INT;
    v_already_returned_qty INT;
    v_remaining_qty INT;
    v_item_total NUMERIC;
    v_rows_updated INT;

    v_return_id UUID;
    v_result jsonb;

    v_agg_rec RECORD;
BEGIN
    -- 1. Security & Authentication check
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_business_id := public.get_user_business_id();
    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Not authorized for any business';
    END IF;

    -- 2. Extract & Validate sale_id
    IF payload->>'sale_id' IS NULL OR payload->>'sale_id' = '' THEN
        RAISE EXCEPTION 'sale_id is required';
    END IF;
    v_sale_id := (payload->>'sale_id')::UUID;

    -- Verify sale exists, belongs to authenticated user business, and is completed
    SELECT branch_id INTO v_branch_id
    FROM public.sales
    WHERE id = v_sale_id
      AND business_id = v_business_id
      AND status = 'completed';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Completed sale % not found or does not belong to your business', v_sale_id;
    END IF;

    -- 3. Check damage status
    v_is_damaged := COALESCE((payload->>'is_damaged')::BOOLEAN, false);
    v_payment_method := COALESCE(payload->>'payment_method', 'cash');

    IF v_is_damaged THEN
        RAISE EXCEPTION 'Return Rejected: Damaged or broken items are not eligible for return or refund.';
    END IF;

    IF payload->'items' IS NULL OR jsonb_array_length(payload->'items') = 0 THEN
        RAISE EXCEPTION 'Return items list cannot be empty';
    END IF;

    -- 4. Aggregate requested quantities per product_id ordered deterministically to prevent deadlocks & duplicate entry bypasses
    FOR v_agg_rec IN
        SELECT
            (elem->>'product_id')::UUID AS product_id,
            SUM((elem->>'quantity')::INT) AS total_requested_qty
        FROM jsonb_array_elements(payload->'items') elem
        GROUP BY (elem->>'product_id')::UUID
        ORDER BY (elem->>'product_id')::UUID ASC
    LOOP
        v_product_id := v_agg_rec.product_id;
        v_quantity := v_agg_rec.total_requested_qty;

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Total return quantity must be greater than zero for product %', v_product_id;
        END IF;

        -- CONCURRENT RETURN PROTECTION:
        -- Lock the sale_items row FOR UPDATE in consistent ORDER BY product_id ASC to prevent deadlocks and serialize concurrent returns.
        SELECT unit_price, quantity
        INTO v_unit_price, v_orig_quantity
        FROM public.sale_items
        WHERE sale_id = v_sale_id AND product_id = v_product_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % was not part of original sale %', v_product_id, v_sale_id;
        END IF;

        -- Calculate cumulative previously returned quantity for this product on this sale
        SELECT COALESCE(SUM(sri.quantity), 0)
        INTO v_already_returned_qty
        FROM public.sale_return_items sri
        JOIN public.sale_returns sr ON sr.id = sri.sale_return_id
        WHERE sr.sale_id = v_sale_id
          AND sri.product_id = v_product_id
          AND sr.status = 'approved';

        v_remaining_qty := v_orig_quantity - v_already_returned_qty;

        IF v_quantity > v_remaining_qty THEN
            RAISE EXCEPTION 'Cannot return % items for product %. Max eligible return quantity is % (% originally purchased, % already returned).',
                v_quantity, v_product_id, v_remaining_qty, v_orig_quantity, v_already_returned_qty;
        END IF;

        -- Accumulate refund total using authentic sale_items unit price (client price IGNORED)
        v_refund_amount := v_refund_amount + (v_quantity * v_unit_price);
    END LOOP;

    -- 5. Insert sale_returns record
    INSERT INTO public.sale_returns (
        business_id, branch_id, sale_id, employee_id, refund_amount, payment_method, is_damaged, status
    ) VALUES (
        v_business_id, v_branch_id, v_sale_id, v_user_id, v_refund_amount, v_payment_method, false, 'approved'
    ) RETURNING id INTO v_return_id;

    -- 6. Insert return items, restore inventory stock & write inventory logs for aggregated items in consistent order
    FOR v_agg_rec IN
        SELECT
            (elem->>'product_id')::UUID AS product_id,
            SUM((elem->>'quantity')::INT) AS total_requested_qty
        FROM jsonb_array_elements(payload->'items') elem
        GROUP BY (elem->>'product_id')::UUID
        ORDER BY (elem->>'product_id')::UUID ASC
    LOOP
        v_product_id := v_agg_rec.product_id;
        v_quantity := v_agg_rec.total_requested_qty;

        -- Re-fetch authentic unit price
        SELECT unit_price INTO v_unit_price
        FROM public.sale_items
        WHERE sale_id = v_sale_id AND product_id = v_product_id;

        v_item_total := v_quantity * v_unit_price;

        -- Insert return item
        INSERT INTO public.sale_return_items (
            sale_return_id, product_id, quantity, unit_price, refund_total
        ) VALUES (
            v_return_id, v_product_id, v_quantity, v_unit_price, v_item_total
        );

        -- Restore inventory quantity in public.inventory (+v_quantity)
        UPDATE public.inventory
        SET quantity = quantity + v_quantity,
            updated_at = NOW()
        WHERE product_id = v_product_id
          AND business_id = v_business_id
          AND (v_branch_id IS NULL OR branch_id = v_branch_id);

        -- VERIFY INVENTORY RESTORATION WAS EXECUTED
        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
        IF v_rows_updated = 0 THEN
            RAISE EXCEPTION 'Inventory record not found for product % at this branch. Return operation aborted.', v_product_id;
        END IF;

        -- Record movement in inventory_logs
        INSERT INTO public.inventory_logs (business_id, product_id, user_id, quantity_change, movement_type, notes)
        VALUES (v_business_id, v_product_id, v_user_id, v_quantity, 'return', 'Return for sale: ' || v_sale_id);
    END LOOP;

    v_result := jsonb_build_object(
        'return_id', v_return_id,
        'refund_amount', v_refund_amount,
        'status', 'approved'
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_return(jsonb) TO authenticated;
