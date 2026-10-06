-- Migration: 014_fix_get_assignable_auth_users_rpc_types.sql
-- Description: Fixes return query type structure mismatch in get_assignable_auth_users RPC by explicitly casting all returned columns to match the declared RETURNS TABLE (id UUID, email TEXT, full_name TEXT, role TEXT) signature.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_assignable_auth_users()
RETURNS TABLE (
    id UUID,
    email TEXT,
    full_name TEXT,
    role TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- 1. Security Check: Caller must be authenticated
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 2. Authorization Check: Caller must be an Admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can list assignable auth users.';
    END IF;

    -- 3. Return assignable Auth users with explicit column type casts matching output signature
    RETURN QUERY
    SELECT
        u.id::UUID AS id,
        u.email::TEXT AS email,
        COALESCE(p.full_name::TEXT, split_part(u.email::TEXT, '@', 1)::TEXT)::TEXT AS full_name,
        COALESCE(p.role::TEXT, 'unassigned'::TEXT)::TEXT AS role
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    WHERE p.role IS NULL OR p.role <> 'admin'
    ORDER BY u.created_at DESC;
END;
$$;

-- Explicitly revoke execution permissions from PUBLIC and anon
REVOKE ALL ON FUNCTION public.get_assignable_auth_users() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_assignable_auth_users() FROM anon;

-- Grant execution permission strictly to authenticated users (RPC enforces public.is_admin() internally)
GRANT EXECUTE ON FUNCTION public.get_assignable_auth_users() TO authenticated;

COMMIT;
