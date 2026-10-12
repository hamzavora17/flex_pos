-- Migration: Password Reset Requests and Admin Reset RPC
-- Description: Creates public.password_reset_requests table for user forgot-password notifications and public.admin_reset_user_password RPC for admin password updates.

-- 1. PASSWORD RESET REQUESTS TABLE
CREATE TABLE IF NOT EXISTS public.password_reset_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'rejected')),
    admin_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Index for fast query by status and date
CREATE INDEX IF NOT EXISTS idx_password_reset_requests_status ON public.password_reset_requests(status);
CREATE INDEX IF NOT EXISTS idx_password_reset_requests_created_at ON public.password_reset_requests(created_at DESC);

-- Enable RLS
ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

-- POLICIES
-- Anyone (authenticated or anonymous on login page) can submit a password reset request
DROP POLICY IF EXISTS "Anyone can insert password reset request" ON public.password_reset_requests;
CREATE POLICY "Anyone can insert password reset request"
ON public.password_reset_requests
FOR INSERT
WITH CHECK (true);

-- Admins can view all password reset requests
DROP POLICY IF EXISTS "Admins can view password reset requests" ON public.password_reset_requests;
CREATE POLICY "Admins can view password reset requests"
ON public.password_reset_requests
FOR SELECT
USING (public.is_admin());

-- Admins can update password reset requests
DROP POLICY IF EXISTS "Admins can update password reset requests" ON public.password_reset_requests;
CREATE POLICY "Admins can update password reset requests"
ON public.password_reset_requests
FOR UPDATE
USING (public.is_admin());

-- 2. ADMIN RESET USER PASSWORD RPC
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(
    p_request_id UUID DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_new_password TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user_id UUID;
    v_encrypted_password TEXT;
BEGIN
    -- 1. Verify caller is admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can reset user passwords.';
    END IF;

    IF p_email IS NULL OR TRIM(p_email) = '' THEN
        RAISE EXCEPTION 'Email parameter is required.';
    END IF;

    IF p_new_password IS NULL OR LENGTH(p_new_password) < 6 THEN
        RAISE EXCEPTION 'New password must be at least 6 characters.';
    END IF;

    -- 2. Find user in auth.users by email
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE LOWER(email) = LOWER(TRIM(p_email));

    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(TRIM(p_email));
    END IF;

    IF v_user_id IS NULL THEN
        -- Check if p_email is username (e.g. 'hamza' -> 'hamza@flexpos.com')
        SELECT id INTO v_user_id
        FROM public.profiles
        WHERE LOWER(email) = LOWER(TRIM(p_email) || '@flexpos.com');
    END IF;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No user account found for "%".', p_email;
    END IF;

    -- 3. Update password in auth.users
    v_encrypted_password := crypt(p_new_password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = v_encrypted_password,
        updated_at = NOW()
    WHERE id = v_user_id;

    -- 4. Mark request as resolved in password_reset_requests if p_request_id is provided
    IF p_request_id IS NOT NULL THEN
        UPDATE public.password_reset_requests
        SET status = 'resolved',
            admin_notes = 'Password updated by admin at ' || NOW()::text,
            resolved_at = NOW()
        WHERE id = p_request_id;
    END IF;

    -- 5. Log activity safely
    BEGIN
        INSERT INTO public.activity_logs (
            user_id,
            type,
            title,
            details
        ) VALUES (
            auth.uid(),
            'user_password_reset',
            'Password Reset',
            'Admin reset password for ' || p_email
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'message', 'Password successfully updated for ' || p_email
    );
END;
$$;

-- Enable Realtime for password_reset_requests safely
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'password_reset_requests'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.password_reset_requests;
        END IF;
    END IF;
END $$;
