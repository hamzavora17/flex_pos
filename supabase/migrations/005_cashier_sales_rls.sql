-- Migration: 005_cashier_sales_rls.sql
-- Description: Enforces cashier-isolated RLS for sales, sale_items, and payments so cashiers can only view their own sales history.

-- 1. Update RLS policy on sales for SELECT
DROP POLICY IF EXISTS "Members can view sales" ON public.sales;
DROP POLICY IF EXISTS "Cashiers view own sales, admins view store sales" ON public.sales;

CREATE POLICY "Cashiers view own sales, admins view store sales" ON public.sales
    FOR SELECT USING (
        business_id = public.get_user_business_id() AND (
            public.is_admin() OR employee_id = auth.uid()
        )
    );

-- 2. Update RLS policy on sale_items for SELECT
DROP POLICY IF EXISTS "Members can view sale items" ON public.sale_items;
DROP POLICY IF EXISTS "Cashiers view own sale items, admins view store sale items" ON public.sale_items;

CREATE POLICY "Cashiers view own sale items, admins view store sale items" ON public.sale_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.sales s
            WHERE s.id = sale_items.sale_id
              AND s.business_id = public.get_user_business_id()
              AND (public.is_admin() OR s.employee_id = auth.uid())
        )
    );

-- 3. Update RLS policy on payments for SELECT
DROP POLICY IF EXISTS "Members can view payments" ON public.payments;
DROP POLICY IF EXISTS "Cashiers view own sale payments, admins view store payments" ON public.payments;

CREATE POLICY "Cashiers view own sale payments, admins view store payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.sales s
            WHERE s.id = payments.sale_id
              AND s.business_id = public.get_user_business_id()
              AND (public.is_admin() OR s.employee_id = auth.uid())
        )
    );
