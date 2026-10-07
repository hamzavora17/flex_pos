-- Migration: 017_fix_manager_inventory_rls.sql
-- Description: Grants Admins and Managers INSERT and UPDATE permissions on public.inventory
-- for their business store, while keeping DELETE permissions strictly restricted to Admins.

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. INVENTORY RLS POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Drop older or conflicting inventory policies
DROP POLICY IF EXISTS "Members can view inventory" ON public.inventory;
DROP POLICY IF EXISTS "Users can view inventory in their business branches" ON public.inventory;
DROP POLICY IF EXISTS "Admins and managers can view business inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins and managers can insert business inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins and managers can update business inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can delete business inventory" ON public.inventory;

-- SELECT: Admins and Managers can view store business inventory
CREATE POLICY "Admins and managers can view business inventory"
ON public.inventory
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- INSERT: Admins and Managers can create inventory records for their store products
CREATE POLICY "Admins and managers can insert business inventory"
ON public.inventory
FOR INSERT
TO authenticated
WITH CHECK (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- UPDATE: Admins and Managers can update stock levels for their store products
CREATE POLICY "Admins and managers can update business inventory"
ON public.inventory
FOR UPDATE
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
)
WITH CHECK (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- DELETE: Strictly restricted to Admins ONLY (Managers cannot delete inventory rows)
CREATE POLICY "Admins can delete business inventory"
ON public.inventory
FOR DELETE
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin()
);

COMMIT;
