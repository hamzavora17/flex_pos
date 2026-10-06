-- Migration: 012_fix_hamza_user_provisioning.sql
-- Description: Ensures proper provisioning for hamza@flexpos.com and admin@flexpos.com in public.profiles and public.employees by resolving actual auth user IDs from auth.users.

BEGIN;

-- 1. Create automatic profile creation trigger for any new auth user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(split_part(NEW.email, '@', 1), 'User'),
        'cashier'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Dynamically provision Hamza and Admin records based on real auth.users IDs
DO $$
DECLARE
    v_admin_id UUID;
    v_hamza_id UUID;
    v_business_id UUID;
BEGIN
    -- Resolve active business ID (fallback to default store)
    SELECT id INTO v_business_id FROM public.businesses ORDER BY created_at ASC LIMIT 1;
    IF v_business_id IS NULL THEN
        v_business_id := 'b0000000-0000-0000-0000-000000000001';
    END IF;

    -- Provision admin@flexpos.com if present in auth.users
    SELECT id INTO v_admin_id FROM auth.users WHERE email = 'admin@flexpos.com';
    IF v_admin_id IS NOT NULL THEN
        INSERT INTO public.profiles (id, email, full_name, role)
        VALUES (v_admin_id, 'admin@flexpos.com', 'Admin User', 'admin')
        ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            role = 'admin';

        UPDATE public.businesses
        SET owner_id = v_admin_id
        WHERE id = v_business_id;
    END IF;

    -- Provision hamza@flexpos.com if present in auth.users
    SELECT id INTO v_hamza_id FROM auth.users WHERE email = 'hamza@flexpos.com';
    IF v_hamza_id IS NOT NULL THEN
        -- Upsert profile with role = 'cashier'
        INSERT INTO public.profiles (id, email, full_name, role)
        VALUES (v_hamza_id, 'hamza@flexpos.com', 'Hamza', 'cashier')
        ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            role = 'cashier';

        -- Upsert employee record linking profile to active business store
        INSERT INTO public.employees (business_id, profile_id, position, status)
        VALUES (v_business_id, v_hamza_id, 'cashier', 'active')
        ON CONFLICT (profile_id) DO UPDATE SET
            business_id = EXCLUDED.business_id,
            position = 'cashier',
            status = 'active';
    END IF;
END $$;

COMMIT;
