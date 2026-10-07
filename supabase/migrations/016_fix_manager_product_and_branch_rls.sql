-- Migration: 016_fix_manager_product_and_branch_rls.sql
-- Description: Grants Managers secure INSERT and UPDATE permissions on products,
-- restricts product DELETE permission strictly to Admins, and enables branch SELECT access
-- for authenticated store business members.

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. PRODUCTS RLS POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Drop older or conflicting product policies
DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can manage products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can view business products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can insert business products" ON public.products;
DROP POLICY IF EXISTS "Admins and managers can update business products" ON public.products;
DROP POLICY IF EXISTS "Admins can delete business products" ON public.products;
DROP POLICY IF EXISTS "Members can view products" ON public.products;
DROP POLICY IF EXISTS "Users can view data in their business" ON public.products;

-- SELECT: Admins and Managers can view business products (Cashiers use cashier_products view)
CREATE POLICY "Admins and managers can view business products"
ON public.products
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- INSERT: Admins and Managers can add products to their store catalog
CREATE POLICY "Admins and managers can insert business products"
ON public.products
FOR INSERT
TO authenticated
WITH CHECK (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- UPDATE: Admins and Managers can update product details & active status
CREATE POLICY "Admins and managers can update business products"
ON public.products
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

-- DELETE: Strictly restricted to Admins ONLY (Managers cannot permanently delete products)
CREATE POLICY "Admins can delete business products"
ON public.products
FOR DELETE
TO authenticated
USING (
    business_id = public.get_user_business_id()
    AND public.is_admin()
);


-- ----------------------------------------------------------------------------
-- 2. BRANCHES RLS POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

-- Drop older or conflicting branch policies
DROP POLICY IF EXISTS "Members can view business branches" ON public.branches;
DROP POLICY IF EXISTS "Admins can manage branches" ON public.branches;
DROP POLICY IF EXISTS "Users can view branches" ON public.branches;
DROP POLICY IF EXISTS "Admins and managers can insert business branches" ON public.branches;
DROP POLICY IF EXISTS "Admins and managers can update business branches" ON public.branches;

-- SELECT: Authenticated members of the business can view store branches
CREATE POLICY "Members can view business branches"
ON public.branches
FOR SELECT
TO authenticated
USING (
    business_id = public.get_user_business_id()
);

-- INSERT: Admins and Managers can create store branches
CREATE POLICY "Admins and managers can insert business branches"
ON public.branches
FOR INSERT
TO authenticated
WITH CHECK (
    business_id = public.get_user_business_id()
    AND public.is_admin_or_manager()
);

-- UPDATE: Admins and Managers can update store branches
CREATE POLICY "Admins and managers can update business branches"
ON public.branches
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

COMMIT;
