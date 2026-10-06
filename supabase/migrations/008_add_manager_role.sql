-- Migration: 008_add_manager_role.sql
-- Description: Safely adds 'manager' and 'cashier' roles, secures profiles role column against privilege escalation, and defines role helper functions.

-- ----------------------------------------------------------------------------
-- 1. SAFELY UPDATE CHECK CONSTRAINT ON PUBLIC.PROFILES ROLE COLUMN
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin', 'manager', 'cashier', 'employee'));

-- ----------------------------------------------------------------------------
-- 2. SQL HELPER FUNCTIONS FOR ROLE CHECKS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'manager'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_manager()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'manager')
    );
$$;

-- ----------------------------------------------------------------------------
-- 3. PREVENT ROLE SELF-PROMOTION / PRIVILEGE ESCALATION TRIGGER
-- ----------------------------------------------------------------------------
-- Guarantees that non-admin users cannot change their profiles.role or insert escalated roles.
CREATE OR REPLACE FUNCTION public.enforce_profile_role_security()
RETURNS TRIGGER AS $$
BEGIN
    -- On INSERT: If caller is not an admin, prevent self-assigning admin or manager
    IF TG_OP = 'INSERT' THEN
        IF NOT public.is_admin() THEN
            IF NEW.role IS NULL OR NEW.role IN ('admin', 'manager') THEN
                NEW.role := 'cashier';
            END IF;
        END IF;
    -- On UPDATE: If caller is not an admin, block any attempt to alter NEW.role
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.role IS DISTINCT FROM OLD.role THEN
            IF NOT public.is_admin() THEN
                RAISE EXCEPTION 'Unauthorized: Only administrators can modify user roles.';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS enforce_profile_role_security_trigger ON public.profiles;
CREATE TRIGGER enforce_profile_role_security_trigger
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profile_role_security();
