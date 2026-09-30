# FlexPOS Project Audit & Preparation Report

## 1. Current Project Structure
- **Root Directory**: `flex_pos/`
  - `lib/main.dart` (50.4 KB) — Single file containing all screens, models, UI components, and state management.
  - `assets/` — Stores static image resources (`FlexPOS_logo_upscaled.png`, `favicon.png`).
  - `test/widget_test.dart` — Basic widget smoke test for `FlexPOSApp`.
  - `pubspec.yaml` — Package metadata and dependencies.
  - `analysis_options.yaml` — Static analysis configuration using `package:flutter_lints/flutter.yaml`.
  - `android/`, `ios/`, `web/` — Platform target configurations.

## 2. Current Application Flow & Navigation
- **Splash Screen (`SplashScreen`)**:
  - Displays the FlexPOS logo and an animated progress indicator (0% to 100% over ~4 seconds).
  - Automatically navigates to `LoginPage` upon completion using `Navigator.of(context).pushReplacement(...)`.
- **Login Screen (`LoginPage`)**:
  - Supports responsive layout (desktop brand panel with real-time sales metric cards vs. mobile single column).
  - Contains Email & Password input fields with input validation.
  - Features a "Forgot Password?" dialog (`_ForgotPasswordDialog`) that instructs users to contact an administrator.
  - **Routing Logic**:
    - Email `admin@flexpos.com` + Password `admin123` -> Navigates to `AdminDashboard`.
    - Any valid email matching `*@flexpos.com` -> Navigates to `HomePage`.
- **Regular POS Home (`HomePage`)**:
  - Displays a header app bar with store logo, title, and logout button.
  - Contains a grid of core POS modules: "New Sale", "Inventory", "Reports", "Settings".
  - Logout returns to `LoginPage`.
- **Admin Dashboard (`AdminDashboard`)**:
  - Displays system-wide overview cards (Total Businesses, Active Users, Monthly Revenue).
  - On wider screens (>900px), presents a left navigation sidebar (Overview, Business Units, User Management, System Settings, Support).
  - Includes a "Recent Activity" table with simulated audit logs.
  - Logout returns to `LoginPage`.

## 3. Existing Features
- Responsive web/desktop & mobile UI layouts.
- Form validation with custom error indicators and visibility toggle for passwords.
- Hero logo animations and custom branded theme (`Color(0xFF003366)` primary, `Color(0xFF8DB600)` secondary).
- Interactive password reset request modal.
- System metrics dashboard layout for admin role.

## 4. Existing Authentication Behavior
- Currently strictly client-side and simulated.
- **Validation Rules**:
  - Email: Restricted to regex `^[\w-.]+@flexpos\.com$` (case-insensitive).
  - Password: Requires at least 8 characters containing both letters and numbers (`^(?=.*[a-zA-Z])(?=.*\d).{8,}$`).
- **Role Determination**:
  - Hardcoded string equality check on `email == 'admin@flexpos.com'`.
  - Hardcoded password check for admin: `password == 'admin123'`.
  - Other valid `@flexpos.com` emails bypass password verification after a mock loading delay (`Future.delayed`).

## 5. Existing Hardcoded / Local / Mock Data
- Admin credentials (`admin@flexpos.com` / `admin123`).
- Simulated loading delay (`Future.delayed(Duration(milliseconds: 800))`).
- Stat metrics in Admin Dashboard (`Total Businesses: 1,284`, `Active Users: 8,432`, `Monthly Revenue: $42.5k`).
- Floating metrics on Login brand panel ("Today's Sales: ₹4,289.50", "Active Orders: 24").
- Grid action cards on `HomePage` (have empty `onTap` handlers).
- Recent activity list items in `AdminDashboard`.

## 6. Existing Dependencies
- **SDK**: Flutter `>=3.47.5`, Dart `^3.13.4` (environment compatibility: `sdk: ^3.12.2`).
- **Dependencies**:
  - `cupertino_icons: ^1.0.8`
  - `video_player: ^2.8.2`
- **Dev Dependencies**:
  - `flutter_test`
  - `flutter_lints: ^6.0.0`

## 7. Problems & Errors Found (and Resolved)
- **Unused Import & Broken Test**:
  - `test/widget_test.dart` contained legacy counter template code referencing a non-existent `MyApp` widget, causing `flutter analyze` warning (`unused_import`) and `flutter test` failure.
  - **Fix Applied**: Updated `test/widget_test.dart` to properly test `FlexPOSApp` rendering the splash screen. `flutter analyze` and `flutter test` now pass with 0 errors/warnings.
- **Supabase Compatibility Blockers to Address Later**:
  1. Strict email regex forcing `@flexpos.com` domain.
  2. Strict password regex preventing login with external identity providers or existing passwords.
  3. Direct `Navigator.pushReplacement` navigation instead of reactive `StreamBuilder` / `Listenable` on Supabase Auth state (`onAuthStateChange`).
  4. Lack of user role column or table mapping (`profiles` / `roles`).

## 8. Recommended Architecture for Adding Supabase Later
When ready to integrate Supabase, standard clean modular architecture should be introduced without breaking the existing UI:

```
lib/
├── main.dart                 # App initialization & Supabase.initialize()
├── core/
│   ├── config/               # Supabase credentials & constants
│   └── theme/                # FlexPOS colors and ThemeData
├── features/
│   ├── auth/
│   │   ├── data/             # AuthRepository (Supabase auth calls)
│   │   ├── presentation/     # LoginPage, ForgotPasswordDialog
│   │   └── models/           # AppUser, UserRole
│   ├── pos/
│   │   └── presentation/     # HomePage, POS grid
│   └── admin/
│       └── presentation/     # AdminDashboard
└── services/                 # Supabase client instance & database helpers
```

### Database Schema Recommendations for Supabase
1. **`profiles` table**: `id (uuid, FK to auth.users)`, `email (text)`, `role (text: 'admin' | 'operator' | 'manager')`, `full_name (text)`, `created_at (timestamp)`.
2. **`business_units` table**: `id`, `name`, `status`, `created_at`.
3. **`sales` / `orders` table**: `id`, `terminal_id`, `total_amount`, `status`, `created_at`.

## 9. Files That Should NOT Be Unnecessarily Rewritten
- `lib/main.dart`: Keep current UI code intact; slice into feature modules gradually when integrating backend logic.
- Assets in `assets/`: Maintain `FlexPOS_logo_upscaled.png` and `favicon.png`.
- Platform build configurations (`android/`, `ios/`, `web/`): Do not alter unless required for specific Supabase plugins (e.g. deep linking / OAuth callbacks).
