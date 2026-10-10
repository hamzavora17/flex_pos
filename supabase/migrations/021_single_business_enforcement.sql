-- Migration: 021_single_business_enforcement.sql
-- Description: Idempotent, concurrency-safe single-business database security enforcement.
-- Validates verified business record, column schema (businesses.name), constraint/index definitions,
-- trigger presence, and business_memberships schema (active IS TRUE). Installs atomic single-row constraint,
-- prevents deletion/truncation of primary store, fixes log_business_activity column reference (NEW.name),
-- revokes public/anon direct table INSERT/TRUNCATE and RPC grants, and hardens get_user_business_id and get_user_businesses.

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. PRE-MIGRATION SAFETY & SCHEMA VERIFICATION BLOCK
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_count INT;
    v_invalid_memberships INT;
    v_invalid_is_single INT;
BEGIN
    -- 1. Validate business record count
    SELECT COUNT(*) INTO v_count FROM public.businesses;
    IF v_count = 0 THEN
        RAISE EXCEPTION 'Single-business enforcement halted: No business record found in public.businesses. Explicit business initialization is required.';
    ELSIF v_count > 1 THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Multiple business records (%) found in public.businesses. Resolve duplicate records manually before applying this migration.', v_count;
    END IF;

    -- 2. Validate expected column 'name' exists on public.businesses and is VARCHAR/TEXT NOT NULL
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'businesses' AND column_name = 'name'
          AND data_type IN ('character varying', 'text') AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Column "name" on public.businesses was not found or is nullable/non-text.';
    END IF;

    -- 3. Validate mandatory business_memberships table & required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'business_memberships'
    ) THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Required table "business_memberships" is missing from public schema.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'business_memberships'
          AND column_name = 'business_id' AND data_type = 'uuid' AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'business_memberships'
          AND column_name = 'user_id' AND data_type = 'uuid' AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'business_memberships'
          AND column_name = 'active' AND data_type = 'boolean'
    ) THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Table "business_memberships" lacks required columns (business_id UUID NOT NULL, user_id UUID NOT NULL, active BOOLEAN).';
    END IF;

    -- Check for orphan memberships pointing to non-existent business IDs
    EXECUTE 'SELECT COUNT(*) FROM public.business_memberships bm WHERE NOT EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = bm.business_id)' INTO v_invalid_memberships;
    IF v_invalid_memberships > 0 THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Found % invalid membership records referencing non-existent business IDs.', v_invalid_memberships;
    END IF;

    -- 4. Validate is_single_business column definition, default, and existing row values if already present
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'businesses' AND column_name = 'is_single_business'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'businesses' AND column_name = 'is_single_business'
              AND data_type = 'boolean' AND is_nullable = 'NO' AND (column_default = 'true' OR column_default = 'true::boolean')
        ) THEN
            RAISE EXCEPTION 'Single-business enforcement halted: Column "is_single_business" exists on public.businesses with incompatible definition (must be BOOLEAN NOT NULL DEFAULT true).';
        END IF;

        EXECUTE 'SELECT COUNT(*) FROM public.businesses WHERE is_single_business IS NOT TRUE' INTO v_invalid_is_single;
        IF v_invalid_is_single > 0 THEN
            RAISE EXCEPTION 'Single-business enforcement halted: Found % rows where is_single_business is not TRUE.', v_invalid_is_single;
        END IF;
    END IF;

    -- 5. Validate constraint definition using catalog attributes if chk_single_business_true exists
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.businesses'::regclass AND conname = 'chk_single_business_true'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = 'public.businesses'::regclass AND conname = 'chk_single_business_true'
              AND contype = 'c'
              AND convalidated = true
              AND (
                  pg_get_constraintdef(oid) = 'CHECK ((is_single_business = true))'
               OR pg_get_constraintdef(oid) = 'CHECK (is_single_business = true)'
               OR pg_get_constraintdef(oid) = 'CHECK ((is_single_business IS TRUE))'
              )
        ) THEN
            RAISE EXCEPTION 'Single-business enforcement halted: Constraint "chk_single_business_true" exists on public.businesses with incompatible or unvalidated definition.';
        END IF;
    END IF;

    -- 6. Validate index properties using PostgreSQL catalog metadata if uq_businesses_single_row exists
    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'businesses' AND indexname = 'uq_businesses_single_row'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_index i
            JOIN pg_class c ON c.oid = i.indexrelid
            JOIN pg_namespace cn ON cn.oid = c.relnamespace
            JOIN pg_class t ON t.oid = i.indrelid
            JOIN pg_namespace tn ON tn.oid = t.relnamespace
            JOIN pg_am am ON am.oid = c.relam
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = i.indkey[0]
            WHERE tn.nspname = 'public'
              AND t.relname = 'businesses'
              AND cn.nspname = 'public'
              AND c.relname = 'uq_businesses_single_row'
              AND c.relkind = 'i'
              AND a.attname = 'is_single_business'
              AND am.amname = 'btree'
              AND i.indnatts = 1
              AND i.indnkeyatts = 1
              AND i.indisunique = true
              AND i.indisvalid = true
              AND i.indisready = true
              AND i.indpred IS NULL
              AND i.indexprs IS NULL
        ) THEN
            RAISE EXCEPTION 'Single-business enforcement halted: Index "uq_businesses_single_row" exists but is not a valid, ready, unique, unpredicated 1-key-column B-tree index in public schema bound to public.businesses(is_single_business).';
        END IF;
    END IF;

    -- 7. Validate that trg_log_business_activity trigger exists on public.businesses, is a non-internal ROW AFTER INSERT OR UPDATE trigger (tgtype = 21), executing public.log_business_activity()
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_namespace pn ON pn.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'businesses'
          AND t.tgname = 'trg_log_business_activity'
          AND pn.nspname = 'public'
          AND p.proname = 'log_business_activity'
          AND t.tgisinternal = false
          AND t.tgtype = 21  -- ROW (1) AFTER (0) INSERT (4) OR UPDATE (16)
    ) THEN
        RAISE EXCEPTION 'Single-business enforcement halted: Trigger "trg_log_business_activity" on public.businesses was not found, is an internal trigger, or does not match exact tgtype=21 (ROW AFTER INSERT OR UPDATE) configuration executing public.log_business_activity().';
    END IF;

    -- 8. Validate trg_prevent_sole_business_deletion trigger definition if already present
    IF EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'businesses' AND t.tgname = 'trg_prevent_sole_business_deletion'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_proc p ON p.oid = t.tgfoid
            JOIN pg_namespace pn ON pn.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND c.relname = 'businesses'
              AND t.tgname = 'trg_prevent_sole_business_deletion'
              AND pn.nspname = 'public'
              AND p.proname = 'prevent_sole_business_deletion'
              AND p.prosrc LIKE '%Single-business deletion prohibited%'
              AND t.tgisinternal = false
        ) THEN
            RAISE EXCEPTION 'Single-business enforcement halted: Existing trigger "trg_prevent_sole_business_deletion" on public.businesses has an incompatible definition.';
        END IF;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. CONCURRENCY-SAFE SINGLE BUSINESS TABLE CONSTRAINT
