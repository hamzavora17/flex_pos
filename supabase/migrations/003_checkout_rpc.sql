-- Migration: 003_checkout_rpc.sql
-- Description: Adds snapshot columns to sale_items, updates payments check constraint, and introduces the secure checkout RPC.

-- 1. Add Snapshot Columns to sale_items
ALTER TABLE public.sale_items
ADD COLUMN IF NOT EXISTS product_name_snapshot TEXT,
ADD COLUMN IF NOT EXISTS sku_snapshot TEXT;

-- 2. Update Payments constraint to include 'qr'
ALTER TABLE public.payments
DROP CONSTRAINT IF EXISTS payments_payment_method_check;

ALTER TABLE public.payments
ADD CONSTRAINT payments_payment_method_check
CHECK (payment_method IN ('cash', 'card', 'upi', 'qr', 'other'));

-- 3. Create the process_checkout RPC
CREATE OR REPLACE FUNCTION public.process_checkout(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_user_id UUID;
    v_business_id UUID;
    v_branch_id UUID;
    v_customer_id UUID;
    v_discount NUMERIC;
    v_payment_method TEXT;

    v_item jsonb;
    v_product_id UUID;
    v_quantity INT;
    v_prod_name TEXT;
    v_prod_sku TEXT;
    v_unit_price NUMERIC;

    v_inventory_id UUID;
    v_stock_qty INT;

    v_subtotal NUMERIC := 0;
    v_tax NUMERIC := 0;
    v_total NUMERIC := 0;

    v_sale_id UUID;
    v_invoice_number TEXT;

    v_result jsonb;
BEGIN
    -- 1. Derive user & business securely
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_business_id := public.get_user_business_id();
    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Not authorized for any business';
    END IF;

    -- 2. Extract payload safely
    BEGIN
        IF payload->>'branch_id' IS NULL OR payload->>'branch_id' = '' THEN
            RAISE EXCEPTION 'branch_id is required';
        END IF;
        v_branch_id := (payload->>'branch_id')::UUID;

        IF payload->>'customer_id' IS NOT NULL AND payload->>'customer_id' <> '' THEN
            v_customer_id := (payload->>'customer_id')::UUID;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid UUID format in payload';
    END;

    -- SECURE BRANCH ISOLATION CHECK
    IF NOT EXISTS (
        SELECT 1 FROM public.branches
        WHERE id = v_branch_id AND business_id = v_business_id
    ) THEN
        RAISE EXCEPTION 'Branch does not exist or does not belong to this business';
    END IF;

    -- SECURE CUSTOMER ISOLATION CHECK
    IF v_customer_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.customers
            WHERE id = v_customer_id AND business_id = v_business_id
        ) THEN
            RAISE EXCEPTION 'Customer does not exist or does not belong to this business';
        END IF;
    END IF;

    v_discount := COALESCE((payload->>'discount')::NUMERIC, 0);
    v_payment_method := COALESCE(payload->>'payment_method', 'cash');

    IF v_discount < 0 THEN
        RAISE EXCEPTION 'Discount cannot be negative';
    END IF;

    IF payload->'items' IS NULL OR jsonb_array_length(payload->'items') = 0 THEN
        RAISE EXCEPTION 'Cart cannot be empty';
    END IF;

    IF v_payment_method NOT IN ('cash', 'card', 'upi', 'qr', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method: %', v_payment_method;
    END IF;

    -- Generate a unique Invoice Number (e.g., INV-YYYYMMDD-XXXXXX)
    v_invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 6));

    -- 3. Create the draft Sale record
    INSERT INTO public.sales (business_id, branch_id, customer_id, employee_id, invoice_number, subtotal, discount, tax, total, status)
    VALUES (v_business_id, v_branch_id, v_customer_id, v_user_id, v_invoice_number, 0, v_discount, 0, 0, 'completed')
    RETURNING id INTO v_sale_id;

    -- 4. Process each item in the cart
    FOR v_item IN SELECT * FROM jsonb_array_elements(payload->'items')
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantity must be positive for all items';
        END IF;

        -- Get Product pricing details securely
        SELECT name, sku, price
        INTO v_prod_name, v_prod_sku, v_unit_price
        FROM public.products
        WHERE id = v_product_id AND business_id = v_business_id AND active = true;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found or is inactive', v_product_id;
        END IF;

        -- Lock inventory row for update to prevent concurrent overselling
        SELECT id, quantity
        INTO v_inventory_id, v_stock_qty
        FROM public.inventory
        WHERE product_id = v_product_id AND branch_id = v_branch_id AND business_id = v_business_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Inventory record not found for product "%" at this branch', v_prod_name;
        END IF;

        IF v_stock_qty < v_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product "%" (Available: %, Requested: %)', v_prod_name, v_stock_qty, v_quantity;
        END IF;

        -- Deduct inventory from public.inventory table
        UPDATE public.inventory
        SET quantity = quantity - v_quantity,
            updated_at = NOW()
        WHERE id = v_inventory_id;

        -- Insert into inventory_logs
        INSERT INTO public.inventory_logs (business_id, product_id, user_id, quantity_change, movement_type, notes)
        VALUES (v_business_id, v_product_id, v_user_id, -v_quantity, 'sale', 'Sale invoice: ' || v_invoice_number);

        -- Create sale item
        INSERT INTO public.sale_items (sale_id, product_id, product_name, product_sku, product_name_snapshot, sku_snapshot, quantity, unit_price, line_total)
        VALUES (v_sale_id, v_product_id, v_prod_name, v_prod_sku, v_prod_name, v_prod_sku, v_quantity, v_unit_price, v_quantity * v_unit_price);

        -- Accumulate subtotal
        v_subtotal := v_subtotal + (v_quantity * v_unit_price);
    END LOOP;

    -- 5. Finalize Sale Calculations
    v_total := v_subtotal - v_discount + v_tax;

    IF v_total < 0 THEN
        RAISE EXCEPTION 'Total cannot be negative. Discount exceeds subtotal.';
    END IF;

    -- Update Sale totals
    UPDATE public.sales
    SET subtotal = v_subtotal,
        total = v_total
    WHERE id = v_sale_id;

    -- 6. Record Payment
    INSERT INTO public.payments (sale_id, amount, method, payment_method)
    VALUES (v_sale_id, v_total, v_payment_method, v_payment_method);

    -- 7. Return summary
    v_result := jsonb_build_object(
        'sale_id', v_sale_id,
        'invoice_number', v_invoice_number,
        'subtotal', v_subtotal,
        'discount', v_discount,
        'tax', v_tax,
        'total', v_total,
        'payment_method', v_payment_method
    );

    RETURN v_result;
END;
$$;