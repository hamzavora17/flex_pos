# FlexPOS Supabase Database & Security Guide

This directory contains the database migration scripts and security policies for the **FlexPOS** Point of Sale system.

---

## ⚠️ Migration Notice

The Supabase database contains an existing database schema with 9 pre-created tables (`businesses`, `profiles`, `categories`, `products`, `inventory`, `customers`, `sales`, `sale_items`, `payments`).

To safely extend the existing database without dropping tables, deleting data, or breaking compatibility, use the incremental migration file:

📁 **[`supabase/migrations/002_flexpos_roles_and_rls.sql`](file:///D:/a%20Sem-5/1%20Flutter/flex_pos/supabase/migrations/002_flexpos_roles_and_rls.sql)**

*(Note: Do NOT run `001_initial_flexpos_schema.sql` on a database with existing tables.)*

---

## 1. How to Apply Migration 002 in Supabase

### Option A: Via Supabase Web Dashboard (Recommended)
1. Open your Supabase Dashboard: [https://supabase.com/dashboard](https://supabase.com/dashboard).
2. Navigate to **SQL Editor** in the left sidebar.
3. Click **New Query**.
4. Copy and paste the entire contents of [`supabase/migrations/002_flexpos_roles_and_rls.sql`](file:///D:/a%20Sem-5/1%20Flutter/flex_pos/supabase/migrations/002_flexpos_roles_and_rls.sql).
5. Click **Run**.
6. Verify that the new `employees` and `inventory_logs` tables appear, and that columns `role` (in `profiles`) and `owner_id` (in `businesses`) are populated.

### Option B: Via Supabase CLI
```bash
supabase link --project-ref guetrlodubohesyoyyit
supabase db push
```

---

## 2. Preserved Existing Database Schema

Migration 002 preserves all existing tables and columns, including:
- **`businesses`**: Preserves `name`, `currency`. Adds `owner_id`, `email`, `phone`, `address`.
- **`profiles`**: Preserves `full_name`, `phone`. Adds `email`, `role`.
- **`products`**: Preserves `name`, `price`, `cost`, `active`, `sku`, `barcode`. Adds `unit`, `min_stock_alert`.
- **`inventory`**: Preserves `branch_id`, `low_stock_threshold`, `quantity`. Adds `business_id`.
- **`sales`**: Preserves `branch_id`, `shift_id`, `employee_id`, `customer_id`, `invoice_number`, `subtotal`, `discount`, `tax`, `total`, `status`.
- **`sale_items`**: Preserves `product_name`, `product_sku`, `unit_price`, `line_total`, `quantity`.
- **`payments`**: Preserves `method`, `amount`, `reference`.

---

## 3. Incremental Additions (Migration 002)

| Table Name | Operation | Purpose |
| :--- | :--- | :--- |
| **`profiles`** | `ALTER ADD COLUMN` | Adds `email` and `role ('admin' / 'employee')`. |
| **`businesses`** | `ALTER ADD COLUMN` | Adds `owner_id` (store owner reference), `email`, `phone`, `address`. |
| **`products`** | `ALTER ADD COLUMN` | Adds `unit` and `min_stock_alert`. |
| **`inventory`** | `ALTER ADD COLUMN` | Adds `business_id`. |
| **`customers`** | `ALTER ADD COLUMN` | Adds `address`. |
| **`employees`** | `CREATE TABLE` | Links employee user profiles to store businesses with status & position. |
| **`inventory_logs`** | `CREATE TABLE` | Stock movement audit trail (stock_in, stock_out, adjustment, sale, return). |

---

## 4. Role Model & Row Level Security (RLS) Strategy

Row Level Security is enabled across all application tables:

### Roles
- **`admin`**: Full CRUD permissions across business entities, product management, employee management, and reports.
- **`employee`**: Read access to catalog/customers, write access to create sales, sale items, payments, and stock logs. Cannot manage store settings or employee profiles.

### RLS Helper Functions
- `is_admin()`: Returns `true` if `auth.uid()` possesses role `'admin'` in `profiles`.
- `get_user_business_id()`: Returns the active `business_id` associated with `auth.uid()` via store ownership or active employee status.

---

## 5. Next Phase Steps
1. Execute Migration `002_flexpos_roles_and_rls.sql` in the Supabase SQL Editor.
2. Integrate Supabase Auth in Flutter (`Supabase.instance.client.auth`).
3. Wire up user sign-in/sign-out and fetch user profile/role from `profiles`.
4. Route user dynamically to `AdminDashboard` or `HomePage` based on database role (`admin` vs `employee`).
