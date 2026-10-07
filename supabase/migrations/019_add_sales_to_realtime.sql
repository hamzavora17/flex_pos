-- Migration: 019_add_sales_to_realtime.sql
-- Description: Adds public.sales to the existing supabase_realtime publication to enable live updates on the Manager Dashboard.

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'sales'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.sales;
        END IF;
    END IF;
END $$;

COMMIT;
