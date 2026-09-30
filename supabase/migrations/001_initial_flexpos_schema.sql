-- Migration: 001_initial_flexpos_schema.sql
-- Description: Initial database schema and Row Level Security (RLS) policies for FlexPOS.

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS & HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Function to handle updated_at timestamp updates automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 1. TABLES DEFINITIONS
-- ----------------------------------------------------------------------------

-- 1. PROFILES (Extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'employee' CHECK (role IN ('admin', 'employee')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. BUSINESSES
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    email TEXT,
    phone TEXT,
    address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. EMPLOYEES
CREATE TABLE IF NOT EXISTS public.employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    profile_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    position TEXT DEFAULT 'cashier',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. PRODUCTS
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    sku TEXT,
    barcode TEXT,
    purchase_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (purchase_price >= 0),
    selling_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (selling_price >= 0),
    stock_quantity INT NOT NULL DEFAULT 0,
    minimum_stock_level INT NOT NULL DEFAULT 5,
    unit TEXT DEFAULT 'pcs',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_business_sku UNIQUE (business_id, sku),
    CONSTRAINT unique_business_barcode UNIQUE (business_id, barcode)
);

-- 6. INVENTORY
CREATE TABLE IF NOT EXISTS public.inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity INT NOT NULL, -- positive for stock addition, negative for stock deduction
    movement_type TEXT NOT NULL CHECK (movement_type IN ('stock_in', 'stock_out', 'adjustment', 'sale', 'return')),
    reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. CUSTOMERS
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. SALES
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    invoice_number TEXT NOT NULL,
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (subtotal >= 0),
    discount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0),
    tax NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (tax >= 0),
    total NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total >= 0),
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'pending', 'cancelled', 'refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_business_invoice UNIQUE (business_id, invoice_number)
);

-- 9. SALE_ITEMS
CREATE TABLE IF NOT EXISTS public.sale_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    discount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0),
    total NUMERIC(12, 2) NOT NULL CHECK (total >= 0)
);

-- 10. PAYMENTS
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'card', 'upi', 'other')),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'pending', 'failed', 'refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. INDEXES
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_businesses_owner ON public.businesses(owner_id);

CREATE INDEX IF NOT EXISTS idx_employees_business ON public.employees(business_id);
CREATE INDEX IF NOT EXISTS idx_employees_profile ON public.employees(profile_id);

CREATE INDEX IF NOT EXISTS idx_categories_business ON public.categories(business_id);

CREATE INDEX IF NOT EXISTS idx_products_business ON public.products(business_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON public.products(sku);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(barcode);

CREATE INDEX IF NOT EXISTS idx_inventory_business ON public.inventory(business_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product ON public.inventory(product_id);

CREATE INDEX IF NOT EXISTS idx_customers_business ON public.customers(business_id);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON public.customers(phone);

CREATE INDEX IF NOT EXISTS idx_sales_business ON public.sales(business_id);
CREATE INDEX IF NOT EXISTS idx_sales_customer ON public.sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_employee ON public.sales(employee_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON public.sale_items(product_id);

CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments(sale_id);

-- ----------------------------------------------------------------------------
-- 3. UPDATED_AT TRIGGERS
-- ----------------------------------------------------------------------------

CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_businesses_updated_at BEFORE UPDATE ON public.businesses FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- 4. RLS HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

-- Check if current authenticated user is an Admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

-- Get business_id associated with current authenticated user
CREATE OR REPLACE FUNCTION public.get_user_business_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT b.id FROM public.businesses b WHERE b.owner_id = auth.uid()
    UNION ALL
    SELECT e.business_id FROM public.employees e WHERE e.profile_id = auth.uid() AND e.status = 'active'
    LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- 5. ENABLE ROW LEVEL SECURITY (RLS)
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 6. RLS POLICIES
-- ----------------------------------------------------------------------------

-- PROFILES POLICIES
CREATE POLICY "Users can view their own profile or business peers"
ON public.profiles FOR SELECT
USING (
    id = auth.uid()
    OR public.is_admin()
    OR id IN (
        SELECT e.profile_id FROM public.employees e WHERE e.business_id = public.get_user_business_id()
    )
);

CREATE POLICY "Users can insert their own profile on signup"
ON public.profiles FOR INSERT
WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update their own profile or admins update any"
ON public.profiles FOR UPDATE
USING (id = auth.uid() OR public.is_admin())
WITH CHECK (id = auth.uid() OR public.is_admin());

-- BUSINESSES POLICIES
CREATE POLICY "Members can view their business"
ON public.businesses FOR SELECT
USING (owner_id = auth.uid() OR id = public.get_user_business_id());

CREATE POLICY "Admins can create a business"
ON public.businesses FOR INSERT
WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Admins can update their business"
ON public.businesses FOR UPDATE
USING (owner_id = auth.uid() OR (public.is_admin() AND id = public.get_user_business_id()))
WITH CHECK (owner_id = auth.uid() OR (public.is_admin() AND id = public.get_user_business_id()));

-- EMPLOYEES POLICIES
CREATE POLICY "Members can view business employees"
ON public.employees FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Admins can manage employees"
ON public.employees FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- CATEGORIES POLICIES
CREATE POLICY "Members can view business categories"
ON public.categories FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Admins can manage categories"
ON public.categories FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- PRODUCTS POLICIES
CREATE POLICY "Members can view business products"
ON public.products FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Admins can manage products"
ON public.products FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- INVENTORY POLICIES
CREATE POLICY "Members can view inventory logs"
ON public.inventory FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Members can insert inventory logs on sales/restock"
ON public.inventory FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

CREATE POLICY "Admins can manage inventory logs"
ON public.inventory FOR ALL
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- CUSTOMERS POLICIES
CREATE POLICY "Members can view business customers"
ON public.customers FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Members can create or update customers"
ON public.customers FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

CREATE POLICY "Members can update customers"
ON public.customers FOR UPDATE
USING (business_id = public.get_user_business_id())
WITH CHECK (business_id = public.get_user_business_id());

CREATE POLICY "Admins can delete customers"
ON public.customers FOR DELETE
USING (public.is_admin() AND business_id = public.get_user_business_id());

-- SALES POLICIES
CREATE POLICY "Members can view business sales"
ON public.sales FOR SELECT
USING (business_id = public.get_user_business_id());

CREATE POLICY "Members can create sales"
ON public.sales FOR INSERT
WITH CHECK (business_id = public.get_user_business_id());

CREATE POLICY "Admins can update sales"
ON public.sales FOR UPDATE
USING (public.is_admin() AND business_id = public.get_user_business_id())
WITH CHECK (public.is_admin() AND business_id = public.get_user_business_id());

-- SALE ITEMS POLICIES
CREATE POLICY "Members can view sale items"
ON public.sale_items FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = sale_items.sale_id AND s.business_id = public.get_user_business_id()
    )
);

CREATE POLICY "Members can create sale items"
ON public.sale_items FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = sale_items.sale_id AND s.business_id = public.get_user_business_id()
    )
);

-- PAYMENTS POLICIES
CREATE POLICY "Members can view payments"
ON public.payments FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = payments.sale_id AND s.business_id = public.get_user_business_id()
    )
);

CREATE POLICY "Members can create payments"
ON public.payments FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = payments.sale_id AND s.business_id = public.get_user_business_id()
    )
);
