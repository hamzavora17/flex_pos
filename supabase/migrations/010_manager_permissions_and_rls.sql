-- Migration 010: Manager permissions, RLS hardening, cashier catalog
-- Run this exact file in Supabase SQL Editor.
-- Also replace your local 010_manager_permissions_and_rls.sql with this file.
--
-- IMPORTANT:
-- This migration removes older permissive SELECT policies first.
-- PostgreSQL combines PERMISSIVE policies with OR, so leaving an old
-- business-wide SELECT policy would defeat the new role restrictions.

BEGIN;

-- ============================================================
-- 1. Remove old/broad SELECT policies
-- ============================================================

DROP POLICY IF EXISTS "Members can view employees" ON public.employees;

DROP POLICY IF EXISTS "Members can view inventory" ON public.inventory;
DROP POLICY IF EXISTS "Users can view inventory in their business branches" ON public.inventory;

DROP POLICY IF EXISTS "Members can view inventory logs" ON public.inventory_logs;

DROP POLICY IF EXISTS "Members can view payments" ON public.payments;
DROP POLICY IF EXISTS "Users can view payments in their business" ON public.payments;

DROP POLICY IF EXISTS "Members can view products" ON public.products;
DROP POLICY IF EXISTS "Users can view data in their business" ON public.products;

DROP POLICY IF EXISTS "Members can view sale items" ON public.sale_items;
DROP POLICY IF EXISTS "Users can view sale items in their business" ON public.sale_items;

DROP POLICY IF EXISTS "Members can view sales" ON public.sales;
DROP POLICY IF EXISTS "Users can view sales in their business" ON public.sales;

DROP POLICY IF EXISTS "Users can view profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view profiles in their business" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;

-- Remove previous versions if this migration has been partially run.
DROP POLICY IF EXISTS "Admins and managers can view business sales" ON public.sales;
DROP POLICY IF EXISTS "Cashiers can view own sales" ON public.sales;
DROP POLICY IF EXISTS "Admins and managers can view business sale items" ON public.sale_items;
DROP POLICY IF EXISTS "Cashiers can view own sale items" ON public.sale_items;
DROP POLICY IF EXISTS "Admins and managers can view business payments" ON public.payments;
DROP POLICY IF EXISTS "Cashiers can view own payments" ON public.payments;
DROP POLICY IF EXISTS "Admins and managers can view business products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can view business inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins and managers can view business inventory logs" ON public.inventory_logs;
DROP POLICY IF EXISTS "Users can view own employee record" ON public.employees;
DROP POLICY IF EXISTS "Users can view own profile or admins can view business profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile or admins can update profiles" ON public.profiles;

-- ============================================================
-- 2. Ensure RLS is enabled
-- ============================================================

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. SALES
-- Admin/Manager: all sales in own business.
-- Cashier/employee: only their own sales.
-- ============================================================

CREATE POLICY "Admins and managers can view business sales"
ON public.sales
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

CREATE POLICY "Cashiers can view own sales"
ON public.sales
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND NOT public.is_admin_or_manager()
    AND employee_id = auth.uid()
);

-- ============================================================
-- 4. SALE ITEMS
-- Visibility follows the parent sale.
-- ============================================================

CREATE POLICY "Admins and managers can view business sale items"
ON public.sale_items
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.sales s
        WHERE s.id = sale_items.sale_id
          AND s.business_id = public.get_user_business_id()
          AND public.is_admin_or_manager()
    )
);

CREATE POLICY "Cashiers can view own sale items"
ON public.sale_items
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.sales s
        WHERE s.id = sale_items.sale_id
          AND s.business_id = public.get_user_business_id()
          AND NOT public.is_admin_or_manager()
          AND s.employee_id = auth.uid()
    )
);

-- ============================================================
-- 5. PAYMENTS
-- Visibility follows the parent sale.
-- ============================================================

CREATE POLICY "Admins and managers can view business payments"
ON public.payments
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.sales s
        WHERE s.id = payments.sale_id
          AND s.business_id = public.get_user_business_id()
          AND public.is_admin_or_manager()
    )
);

CREATE POLICY "Cashiers can view own payments"
ON public.payments
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.sales s
        WHERE s.id = payments.sale_id
          AND s.business_id = public.get_user_business_id()
          AND NOT public.is_admin_or_manager()
          AND s.employee_id = auth.uid()
    )
);

-- ============================================================
-- 6. PRODUCTS
-- Only Admin/Manager get direct table visibility.
-- Cashiers use cashier_products.
-- ============================================================

CREATE POLICY "Admins and managers can view business products"
ON public.products
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- ============================================================
-- 7. INVENTORY
-- Only Admin/Manager get direct inventory visibility.
-- ============================================================

CREATE POLICY "Admins and managers can view business inventory"
ON public.inventory
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- ============================================================
-- 8. INVENTORY LOGS
-- Only Admin/Manager can read inventory movement history.
-- ============================================================

CREATE POLICY "Admins and managers can view business inventory logs"
ON public.inventory_logs
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- ============================================================
-- 9. EMPLOYEES
-- Manager must not see the staff list.
-- Admin retains the existing admin management policy.
-- A normal user can see only their own employee row.
-- ============================================================

CREATE POLICY "Users can view own employee record"
ON public.employees
FOR SELECT
TO authenticated
USING (
    profile_id = auth.uid()
);

-- ============================================================
-- 10. PROFILES
-- SELECT: own profile, or Admin.
-- UPDATE: own profile, or Admin.
--
-- The trigger below restricts non-admin users to full_name only.
-- ============================================================

CREATE POLICY "Users can view own profile or admins can view business profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (
    id = auth.uid()
    OR public.is_admin()
);

CREATE POLICY "Users can update own profile or admins can update profiles"
ON public.profiles
FOR UPDATE
TO authenticated
USING (
    id = auth.uid()
    OR public.is_admin()
)
WITH CHECK (
    id = auth.uid()
    OR public.is_admin()
);

-- ============================================================
-- 11. Profile security trigger
--
-- INSERT:
--   Non-admin users cannot self-assign admin/manager.
--   Their role is forced to cashier.
--
-- UPDATE:
--   Non-admin users may change ONLY full_name.
--   id, role, email, phone, and created_at are immutable.
--   Admins retain administrative control.
-- ============================================================

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

DROP TRIGGER IF EXISTS enforce_profile_role_security_trigger
ON public.profiles;

CREATE TRIGGER enforce_profile_role_security_trigger
BEFORE INSERT OR UPDATE
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_profile_role_security();

-- ============================================================
-- 12. Cashier catalog
--
-- Cashiers receive only the fields needed for selling.
-- No cost, exact stock quantity, or inventory threshold is exposed.
--
-- Stock authority = inventory.quantity.
-- ============================================================

CREATE OR REPLACE VIEW public.cashier_products AS
SELECT
    p.id,
    p.business_id,
    p.category_id,
    p.name,
    p.sku,
    p.barcode,
    p.price,
    p.unit,
    p.active,
    (
        COALESCE(SUM(i.quantity), 0) > 0
    ) AS is_in_stock
FROM public.products p
LEFT JOIN public.inventory i
    ON i.product_id = p.id
   AND i.business_id = p.business_id
WHERE p.business_id = public.get_user_business_id()
  AND p.active = true
GROUP BY
    p.id,
    p.business_id,
    p.category_id,
    p.name,
    p.sku,
    p.barcode,
    p.price,
    p.unit,
    p.active;

GRANT SELECT
ON public.cashier_products
TO authenticated;

COMMIT;
