-- Migration: 022_fix_returns_refunds_rpc.sql
-- Description: Fixes process_return RPC to resolve sale items by either product_id or sale_items.id,
-- and safely verifies product existence before inserting into sale_return_items or restoring inventory,
-- preventing foreign key violations and "product not in original sale" errors on past or custom sales.

-- 1. Allow sale_return_items.product_id to be NULL for custom / deleted products / legacy items
ALTER TABLE public.sale_return_items ALTER COLUMN product_id DROP NOT NULL;

-- 2. Update process_return RPC
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

    v_product_id UUID;
    v_actual_product_id UUID;
    v_target_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC;
    v_orig_quantity INT;
    v_already_returned_qty INT;
    v_remaining_qty INT;
    v_item_total NUMERIC;

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

    -- 4. Aggregate requested quantities per product_id ordered deterministically
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
            RAISE EXCEPTION 'Total return quantity must be greater than zero for item %', v_product_id;
        END IF;

        -- CONCURRENT RETURN PROTECTION:
        -- Lock the sale_items row FOR UPDATE matching by either product_id OR sale_items.id
        SELECT unit_price, quantity, product_id
        INTO v_unit_price, v_orig_quantity, v_actual_product_id
        FROM public.sale_items
        WHERE sale_id = v_sale_id AND (product_id = v_product_id OR id = v_product_id)
        LIMIT 1
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % was not part of original sale %', v_product_id, v_sale_id;
        END IF;

        -- Calculate cumulative previously returned quantity for this item/product on this sale
        SELECT COALESCE(SUM(sri.quantity), 0)
        INTO v_already_returned_qty
        FROM public.sale_return_items sri
        JOIN public.sale_returns sr ON sr.id = sri.sale_return_id
        WHERE sr.sale_id = v_sale_id
          AND (
            sri.product_id = v_product_id
            OR (v_actual_product_id IS NOT NULL AND sri.product_id = v_actual_product_id)
          )
          AND sr.status = 'approved';

        v_remaining_qty := v_orig_quantity - v_already_returned_qty;

        IF v_quantity > v_remaining_qty THEN
            RAISE EXCEPTION 'Cannot return % items for item %. Max eligible return quantity is % (% originally purchased, % already returned).',
                v_quantity, v_product_id, v_remaining_qty, v_orig_quantity, v_already_returned_qty;
        END IF;

        -- Accumulate refund total using authentic sale_items unit price
        v_refund_amount := v_refund_amount + (v_quantity * v_unit_price);
    END LOOP;

    -- 5. Insert sale_returns record
    INSERT INTO public.sale_returns (
        business_id, branch_id, sale_id, employee_id, refund_amount, payment_method, is_damaged, status
    ) VALUES (
        v_business_id, v_branch_id, v_sale_id, v_user_id, v_refund_amount, v_payment_method, false, 'approved'
    ) RETURNING id INTO v_return_id;

    -- 6. Insert return items & restore inventory stock if product_id exists
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

        -- Re-fetch authentic unit price and actual product_id from sale_items
        SELECT unit_price, product_id INTO v_unit_price, v_actual_product_id
        FROM public.sale_items
        WHERE sale_id = v_sale_id AND (product_id = v_product_id OR id = v_product_id)
        LIMIT 1;

        v_item_total := v_quantity * v_unit_price;

        -- Safely verify if product_id exists in public.products table
        IF v_actual_product_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.products WHERE id = v_actual_product_id) THEN
            v_target_product_id := v_actual_product_id;
        ELSIF EXISTS (SELECT 1 FROM public.products WHERE id = v_product_id) THEN
            v_target_product_id := v_product_id;
        ELSE
            v_target_product_id := NULL;
        END IF;

        -- Insert return item
        INSERT INTO public.sale_return_items (
            sale_return_id, product_id, quantity, unit_price, refund_total
        ) VALUES (
            v_return_id, v_target_product_id, v_quantity, v_unit_price, v_item_total
        );

        -- Restore inventory stock in public.inventory if valid product_id is associated
        IF v_target_product_id IS NOT NULL THEN
            UPDATE public.inventory
            SET quantity = quantity + v_quantity,
                updated_at = NOW()
            WHERE product_id = v_target_product_id
              AND business_id = v_business_id
              AND (v_branch_id IS NULL OR branch_id = v_branch_id);

            -- Record movement in inventory_logs
            INSERT INTO public.inventory_logs (business_id, product_id, user_id, quantity_change, movement_type, notes)
            VALUES (v_business_id, v_target_product_id, v_user_id, v_quantity, 'return', 'Return for sale: ' || v_sale_id);
        END IF;

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
