# FlexPOS Supabase Database Architecture & Security Plan

This document outlines the corrected, non-destructive database architecture for **FlexPOS**. It details the existing Supabase schema and the incremental migration [`supabase/migrations/002_flexpos_roles_and_rls.sql`](file:///D:/a%20Sem-5/1%20Flutter/flex_pos/supabase/migrations/002_flexpos_roles_and_rls.sql).

---

## 1. Existing Database Schema (Preserved as Source of Truth)

The existing Supabase project contains 9 pre-created public tables:

1. **`businesses`**: `id` (UUID), `name` (varchar), `currency` (varchar), `created_at`, `updated_at`.
2. **`profiles`**: `id` (UUID), `full_name` (varchar), `phone` (varchar), `created_at`, `updated_at`.
3. **`categories`**: `id` (UUID), `business_id` (UUID), `name` (varchar), `description` (text), `created_at`, `updated_at`.
4. **`products`**: `id` (UUID), `business_id` (UUID), `category_id` (UUID), `name` (varchar), `sku` (varchar), `barcode` (varchar), `price` (numeric), `cost` (numeric), `active` (boolean), `created_at`, `updated_at`.
5. **`inventory`**: `id` (UUID), `product_id` (UUID), `branch_id` (UUID), `quantity` (integer), `low_stock_threshold` (integer), `created_at`, `updated_at`.
6. **`customers`**: `id` (UUID), `business_id` (UUID), `name` (varchar), `email` (varchar), `phone` (varchar), `notes` (text), `created_at`, `updated_at`.
7. **`sales`**: `id` (UUID), `invoice_number` (varchar), `business_id` (UUID), `branch_id` (UUID), `shift_id` (UUID), `employee_id` (UUID), `customer_id` (UUID), `subtotal` (numeric), `discount` (numeric), `tax` (numeric), `total` (numeric), `status` (varchar), `created_at`, `updated_at`.
8. **`sale_items`**: `id` (UUID), `sale_id` (UUID), `product_id` (UUID), `product_name` (varchar), `product_sku` (varchar), `quantity` (integer), `unit_price` (numeric), `line_total` (numeric), `created_at`.
9. **`payments`**: `id` (UUID), `sale_id` (UUID), `amount` (numeric), `method` (varchar), `reference` (varchar), `created_at`.

---

## 2. Incremental Extensions in Migration 002

Migration 002 applies non-destructive `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` and `CREATE TABLE IF NOT EXISTS` commands:

- **`profiles`**: Adds `email` (TEXT) and `role` (TEXT, check `'admin'` or `'employee'`, default `'employee'`).
- **`businesses`**: Adds `owner_id` (UUID -> profiles.id), `email`, `phone`, `address`.
- **`products`**: Adds `unit` (TEXT, default `'pcs'`) and `min_stock_alert` (INTEGER, default `5`).
- **`inventory`**: Adds `business_id` (UUID -> businesses.id).
- **`customers`**: Adds `address` (TEXT).
- **New Table `employees`**: `id`, `business_id` (FK), `profile_id` (FK, UNIQUE), `position`, `status`, `created_at`, `updated_at`.
- **New Table `inventory_logs`**: Audit log for stock movements (`stock_in`, `stock_out`, `adjustment`, `sale`, `return`).

---

## 3. Role Model & Row Level Security (RLS) Strategy

Row Level Security is enabled on **ALL 11 application tables**.

### Roles
- **`admin`**: Full CRUD access across business entities, products, employee assignments, and financial records.
- **`employee`**: Read access to catalog/customers, write access to create sales, sale items, payments, and stock movement logs. Cannot perform admin operations.

### RLS Helper Functions
- `public.is_admin()`: Returns `true` if current user (`auth.uid()`) has role `'admin'` in `profiles`.
- `public.get_user_business_id()`: Returns `business_id` associated with current user via store ownership or active employee status.
