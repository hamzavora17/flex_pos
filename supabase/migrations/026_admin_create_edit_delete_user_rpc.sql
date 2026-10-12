-- Migration: Admin Create, Edit, and Delete User RPCs (With GoTrue auth.identities Compliance)
-- Description: Enables store administrators to create new user accounts, update profile details/roles, and delete user accounts cleanly.

-- 0. Fix existing auth.users rows and missing auth.identities (e.g. juned@flexpos.com)
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Fix NULLs on auth.users
    UPDATE auth.users
    SET is_sso_user = COALESCE(is_sso_user, false),
        is_anonymous = COALESCE(is_anonymous, false),
        aud = COALESCE(aud, 'authenticated'),
        role = COALESCE(role, 'authenticated'),
        instance_id = COALESCE(instance_id, '00000000-0000-0000-0000-000000000000')
    WHERE is_sso_user IS NULL OR is_anonymous IS NULL OR aud IS NULL OR role IS NULL OR instance_id IS NULL;

    -- Ensure every auth.users row has a corresponding auth.identities row
    FOR r IN
        SELECT u.id, u.email, COALESCE(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)) AS full_name
        FROM auth.users u
        LEFT JOIN auth.identities i ON u.id = i.user_id
        WHERE i.id IS NULL AND u.email IS NOT NULL AND u.email <> ''
    LOOP
        BEGIN
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                provider_id,
                last_sign_in_at,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                r.id,
                jsonb_build_object('sub', r.id::text, 'email', r.email, 'email_verified', true, 'full_name', r.full_name),
                'email',
                r.email,
                NOW(),
                NOW(),
                NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;
END $$;

