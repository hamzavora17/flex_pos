-- Migration: 020_allow_permanent_product_deletion.sql
-- Description: Makes product_id nullable with ON DELETE SET NULL on sale_return_items and inventory_logs,
-- and allows Admins and Managers to permanently delete products from their store catalog.

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. SALE_RETURN_ITEMS: Make product_id nullable with ON DELETE SET NULL
-- ----------------------------------------------------------------------------
ALTER TABLE public.sale_return_items ALTER COLUMN product_id DROP NOT NULL;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT constraint_name
        FROM information_schema.key_column_usage
        WHERE table_schema = 'public'
          AND table_name = 'sale_return_items'
          AND column_name = 'product_id'
    ) LOOP
        EXECUTE 'ALTER TABLE public.sale_return_items DROP CONSTRAINT ' || quote_ident(r.constraint_name);
    END LOOP;
END $$;

ALTER TABLE public.sale_return_items
ADD CONSTRAINT sale_return_items_product_id_fkey
FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


-- ----------------------------------------------------------------------------
-- 2. INVENTORY_LOGS: Make product_id nullable with ON DELETE SET NULL
-- ----------------------------------------------------------------------------
ALTER TABLE public.inventory_logs ALTER COLUMN product_id DROP NOT NULL;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT constraint_name
        FROM information_schema.key_column_usage
        WHERE table_schema = 'public'
          AND table_name = 'inventory_logs'
          AND column_name = 'product_id'
    ) LOOP
        EXECUTE 'ALTER TABLE public.inventory_logs DROP CONSTRAINT ' || quote_ident(r.constraint_name);
    END LOOP;
END $$;

ALTER TABLE public.inventory_logs
ADD CONSTRAINT inventory_logs_product_id_fkey
FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


-- ----------------------------------------------------------------------------
-- 3. PRODUCTS RLS DELETE POLICY: Allow Admins and Managers to delete products
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can delete business products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can delete business products" ON public.products;

CREATE POLICY "Admins and managers can delete business products"
ON public.products
FOR DELETE
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

COMMIT;
