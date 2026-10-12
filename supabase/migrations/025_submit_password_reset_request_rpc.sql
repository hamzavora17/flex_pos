-- Migration: Submit Password Reset Request RPC and Check User Exists RPC
-- Description: Creates public.submit_password_reset_request and public.check_user_exists RPCs to validate user existence before creating a password reset request.

CREATE OR REPLACE FUNCTION public.check_user_exists(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user_id UUID;
    v_clean_email TEXT;
BEGIN
    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RETURN FALSE;
    END IF;

    v_clean_email := TRIM(p_email);

    SELECT id INTO v_user_id
    FROM auth.users
    WHERE LOWER(email) = LOWER(v_clean_email);

    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(v_clean_email);
    END IF;

    IF v_user_id IS NULL AND NOT v_clean_email LIKE '%@%' THEN
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(v_clean_email || '@flexpos.com');
    END IF;

    RETURN v_user_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_password_reset_request(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user_id UUID;
    v_clean_email TEXT;
BEGIN
    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RAISE EXCEPTION 'Failed to reset password: Email address is required.';
    END IF;

    v_clean_email := TRIM(p_email);

    -- 1. Check if user exists in auth.users or public.profiles
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE LOWER(email) = LOWER(v_clean_email);

    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(v_clean_email);
    END IF;

    IF v_user_id IS NULL AND NOT v_clean_email LIKE '%@%' THEN
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(v_clean_email || '@flexpos.com');
        IF v_user_id IS NOT NULL THEN
            v_clean_email := v_clean_email || '@flexpos.com';
        END IF;
    END IF;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Failed to reset password: No user account found for "%".', p_email;
    END IF;

    -- 2. Insert into password_reset_requests table
    INSERT INTO public.password_reset_requests (email, status)
    VALUES (v_clean_email, 'pending');

    RETURN jsonb_build_object(
        'success', true,
        'email', v_clean_email,
        'message', 'Password reset request submitted successfully.'
    );
END;
$$;
