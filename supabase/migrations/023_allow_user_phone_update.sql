-- Migration: Allow users to edit their profile phone number and ensure column exists
-- Description: Adds 'phone' column to public.profiles if missing, and updates enforce_profile_role_security() trigger function to allow users to update their own phone number.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone TEXT;

CREATE OR REPLACE FUNCTION public.enforce_profile_role_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT public.is_admin() THEN
            NEW.role := 'cashier';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NOT public.is_admin() THEN
            IF NEW.id IS DISTINCT FROM OLD.id THEN
                RAISE EXCEPTION 'Unauthorized: profile id cannot be changed.';
            END IF;

            IF NEW.role IS DISTINCT FROM OLD.role THEN
                RAISE EXCEPTION 'Unauthorized: only an admin can change role.';
            END IF;

            IF NEW.email IS DISTINCT FROM OLD.email THEN
                RAISE EXCEPTION 'Unauthorized: only an admin can change email.';
            END IF;

            IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
                RAISE EXCEPTION 'Unauthorized: created_at cannot be changed.';
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;