-- 1. CREATE USER RPC
CREATE OR REPLACE FUNCTION public.admin_create_user(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_role TEXT DEFAULT 'cashier'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_admin_user_id UUID;
    v_target_business_id UUID;
    v_new_user_id UUID;
    v_clean_email TEXT;
    v_clean_name TEXT;
    v_clean_role TEXT;
    v_encrypted_password TEXT;
BEGIN
    -- 1. Security Check: Must be admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can create new users.';
    END IF;

    -- 2. Validate inputs
    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RAISE EXCEPTION 'Email or username is required.';
    END IF;

    v_clean_email := TRIM(p_email);
    IF NOT v_clean_email LIKE '%@%' THEN
        v_clean_email := v_clean_email || '@flexpos.com';
    END IF;

    IF p_password IS NULL OR LENGTH(p_password) < 6 THEN
        RAISE EXCEPTION 'Password must be at least 6 characters.';
    END IF;

    v_clean_name := COALESCE(NULLIF(TRIM(p_full_name), ''), split_part(v_clean_email, '@', 1));
    v_clean_role := LOWER(COALESCE(NULLIF(TRIM(p_role), ''), 'cashier'));

    IF v_clean_role NOT IN ('admin', 'manager', 'cashier', 'employee') THEN
        RAISE EXCEPTION 'Invalid role: %', p_role;
    END IF;

    -- 3. Check if email already exists in auth.users
    IF EXISTS (SELECT 1 FROM auth.users WHERE LOWER(email) = LOWER(v_clean_email)) THEN
        RAISE EXCEPTION 'A user account with email "%" already exists.', v_clean_email;
    END IF;

    -- 4. Generate user UUID and encrypted password
    v_new_user_id := gen_random_uuid();
    v_encrypted_password := crypt(p_password, gen_salt('bf'));

    -- 5. Insert into auth.users with ALL required GoTrue columns
    INSERT INTO auth.users (
        id,
        instance_id,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        role,
        aud,
        is_sso_user,
        is_anonymous,
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change,
        phone_change,
        phone_change_token,
        email_change_token_current,
        reauthentication_token
    ) VALUES (
        v_new_user_id,
        '00000000-0000-0000-0000-000000000000',
        v_clean_email,
        v_encrypted_password,
        NOW(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        jsonb_build_object('full_name', v_clean_name, 'role', v_clean_role),
        NOW(),
        NOW(),
        'authenticated',
        'authenticated',
        false,
        false,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        ''
    );

    -- 6. Insert into auth.identities (Mandatory for Supabase GoTrue authentication)
    BEGIN
        INSERT INTO auth.identities (
            id,
            user_id,
            identity_data,
            provider,
            provider_id,
            last_sign_in_at,
            created_at,
            updated_at
        ) VALUES (
            gen_random_uuid(),
            v_new_user_id,
            jsonb_build_object('sub', v_new_user_id::text, 'email', v_clean_email, 'email_verified', true, 'full_name', v_clean_name),
            'email',
            v_clean_email,
            NOW(),
            NOW(),
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- 7. Insert/Upsert into public.profiles
    INSERT INTO public.profiles (id, email, full_name, role, created_at, updated_at)
    VALUES (v_new_user_id, v_clean_email, v_clean_name, v_clean_role, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name,
        role = EXCLUDED.role,
        updated_at = NOW();

    -- 8. Associate with business store in public.employees
    v_target_business_id := public.get_user_business_id();
    IF v_target_business_id IS NOT NULL AND v_clean_role IN ('manager', 'cashier', 'employee') THEN
        INSERT INTO public.employees (business_id, profile_id, position, status, created_at, updated_at)
        VALUES (v_target_business_id, v_new_user_id, v_clean_role, 'active', NOW(), NOW())
        ON CONFLICT (profile_id) DO UPDATE SET
            position = EXCLUDED.position,
            status = 'active',
            updated_at = NOW();
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_new_user_id,
        'email', v_clean_email,
        'full_name', v_clean_name,
        'role', v_clean_role
    );
END;
$$;

-- 2. UPDATE USER RPC
CREATE OR REPLACE FUNCTION public.admin_update_user(
    p_user_id UUID,
    p_full_name TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_role TEXT DEFAULT NULL,
    p_new_password TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_target_business_id UUID;
    v_clean_email TEXT;
    v_clean_name TEXT;
    v_clean_role TEXT;
    v_encrypted_password TEXT;
BEGIN
    -- 1. Security Check: Must be admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can update users.';
    END IF;

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID parameter is required.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) AND
       NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    -- Update Full Name if provided
    IF p_full_name IS NOT NULL AND TRIM(p_full_name) <> '' THEN
        v_clean_name := TRIM(p_full_name);
        UPDATE public.profiles SET full_name = v_clean_name, updated_at = NOW() WHERE id = p_user_id;
        UPDATE auth.users SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{full_name}', to_jsonb(v_clean_name)), updated_at = NOW() WHERE id = p_user_id;
        UPDATE auth.identities SET identity_data = jsonb_set(COALESCE(identity_data, '{}'::jsonb), '{full_name}', to_jsonb(v_clean_name)), updated_at = NOW() WHERE user_id = p_user_id;
    END IF;

    -- Update Email if provided
    IF p_email IS NOT NULL AND TRIM(p_email) <> '' THEN
        v_clean_email := TRIM(p_email);
        IF NOT v_clean_email LIKE '%@%' THEN
            v_clean_email := v_clean_email || '@flexpos.com';
        END IF;

        IF EXISTS (SELECT 1 FROM auth.users WHERE LOWER(email) = LOWER(v_clean_email) AND id <> p_user_id) THEN
            RAISE EXCEPTION 'Email % is already in use by another account.', v_clean_email;
        END IF;

        UPDATE public.profiles SET email = v_clean_email, updated_at = NOW() WHERE id = p_user_id;
        UPDATE auth.users SET email = v_clean_email, updated_at = NOW() WHERE id = p_user_id;
        UPDATE auth.identities SET provider_id = v_clean_email, identity_data = jsonb_set(COALESCE(identity_data, '{}'::jsonb), '{email}', to_jsonb(v_clean_email)), updated_at = NOW() WHERE user_id = p_user_id;
    END IF;

    -- Update Role if provided
    IF p_role IS NOT NULL AND TRIM(p_role) <> '' THEN
        v_clean_role := LOWER(TRIM(p_role));
        IF v_clean_role IN ('admin', 'manager', 'cashier', 'employee') THEN
            UPDATE public.profiles SET role = v_clean_role, updated_at = NOW() WHERE id = p_user_id;

            v_target_business_id := public.get_user_business_id();
            IF v_target_business_id IS NOT NULL THEN
                INSERT INTO public.employees (business_id, profile_id, position, status, updated_at)
                VALUES (v_target_business_id, p_user_id, v_clean_role, 'active', NOW())
                ON CONFLICT (profile_id) DO UPDATE SET position = EXCLUDED.position, status = 'active', updated_at = NOW();
            END IF;
        END IF;
    END IF;

    -- Update Password if provided
    IF p_new_password IS NOT NULL AND LENGTH(TRIM(p_new_password)) >= 6 THEN
        v_encrypted_password := crypt(TRIM(p_new_password), gen_salt('bf'));
        UPDATE auth.users SET encrypted_password = v_encrypted_password, updated_at = NOW() WHERE id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'message', 'User account updated successfully.'
    );
END;
$$;

-- 3. DELETE USER RPC
CREATE OR REPLACE FUNCTION public.admin_delete_user(
    p_user_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
BEGIN
    -- 1. Security Check: Must be admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can delete users.';
    END IF;

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID is required.';
    END IF;

    IF p_user_id = auth.uid() THEN
        RAISE EXCEPTION 'You cannot delete your own admin account while logged in.';
    END IF;

    -- Delete from auth.identities
    DELETE FROM auth.identities WHERE user_id = p_user_id;

    -- Delete from employees table
    DELETE FROM public.employees WHERE profile_id = p_user_id;

    -- Delete from password_reset_requests
    DELETE FROM public.password_reset_requests WHERE email IN (
        SELECT email FROM public.profiles WHERE id = p_user_id
    );

    -- Delete from profiles
    DELETE FROM public.profiles WHERE id = p_user_id;

    -- Delete from auth.users
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'message', 'User account deleted successfully.'
    );
END;
$$;
