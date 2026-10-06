-- Migration: 013_fix_manager_user_provisioning.sql
-- Description: Provision manager@flexpos.com dynamically by resolving their auth user ID from auth.users and assigning the 'manager' role in public.profiles and public.employees.

BEGIN;

DO $$
DECLARE
    v_manager_id UUID;
    v_business_id UUID;
BEGIN
    -- 1. Resolve active store business ID
    SELECT id INTO v_business_id FROM public.businesses ORDER BY created_at ASC LIMIT 1;
    IF v_business_id IS NULL THEN
        v_business_id := 'b0000000-0000-0000-0000-000000000001';
    END IF;

    -- 2. Resolve manager@flexpos.com auth user ID from auth.users
    SELECT id INTO v_manager_id FROM auth.users WHERE email = 'manager@flexpos.com';

    IF v_manager_id IS NOT NULL THEN
        -- Upsert profile with authoritative role = 'manager'
        INSERT INTO public.profiles (id, email, full_name, role)
        VALUES (v_manager_id, 'manager@flexpos.com', 'Store Manager', 'manager')
        ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            role = 'manager';

        -- Upsert employee record linking profile to active business store
        INSERT INTO public.employees (business_id, profile_id, position, status)
        VALUES (v_business_id, v_manager_id, 'manager', 'active')
        ON CONFLICT (profile_id) DO UPDATE SET
            business_id = EXCLUDED.business_id,
            position = 'manager',
            status = 'active';
    END IF;
END $$;

COMMIT;
