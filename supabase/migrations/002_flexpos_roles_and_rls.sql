-- Migration: 002_flexpos_roles_and_rls.sql
-- Description: Incremental migration extending the existing FlexPOS database with roles,
-- store ownership, employee assignments, initial data updates, and Row Level Security (RLS).

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS & GENERAL HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 1. INCREMENTAL SCHEMA EXTENSIONS ON EXISTING TABLES
-- ----------------------------------------------------------------------------

-- PROFILES
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'employee' CHECK (role IN ('admin', 'employee'));

-- BUSINESSES
ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT;

-- PRODUCTS
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS unit TEXT DEFAULT 'pcs',
  ADD COLUMN IF NOT EXISTS min_stock_alert INTEGER DEFAULT 5;

-- INVENTORY
ALTER TABLE public.inventory
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;

-- CUSTOMERS
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS address TEXT;

-- ----------------------------------------------------------------------------
-- 2. CREATE NEW TABLES REQUIRED FOR FLEXPOS ROLES & AUDITING
-- ----------------------------------------------------------------------------

-- EMPLOYEES (Assigns employee profiles to a business store)
CREATE TABLE IF NOT EXISTS public.employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    profile_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    position TEXT DEFAULT 'cashier',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- INVENTORY LOGS (Audit trail for stock movement, restocks, and sale deductions)
CREATE TABLE IF NOT EXISTS public.inventory_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    quantity_change INTEGER NOT NULL,
    movement_type TEXT NOT NULL CHECK (movement_type IN ('stock_in', 'stock_out', 'adjustment', 'sale', 'return')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. INITIALIZATION & DATA SEEDING (BEFORE RLS POLICIES ARE ENABLED)
-- ----------------------------------------------------------------------------

-- A. Initialize existing Admin profile
UPDATE public.profiles
SET
    email = 'admin@flexpos.com',
    role = 'admin'
WHERE id = '136e7dfc-4b84-44fb-b8ec-b63f49809d3d';

-- B. Initialize existing Employee profile
UPDATE public.profiles
SET
    email = 'hamza@flexpos.com',
    role = 'employee'
WHERE id = 'fb0d9da0-713e-4d20-a1df-e277a116c035';

-- C. Assign store owner to existing Demo FlexPOS Store
UPDATE public.businesses
SET owner_id = '136e7dfc-4b84-44fb-b8ec-b63f49809d3d'
WHERE id = 'b0000000-0000-0000-0000-000000000001';

-- D. Create employee relationship linking Employee profile to Demo FlexPOS Store
INSERT INTO public.employees (
    business_id,
    profile_id,
    position,
    status
) VALUES (
    'b0000000-0000-0000-0000-000000000001',
    'fb0d9da0-713e-4d20-a1df-e277a116c035',
    'cashier',
    'active'
) ON CONFLICT (profile_id) DO NOTHING;

-- E. Backfill business_id on existing inventory rows if unassigned
UPDATE public.inventory
SET business_id = 'b0000000-0000-0000-0000-000000000001'
WHERE business_id IS NULL;

-- ----------------------------------------------------------------------------
-- 4. INDEXES FOR PERFORMANCE
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_businesses_owner ON public.businesses(owner_id);

CREATE INDEX IF NOT EXISTS idx_employees_business ON public.employees(business_id);
CREATE INDEX IF NOT EXISTS idx_employees_profile ON public.employees(profile_id);

CREATE INDEX IF NOT EXISTS idx_categories_business ON public.categories(business_id);

CREATE INDEX IF NOT EXISTS idx_products_business ON public.products(business_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);

CREATE INDEX IF NOT EXISTS idx_inventory_product ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_business ON public.inventory(business_id);

CREATE INDEX IF NOT EXISTS idx_inventory_logs_business ON public.inventory_logs(business_id);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_product ON public.inventory_logs(product_id);

CREATE INDEX IF NOT EXISTS idx_customers_business ON public.customers(business_id);

CREATE INDEX IF NOT EXISTS idx_sales_business ON public.sales(business_id);
CREATE INDEX IF NOT EXISTS idx_sales_employee ON public.sales(employee_id);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON public.sale_items(sale_id);

CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments(sale_id);

-- ----------------------------------------------------------------------------
-- 5. RLS HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

-- Checks if current authenticated user is an Admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

-- Gets the business_id associated with current authenticated user
CREATE OR REPLACE FUNCTION public.get_user_business_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT b.id FROM public.businesses b WHERE b.owner_id = auth.uid()
    UNION ALL
    SELECT e.business_id FROM public.employees e WHERE e.profile_id = auth.uid() AND e.status = 'active'
    LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- 6. ENABLE ROW LEVEL SECURITY (RLS) ON ALL TABLES
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 7. RLS POLICIES
-- ----------------------------------------------------------------------------

-- PROFILES
DROP POLICY IF EXISTS "Users can view profiles" ON public.profiles;
CREATE POLICY "Users can view profiles" ON public.profiles FOR SELECT
USING (
    id = auth.uid()
    OR public.is_admin()
    OR id IN (
        SELECT e.profile_id FROM public.employees e WHERE e.business_id = public.get_user_business_id()
    )
);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Users can update profiles" ON public.profiles;
CREATE POLICY "Users can update profiles" ON public.profiles FOR UPDATE
USING (id = auth.uid() OR public.is_admin())
WITH CHECK (id = auth.uid() OR public.is_admin());

-- BUSINESSES
DROP POLICY IF EXISTS "Members can view business" ON public.businesses;
CREATE POLICY "Members can view business" ON public.businesses FOR SELECT
USING (owner_id = auth.uid() OR id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins can insert business" ON public.businesses;
CREATE POLICY "Admins can insert business" ON public.businesses FOR INSERT
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Admins can update business" ON public.businesses;
CREATE POLICY "Admins can update business" ON public.businesses FOR UPDATE
USING (owner_id = auth.uid() OR (public.is_admin() AND id = public.get_user_business_id()))
WITH CHECK (owner_id = auth.uid() OR (public.is_admin() AND id = public.get_user_business_id()));

-- EMPLOYEES
DROP POLICY IF EXISTS "Members can view employees" ON public.employees;
CREATE POLICY "Members can view employees" ON public.employees FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins can manage employees" ON public.employees;
CREATE POLICY "Admins can manage employees" ON public.employees FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- CATEGORIES
DROP POLICY IF EXISTS "Members can view categories" ON public.categories;
CREATE POLICY "Members can view categories" ON public.categories FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories;
CREATE POLICY "Admins can manage categories" ON public.categories FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- PRODUCTS
DROP POLICY IF EXISTS "Members can view products" ON public.products;
CREATE POLICY "Members can view products" ON public.products FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
CREATE POLICY "Admins can manage products" ON public.products FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- INVENTORY & INVENTORY LOGS
DROP POLICY IF EXISTS "Members can view inventory" ON public.inventory;
CREATE POLICY "Members can view inventory" ON public.inventory FOR SELECT
USING (business_id = public.get_user_business_id() OR business_id IS NULL);

DROP POLICY IF EXISTS "Members can view inventory logs" ON public.inventory_logs;
CREATE POLICY "Members can view inventory logs" ON public.inventory_logs FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Members can insert inventory logs" ON public.inventory_logs;
CREATE POLICY "Members can insert inventory logs" ON public.inventory_logs FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

-- CUSTOMERS
DROP POLICY IF EXISTS "Members can view customers" ON public.customers;
CREATE POLICY "Members can view customers" ON public.customers FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Members can insert customers" ON public.customers;
CREATE POLICY "Members can insert customers" ON public.customers FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Members can update customers" ON public.customers;
CREATE POLICY "Members can update customers" ON public.customers FOR UPDATE
USING (business_id = public.get_user_business_id())
WITH CHECK (business_id = public.get_user_business_id());

-- SALES
DROP POLICY IF EXISTS "Members can view sales" ON public.sales;
CREATE POLICY "Members can view sales" ON public.sales FOR SELECT
USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Members can create sales" ON public.sales;
CREATE POLICY "Members can create sales" ON public.sales FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins can update sales" ON public.sales;
CREATE POLICY "Admins can update sales" ON public.sales FOR UPDATE
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- SALE ITEMS
DROP POLICY IF EXISTS "Members can view sale items" ON public.sale_items;
CREATE POLICY "Members can view sale items" ON public.sale_items FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = sale_items.sale_id AND s.business_id = public.get_user_business_id()
    )
);

DROP POLICY IF EXISTS "Members can create sale items" ON public.sale_items;
CREATE POLICY "Members can create sale items" ON public.sale_items FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = sale_items.sale_id AND s.business_id = public.get_user_business_id()
    )
);

-- PAYMENTS
DROP POLICY IF EXISTS "Members can view payments" ON public.payments;
CREATE POLICY "Members can view payments" ON public.payments FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = payments.sale_id AND s.business_id = public.get_user_business_id()
    )
);

DROP POLICY IF EXISTS "Members can create payments" ON public.payments;
CREATE POLICY "Members can create payments" ON public.payments FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = payments.sale_id AND s.business_id = public.get_user_business_id()
    )
);