-- ----------------------------------------------------------------------------
-- Adding boolean column constrained to 'true' with a UNIQUE index guarantees at most
-- 1 row can exist in public.businesses, blocking concurrent insert race conditions.
ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS is_single_business BOOLEAN NOT NULL DEFAULT true;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.businesses'::regclass AND conname = 'chk_single_business_true'
    ) THEN
        ALTER TABLE public.businesses
          ADD CONSTRAINT chk_single_business_true CHECK (is_single_business = true);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_businesses_single_row
  ON public.businesses (is_single_business);

-- ----------------------------------------------------------------------------
-- 3. REVOKE DIRECT TABLE INSERT AND TRUNCATE PRIVILEGES & CLEAN INSERT POLICIES
-- ----------------------------------------------------------------------------
-- Revokes direct table INSERT and TRUNCATE permissions and cleans known business creation policies
REVOKE INSERT, TRUNCATE ON TABLE public.businesses FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Admins can insert business" ON public.businesses;
DROP POLICY IF EXISTS "Admins can create a business" ON public.businesses;
DROP POLICY IF EXISTS "Admins insert business" ON public.businesses;
DROP POLICY IF EXISTS "Admins can create businesses" ON public.businesses;

CREATE POLICY "Admins can insert business" ON public.businesses
  FOR INSERT TO authenticated WITH CHECK (false);

