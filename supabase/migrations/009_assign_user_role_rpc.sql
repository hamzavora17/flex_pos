-- Migration: 009_assign_user_role_rpc.sql
-- Description: Creates the secure assign_user_role RPC function enabling store Admins to assign manager and cashier roles within their authorized business store.

CREATE OR REPLACE FUNCTION public.assign_user_role(
    p_target_user_id UUID,
    p_role TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_user_id UUID;
    v_target_business_id UUID;
    v_existing_business_id UUID;
    v_position TEXT;
    v_user_email TEXT;
    v_result jsonb;
BEGIN
    -- 1. Security Check: Must be authenticated
    v_admin_user_id := auth.uid();
    IF v_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 2. Authorization Check: Must be an Admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can assign user roles.';
    END IF;

    -- 3. Validate requested role (restricted to store staff roles: manager, cashier, employee)
    IF p_role NOT IN ('manager', 'cashier', 'employee') THEN
        RAISE EXCEPTION 'Invalid role specified: %. Role assignment is restricted to store staff roles (manager, cashier, employee).', p_role;
    END IF;

    -- 4. Explicit Auth User Existence Check
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users
        WHERE id = p_target_user_id
    ) THEN
        RAISE EXCEPTION 'Target user ID % does not exist in Auth records.', p_target_user_id;
    END IF;

    -- Retrieve target user's actual email from auth.users
    SELECT email INTO v_user_email FROM auth.users WHERE id = p_target_user_id;

    -- 5. Server-side Target Business Determination (Never trust client business ID)
    v_target_business_id := public.get_user_business_id();

    IF v_target_business_id IS NULL THEN
        RAISE EXCEPTION 'No active business association found for current administrator.';
    END IF;

    -- 6. Check existing store association (Prevent accidental cross-business reassignment)
    SELECT business_id INTO v_existing_business_id
    FROM public.employees
    WHERE profile_id = p_target_user_id;

    IF v_existing_business_id IS NOT NULL AND v_existing_business_id <> v_target_business_id THEN
        RAISE EXCEPTION 'User is already assigned as an employee to a different business store (%). Reassignment across businesses is restricted.', v_existing_business_id;
    END IF;

    -- 7. Derive employee position directly from approved role
    v_position := p_role;

    -- 8. Upsert target profile in public.profiles
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
        UPDATE public.profiles
        SET role = p_role,
            email = COALESCE(email, v_user_email),
            updated_at = NOW()
        WHERE id = p_target_user_id;
    ELSE
        INSERT INTO public.profiles (id, email, full_name, role)
        VALUES (
            p_target_user_id,
            v_user_email,
            COALESCE(split_part(v_user_email, '@', 1), 'User'),
            p_role
        );
    END IF;

    -- 9. Upsert store employee record in public.employees (Preserve existing business_id on update)
    INSERT INTO public.employees (
        business_id,
        profile_id,
        position,
        status,
        updated_at
    ) VALUES (
        v_target_business_id,
        p_target_user_id,
        v_position,
        'active',
        NOW()
    )
    ON CONFLICT (profile_id) DO UPDATE SET
        position = EXCLUDED.position,
        status = 'active',
        updated_at = NOW();

    v_result := jsonb_build_object(
        'success', true,
        'profile_id', p_target_user_id,
        'role', p_role,
        'business_id', v_target_business_id,
        'position', v_position
    );

    RETURN v_result;
END;
$$;

-- Grant EXECUTE permission to authenticated users (RPC enforces public.is_admin() internally)
GRANT EXECUTE ON FUNCTION public.assign_user_role(UUID, TEXT) TO authenticated;
