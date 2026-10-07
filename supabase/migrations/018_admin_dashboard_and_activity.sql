-- Migration: 018_admin_dashboard_and_activity.sql
-- Description: Creates activity_logs, system_settings, adds status to businesses, adds Admin RLS policies, and defines RPCs for live Admin Panel analytics.

BEGIN;

-- 1. ADD STATUS TO BUSINESSES TABLE IF NOT EXISTS
ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'archived'));

-- 2. SYSTEM SETTINGS TABLE
CREATE TABLE IF NOT EXISTS public.system_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- Seed default system settings
INSERT INTO public.system_settings (key, value, description) VALUES
('currency_symbol', '₹', 'Default currency symbol displayed in the application'),
('default_tax_rate', '0.00', 'Default tax percentage rate applied to sales'),
('allow_cashier_discounts', 'true', 'Whether cashiers are permitted to apply discounts at checkout'),
('min_stock_alert_threshold', '5', 'Global minimum stock level triggering low stock alerts'),
('receipt_header_text', 'Thank you for shopping with FlexPOS!', 'Default message printed at the top of receipts'),
('auto_lock_shift_hours', '12', 'Automatic shift timeout threshold in hours')
ON CONFLICT (key) DO NOTHING;

-- Enable RLS on system_settings
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can view system settings" ON public.system_settings;
CREATE POLICY "Anyone authenticated can view system settings" ON public.system_settings
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins can update system settings" ON public.system_settings;
CREATE POLICY "Admins can update system settings" ON public.system_settings
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- 3. ACTIVITY LOGS TABLE
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    type TEXT NOT NULL, -- e.g. 'sale', 'return', 'business_created', 'business_updated', 'user_created', 'role_changed', 'setting_changed'
    title TEXT NOT NULL,
    details TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON public.activity_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_business ON public.activity_logs(business_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_type ON public.activity_logs(type);

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all activity logs" ON public.activity_logs;
CREATE POLICY "Admins can view all activity logs" ON public.activity_logs
    FOR SELECT TO authenticated
    USING (public.is_admin() OR business_id = public.get_user_business_id());

DROP POLICY IF EXISTS "Authenticated users can insert activity logs" ON public.activity_logs;
CREATE POLICY "Authenticated users can insert activity logs" ON public.activity_logs
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- 4. UPDATE RLS ON BUSINESSES FOR ADMIN SYSTEM-WIDE ACCESS
DROP POLICY IF EXISTS "Admins view all businesses" ON public.businesses;
CREATE POLICY "Admins view all businesses" ON public.businesses
    FOR SELECT TO authenticated
    USING (public.is_admin() OR owner_id = auth.uid() OR id = public.get_user_business_id());

DROP POLICY IF EXISTS "Admins update all businesses" ON public.businesses;
CREATE POLICY "Admins update all businesses" ON public.businesses
    FOR UPDATE TO authenticated
    USING (public.is_admin() OR owner_id = auth.uid())
    WITH CHECK (public.is_admin() OR owner_id = auth.uid());

-- 5. AUTOMATIC TRIGGERS FOR ACTIVITY LOGS
-- A. Trigger for Business events
CREATE OR REPLACE FUNCTION public.log_business_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.activity_logs (business_id, user_id, type, title, details)
        VALUES (NEW.id, auth.uid(), 'business_created', 'New Business Registered', 'Business "' || NEW.business_name || '" was created.');
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            INSERT INTO public.activity_logs (business_id, user_id, type, title, details)
            VALUES (NEW.id, auth.uid(), 'business_updated', 'Business Status Changed', 'Business "' || NEW.business_name || '" status changed to ' || UPPER(NEW.status) || '.');
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_business_activity ON public.businesses;
CREATE TRIGGER trg_log_business_activity
    AFTER INSERT OR UPDATE ON public.businesses
    FOR EACH ROW EXECUTE FUNCTION public.log_business_activity();

-- B. Trigger for Sales events
CREATE OR REPLACE FUNCTION public.log_sale_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'completed' THEN
        INSERT INTO public.activity_logs (business_id, user_id, type, title, details, metadata)
        VALUES (
            NEW.business_id,
            NEW.employee_id,
            'sale',
            'Sale Completed (' || NEW.invoice_number || ')',
            'Amount: ' || NEW.total::TEXT,
            jsonb_build_object('sale_id', NEW.id, 'invoice_number', NEW.invoice_number, 'total', NEW.total)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_sale_activity ON public.sales;
CREATE TRIGGER trg_log_sale_activity
    AFTER INSERT ON public.sales
    FOR EACH ROW EXECUTE FUNCTION public.log_sale_activity();

-- C. Trigger for Returns events
CREATE OR REPLACE FUNCTION public.log_return_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'approved' THEN
        INSERT INTO public.activity_logs (business_id, user_id, type, title, details, metadata)
        VALUES (
            NEW.business_id,
            NEW.employee_id,
            'return',
            'Refund Processed',
            'Refund Amount: ' || NEW.refund_amount::TEXT,
            jsonb_build_object('return_id', NEW.id, 'sale_id', NEW.sale_id, 'refund_amount', NEW.refund_amount)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_return_activity ON public.sale_returns;
CREATE TRIGGER trg_log_return_activity
    AFTER INSERT ON public.sale_returns
    FOR EACH ROW EXECUTE FUNCTION public.log_return_activity();

-- D. Trigger for Employee / Profile role changes
CREATE OR REPLACE FUNCTION public.log_profile_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.activity_logs (user_id, type, title, details)
        VALUES (NEW.id, 'user_created', 'New User Registered', 'User ' || NEW.email || ' joined as ' || UPPER(NEW.role) || '.');
    ELSIF TG_OP = 'UPDATE' AND OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO public.activity_logs (user_id, type, title, details)
        VALUES (NEW.id, 'role_changed', 'User Role Changed', 'User ' || NEW.email || ' role changed from ' || UPPER(OLD.role) || ' to ' || UPPER(NEW.role) || '.');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_profile_activity ON public.profiles;
CREATE TRIGGER trg_log_profile_activity
    AFTER INSERT OR UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.log_profile_activity();


-- 6. RPC: GET ADMIN DASHBOARD STATS
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_today_start TIMESTAMPTZ := date_trunc('day', v_now);
    v_week_start TIMESTAMPTZ := date_trunc('week', v_now);
    v_month_start TIMESTAMPTZ := date_trunc('month', v_now);
    v_prev_month_start TIMESTAMPTZ := date_trunc('month', v_now - INTERVAL '1 month');
    v_prev_month_end TIMESTAMPTZ := v_month_start - INTERVAL '1 microsecond';

    -- Business metrics
    v_total_businesses INT;
    v_active_businesses INT;
    v_inactive_businesses INT;
    v_businesses_created_today INT;
    v_businesses_created_week INT;
    v_businesses_created_month INT;

    -- User metrics
    v_total_users INT;
    v_active_users INT;
    v_inactive_users INT;
    v_admin_count INT;
    v_manager_count INT;
    v_cashier_count INT;
    v_users_created_today INT;
    v_users_created_month INT;

    -- Revenue / Sales metrics
    v_today_sales_total NUMERIC := 0;
    v_today_refunds_total NUMERIC := 0;
    v_today_net_revenue NUMERIC := 0;
    v_today_transactions INT := 0;
    v_today_avg_tx_value NUMERIC := 0;

    v_week_sales_total NUMERIC := 0;
    v_week_refunds_total NUMERIC := 0;
    v_week_net_revenue NUMERIC := 0;

    v_month_sales_total NUMERIC := 0;
    v_month_refunds_total NUMERIC := 0;
    v_month_net_revenue NUMERIC := 0;

    v_prev_month_sales_total NUMERIC := 0;
    v_prev_month_refunds_total NUMERIC := 0;
    v_prev_month_net_revenue NUMERIC := 0;

    v_revenue_growth_pct NUMERIC := 0;
    v_result JSONB;
BEGIN
    -- Authorization check
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can access admin dashboard statistics.';
    END IF;

    -- A. Business Metrics
    SELECT COUNT(*) INTO v_total_businesses FROM public.businesses;
    SELECT COUNT(*) INTO v_active_businesses FROM public.businesses WHERE status = 'active';
    SELECT COUNT(*) INTO v_inactive_businesses FROM public.businesses WHERE status IN ('inactive', 'suspended', 'archived');
    SELECT COUNT(*) INTO v_businesses_created_today FROM public.businesses WHERE created_at >= v_today_start;
    SELECT COUNT(*) INTO v_businesses_created_week FROM public.businesses WHERE created_at >= v_week_start;
    SELECT COUNT(*) INTO v_businesses_created_month FROM public.businesses WHERE created_at >= v_month_start;

    -- B. User Metrics
    SELECT COUNT(*) INTO v_total_users FROM public.profiles;
    SELECT COUNT(*) INTO v_admin_count FROM public.profiles WHERE role = 'admin';
    SELECT COUNT(*) INTO v_manager_count FROM public.profiles WHERE role = 'manager';
    SELECT COUNT(*) INTO v_cashier_count FROM public.profiles WHERE role IN ('cashier', 'employee');

    -- Active users: employees with active status + admins
    SELECT COUNT(DISTINCT id) INTO v_active_users
    FROM public.profiles p
    WHERE p.role = 'admin' OR EXISTS (
        SELECT 1 FROM public.employees e WHERE e.profile_id = p.id AND e.status = 'active'
    );
    v_inactive_users := GREATEST(0, v_total_users - v_active_users);

    SELECT COUNT(*) INTO v_users_created_today FROM public.profiles WHERE created_at >= v_today_start;
    SELECT COUNT(*) INTO v_users_created_month FROM public.profiles WHERE created_at >= v_month_start;

    -- C. Revenue & Sales Metrics
    -- Today
    SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_today_sales_total, v_today_transactions
    FROM public.sales
    WHERE status = 'completed' AND created_at >= v_today_start;

    SELECT COALESCE(SUM(refund_amount), 0)
    INTO v_today_refunds_total
    FROM public.sale_returns
    WHERE status = 'approved' AND created_at >= v_today_start;

    v_today_net_revenue := v_today_sales_total - v_today_refunds_total;
    IF v_today_transactions > 0 THEN
        v_today_avg_tx_value := ROUND(v_today_net_revenue / v_today_transactions, 2);
    ELSE
        v_today_avg_tx_value := 0;
    END IF;

    -- This Week
    SELECT COALESCE(SUM(total), 0) INTO v_week_sales_total FROM public.sales WHERE status = 'completed' AND created_at >= v_week_start;
    SELECT COALESCE(SUM(refund_amount), 0) INTO v_week_refunds_total FROM public.sale_returns WHERE status = 'approved' AND created_at >= v_week_start;
    v_week_net_revenue := v_week_sales_total - v_week_refunds_total;

    -- This Month
    SELECT COALESCE(SUM(total), 0) INTO v_month_sales_total FROM public.sales WHERE status = 'completed' AND created_at >= v_month_start;
    SELECT COALESCE(SUM(refund_amount), 0) INTO v_month_refunds_total FROM public.sale_returns WHERE status = 'approved' AND created_at >= v_month_start;
    v_month_net_revenue := v_month_sales_total - v_month_refunds_total;

    -- Previous Month
    SELECT COALESCE(SUM(total), 0) INTO v_prev_month_sales_total FROM public.sales WHERE status = 'completed' AND created_at >= v_prev_month_start AND created_at <= v_prev_month_end;
    SELECT COALESCE(SUM(refund_amount), 0) INTO v_prev_month_refunds_total FROM public.sale_returns WHERE status = 'approved' AND created_at >= v_prev_month_start AND created_at <= v_prev_month_end;
    v_prev_month_net_revenue := v_prev_month_sales_total - v_prev_month_refunds_total;

    -- Revenue Growth Percentage
    IF v_prev_month_net_revenue > 0 THEN
        v_revenue_growth_pct := ROUND(((v_month_net_revenue - v_prev_month_net_revenue) / v_prev_month_net_revenue) * 100, 2);
    ELSIF v_month_net_revenue > 0 THEN
        v_revenue_growth_pct := 100.00;
    ELSE
        v_revenue_growth_pct := 0.00;
    END IF;

    -- Build JSON result
    v_result := jsonb_build_object(
        'business_metrics', jsonb_build_object(
            'total', v_total_businesses,
            'active', v_active_businesses,
            'inactive', v_inactive_businesses,
            'created_today', v_businesses_created_today,
            'created_week', v_businesses_created_week,
            'created_month', v_businesses_created_month
        ),
        'user_metrics', jsonb_build_object(
            'total', v_total_users,
            'active', v_active_users,
            'inactive', v_inactive_users,
            'admins', v_admin_count,
            'managers', v_manager_count,
            'cashiers', v_cashier_count,
            'created_today', v_users_created_today,
            'created_month', v_users_created_month
        ),
        'revenue_metrics', jsonb_build_object(
            'today_revenue', v_today_net_revenue,
            'today_transactions', v_today_transactions,
            'today_avg_tx_value', v_today_avg_tx_value,
            'week_revenue', v_week_net_revenue,
            'month_revenue', v_month_net_revenue,
            'prev_month_revenue', v_prev_month_net_revenue,
            'revenue_growth_pct', v_revenue_growth_pct
        )
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_stats() TO authenticated;


-- 7. RPC: GET REVENUE CHART DATA
CREATE OR REPLACE FUNCTION public.get_admin_revenue_chart_data(
    p_period TEXT DEFAULT 'last_7_days',
    p_start_date TIMESTAMPTZ DEFAULT NULL,
    p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ := COALESCE(p_end_date, v_now);
    v_trunc_unit TEXT := 'day';
    v_chart_data JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can access revenue chart data.';
    END IF;

    IF p_period = 'today' THEN
        v_start := COALESCE(p_start_date, date_trunc('day', v_now));
        v_trunc_unit := 'hour';
    ELSIF p_period = 'last_7_days' THEN
        v_start := COALESCE(p_start_date, date_trunc('day', v_now - INTERVAL '6 days'));
        v_trunc_unit := 'day';
    ELSIF p_period = 'last_30_days' THEN
        v_start := COALESCE(p_start_date, date_trunc('day', v_now - INTERVAL '29 days'));
        v_trunc_unit := 'day';
    ELSIF p_period = 'this_month' THEN
        v_start := COALESCE(p_start_date, date_trunc('month', v_now));
        v_trunc_unit := 'day';
    ELSIF p_period = 'custom' THEN
        v_start := COALESCE(p_start_date, date_trunc('day', v_now - INTERVAL '30 days'));
        v_trunc_unit := 'day';
    ELSE
        v_start := date_trunc('day', v_now - INTERVAL '6 days');
        v_trunc_unit := 'day';
    END IF;

    WITH time_series AS (
        SELECT generate_series(v_start, v_end, ('1 ' || v_trunc_unit)::INTERVAL) AS bucket_time
    ),
    sales_buckets AS (
        SELECT
            date_trunc(v_trunc_unit, created_at) AS bucket_time,
            COALESCE(SUM(total), 0) AS gross_sales,
            COUNT(*) AS tx_count
        FROM public.sales
        WHERE status = 'completed' AND created_at >= v_start AND created_at <= v_end
        GROUP BY 1
    ),
    refund_buckets AS (
        SELECT
            date_trunc(v_trunc_unit, created_at) AS bucket_time,
            COALESCE(SUM(refund_amount), 0) AS total_refunds
        FROM public.sale_returns
        WHERE status = 'approved' AND created_at >= v_start AND created_at <= v_end
        GROUP BY 1
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'timestamp', ts.bucket_time,
            'revenue', COALESCE(sb.gross_sales, 0) - COALESCE(rb.total_refunds, 0),
            'gross_sales', COALESCE(sb.gross_sales, 0),
            'refunds', COALESCE(rb.total_refunds, 0),
            'transactions', COALESCE(sb.tx_count, 0)
        ) ORDER BY ts.bucket_time ASC
    ) INTO v_chart_data
    FROM time_series ts
    LEFT JOIN sales_buckets sb ON sb.bucket_time = ts.bucket_time
    LEFT JOIN refund_buckets rb ON rb.bucket_time = ts.bucket_time;

    RETURN COALESCE(v_chart_data, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_revenue_chart_data(TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;


-- 8. RPC: CREATE BUSINESS BY ADMIN
CREATE OR REPLACE FUNCTION public.create_business_by_admin(
    p_business_name TEXT,
    p_owner_id UUID DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner_uuid UUID;
    v_business_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can create businesses.';
    END IF;

    IF p_business_name IS NULL OR TRIM(p_business_name) = '' THEN
        RAISE EXCEPTION 'Business name cannot be empty.';
    END IF;

    v_owner_uuid := COALESCE(p_owner_id, auth.uid());

    INSERT INTO public.businesses (
        business_name, owner_id, email, phone, address, status
    ) VALUES (
        TRIM(p_business_name), v_owner_uuid, p_email, p_phone, p_address, 'active'
    ) RETURNING id INTO v_business_id;

    RETURN jsonb_build_object(
        'success', true,
        'business_id', v_business_id,
        'business_name', p_business_name
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_business_by_admin(TEXT, UUID, TEXT, TEXT, TEXT) TO authenticated;


-- 9. RPC: MANAGE BUSINESS STATUS
CREATE OR REPLACE FUNCTION public.manage_business_status(
    p_business_id UUID,
    p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can modify business status.';
    END IF;

    IF p_status NOT IN ('active', 'inactive', 'suspended', 'archived') THEN
        RAISE EXCEPTION 'Invalid status. Allowed statuses: active, inactive, suspended, archived.';
    END IF;

    UPDATE public.businesses
    SET status = p_status,
        updated_at = NOW()
    WHERE id = p_business_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Business ID % not found.', p_business_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'business_id', p_business_id, 'status', p_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.manage_business_status(UUID, TEXT) TO authenticated;

COMMIT;