-- ----------------------------------------------------------------------------
-- 4. FIX ACTIVITY LOG TRIGGER FUNCTION (Column name: NEW.name)
-- ----------------------------------------------------------------------------
-- Updates log_business_activity() function definition to reference actual NEW.name column.
-- NOTE: Trigger trg_log_business_activity is left in its current disabled state (tgenabled = 'O')
-- until activity_logs catalog evidence and permissions are verified by DBA.
CREATE OR REPLACE FUNCTION public.log_business_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.activity_logs (business_id, user_id, type, title, details)
        VALUES (NEW.id, auth.uid(), 'business_created', 'New Business Registered', 'Business "' || NEW.name || '" was created.');
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            INSERT INTO public.activity_logs (business_id, user_id, type, title, details)
            VALUES (NEW.id, auth.uid(), 'business_updated', 'Business Status Changed', 'Business "' || NEW.name || '" status changed to ' || UPPER(NEW.status) || '.');
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. DISABLE CREATE BUSINESS RPC & HARDEN ACL
-- ----------------------------------------------------------------------------
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
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can execute business creation functions.';
    END IF;

    RAISE EXCEPTION 'Single-business restriction enforced: FlexPOS operates exclusively as a single-business system. Additional business creation is prohibited.';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_business_by_admin(TEXT, UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_business_by_admin(TEXT, UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. UNIFIED AUTHORIZED BUSINESS RESOLUTION RPC (get_user_business_id)
-- ----------------------------------------------------------------------------
-- Combines store ownership, active employment, and active membership (active IS TRUE)
-- into ONE distinct set.
-- Returns UUID ONLY when exactly one distinct business ID exists.
-- Returns NULL when zero or conflicting business associations exist (fail-closed safely).
CREATE OR REPLACE FUNCTION public.get_user_business_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_business_ids UUID[];
    v_count INT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Collect all distinct business IDs for current user across ownership, active employment, and active memberships
    WITH all_associations AS (
        SELECT id AS business_id
        FROM public.businesses
        WHERE owner_id = v_user_id

        UNION

        SELECT e.business_id
        FROM public.employees e
        JOIN public.businesses b ON b.id = e.business_id
        WHERE e.profile_id = v_user_id AND e.status = 'active'

        UNION

        SELECT bm.business_id
        FROM public.business_memberships bm
        JOIN public.businesses b ON b.id = bm.business_id
        WHERE bm.user_id = v_user_id AND bm.active IS TRUE
    )
    SELECT ARRAY_AGG(DISTINCT business_id)
    INTO v_business_ids
    FROM all_associations
    WHERE business_id IS NOT NULL;

    v_count := COALESCE(array_length(v_business_ids, 1), 0);

    -- Return UUID ONLY when exactly 1 distinct business ID exists
    IF v_count = 1 THEN
        RETURN v_business_ids[1];
    ELSE
        -- 0 or >1 distinct business IDs -> return NULL (failing closed safely under RLS)
        RETURN NULL;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_business_id() TO public, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7. HARDEN get_user_businesses FUNCTION
-- ----------------------------------------------------------------------------
-- Uses get_user_business_id resolution without bypassing conflict detection.
CREATE OR REPLACE FUNCTION public.get_user_businesses()
RETURNS SETOF UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bid UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;

    v_bid := public.get_user_business_id();
    IF v_bid IS NOT NULL THEN
        RETURN NEXT v_bid;
    END IF;
    RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_businesses() TO public, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 8. HARDEN is_admin FUNCTION ACL & SEARCH_PATH
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO public, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 9. PREVENT SOLE BUSINESS STORE RECORD DELETION & TRUNCATION
-- ----------------------------------------------------------------------------
-- Enforces explicit deletion & truncation protection preventing removal of the primary business row.
CREATE OR REPLACE FUNCTION public.prevent_sole_business_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RAISE EXCEPTION 'Single-business deletion/truncation prohibited: Deleting or truncating the primary FlexPOS business store record is forbidden as it would purge all associated sales, inventory, and activity history.';
    RETURN NULL;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'businesses' AND t.tgname = 'trg_prevent_sole_business_deletion'
    ) THEN
        CREATE TRIGGER trg_prevent_sole_business_deletion
            BEFORE DELETE OR TRUNCATE ON public.businesses
            FOR EACH STATEMENT
            EXECUTE FUNCTION public.prevent_sole_business_deletion();
    END IF;
END $$;

COMMIT;
