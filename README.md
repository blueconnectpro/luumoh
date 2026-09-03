# Luumoh

Luumoh is structured as a Flutter monorepo backed by Supabase.

## Apps

- `apps/customer_app`: browse stores/products, place orders, pay through Monnify, track order status and rider ETA.
- `apps/rider_app`: accept available paid orders, update delivery status, publish ETA changes.
- `apps/store_app`: manage products, availability, inventory, and daily order operations.
- `apps/admin_dashboard`: platform overview for stores, orders, riders, payments, and operations.

## Shared Package

- `packages/luumoh_core`: shared models, Supabase repositories, payment client, and app configuration.

## Backend

- `supabase/migrations`: schema, RLS policies, realtime publication, inventory reservation logic, and order/payment functions.
- `supabase/functions/monnify-initiate`: creates a Monnify hosted checkout transaction from a Supabase order.
- `supabase/functions/monnify-webhook`: validates Monnify webhooks and finalizes paid orders.
- `supabase/functions/admin-upsert-user`: lets signed-in admins create/update operational auth users without exposing service-role credentials to Flutter.

## Inventory Approach

Use Supabase as the operational inventory system first:

- `inventory_items.quantity_on_hand` is the store's physical stock.
- `inventory_reservations` holds customer checkout reservations until payment succeeds or the checkout expires.
- `customer_catalog` exposes available quantity as `quantity_on_hand - active reservations`.
- Store availability toggles and stock changes update the same tables the customer app reads, so unavailable/out-of-stock state is immediately shared.
- Paid Monnify webhooks convert reservations into `inventory_movements` and reduce on-hand stock.

This gives you a clean inventory ledger without adopting a heavy ERP too early. If stores later need accounting, purchase orders, supplier workflows, barcode scanning, or multi-branch warehousing, integrate an ERP/POS such as ERPNext, Odoo, or Loyverse and sync it into the same `inventory_items`/`inventory_movements` tables.

## Cloud Supabase Setup

1. Install Flutter and Supabase CLI.

If the Supabase CLI is not installed globally, you can use:

```bash
npx supabase --version
```

2. Fill `.env` with the cloud Supabase project values, Mapbox public token, and Monnify keys.

Use only `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `MAPBOX_ACCESS_TOKEN` in Flutter. Keep `SUPABASE_SERVICE_ROLE_KEY`, `MONNIFY_SECRET_KEY`, and `MONNIFY_API_KEY` server-side only.

For local Flutter runs without typing `--dart-define` every time, sync the public Flutter config from `.env`:

```powershell
.\scripts\sync-flutter-env.ps1
```

This writes only `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `MAPBOX_ACCESS_TOKEN`, and optional `STORE_ID` into an ignored local Dart file. Run it again whenever those `.env` values change.

## Mapbox Location Setup

Add your public Mapbox access token to `.env`:

```env
MAPBOX_ACCESS_TOKEN=pk.your-mapbox-public-token
```

Then sync the Flutter config:

```powershell
.\scripts\sync-flutter-env.ps1
```

Customer, store, rider, and admin-created store addresses now use Mapbox for address search, reverse geocoding from current location, saved latitude/longitude, route maps, and Mapbox directions links. Customer and store users can either use current location or type/search an address before saving.

3. Login and link the cloud Supabase project:

```bash
npx supabase login
npx supabase link --project-ref <SUPABASE_PROJECT_REF>
```

If you see `open C:\Users\...\ .supabase\profile: The system cannot find the file specified`, the CLI has not been logged in on this machine. Run `npx supabase login`, or create a personal access token from Supabase Dashboard -> Account -> Access Tokens and set `SUPABASE_ACCESS_TOKEN` in `.env` before running Supabase commands.

For a one-off PowerShell session without editing `.env`:

```powershell
$env:SUPABASE_ACCESS_TOKEN="your-token"
.\scripts\push-supabase-db.ps1
```

4. Push migrations to cloud Supabase.

On Windows with newer Node versions, prefer the pinned helper script because unpinned `npx supabase` can resolve a CLI wrapper that cannot find a Windows binary package:

```powershell
.\scripts\push-supabase-db.ps1
```

If you add `SUPABASE_DB_PASSWORD` to `.env`, the script runs non-interactively. Otherwise the CLI will prompt for the database password from Supabase Dashboard -> Project Settings -> Database.

The direct CLI equivalent is:

```bash
npx supabase@2.26.9 db push --project-ref <SUPABASE_PROJECT_REF>
```

5. Set Edge Function secrets from the values in `.env`:

```bash
npx supabase secrets set MONNIFY_BASE_URL=... MONNIFY_API_KEY=... MONNIFY_SECRET_KEY=... MONNIFY_CONTRACT_CODE=... MONNIFY_REDIRECT_URL=...
```

6. Deploy functions:

```bash
npx supabase functions deploy monnify-initiate
npx supabase functions deploy monnify-confirm
npx supabase functions deploy monnify-webhook --no-verify-jwt
npx supabase functions deploy admin-upsert-user
```

On Windows, use the helper to set secrets from `.env` and deploy all functions:

```powershell
.\scripts\deploy-supabase-functions.ps1
```

Then run a quick cloud health check:

```powershell
.\scripts\check-cloud-health.ps1
```

To confirm customer-visible stores/products are available from the linked cloud project:

```powershell
.\scripts\check-customer-catalog.ps1
```

To test the customer order RPC against seeded catalog data without completing payment:

```powershell
.\scripts\test-order-placement.ps1
```

To test the full paid operations flow across customer, store, rider, and customer tracking:

```powershell
.\scripts\test-operations-flow.ps1
```

To test admin onboarding through the deployed Edge Function:

```powershell
.\scripts\test-admin-onboarding.ps1
```

To check local release readiness before a launch smoke run:

```powershell
.\scripts\check-release-readiness.ps1
```

To run the production blocker gates:

```powershell
.\scripts\check-android-release-readiness.ps1
.\scripts\check-supabase-realtime-readiness.ps1 -FailOnWarnings
.\scripts\check-monnify-readiness.ps1 -RequireProduction
.\scripts\check-security-rls.ps1 -FailOnWarnings
.\scripts\check-finance-reconciliation.ps1 -FailOnIssues
```

To run the combined pre-launch QA path:

```powershell
.\scripts\run-full-prelaunch-qa.ps1
```

For strict launch QA after external production setup is complete:

```powershell
.\scripts\run-full-prelaunch-qa.ps1 -RequireAndroidRelease -RequireRealtime -RequireProductionMonnify -RunAnalyze
```

To run the same strict path and export the final operations report:

```powershell
.\scripts\run-production-final-qa.ps1
```

## Payment Routes

Monnify hosted checkout requires an HTTP(S) redirect URL. Use the hosted Supabase return page for Monnify, then let that page open the customer app deep link:

```env
MONNIFY_REDIRECT_URL=https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-return
MONNIFY_APP_RETURN_URL=luumoh://payment-return
```

Configure the Monnify webhook URL as:

```text
https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-webhook
```

To verify checkout initialization without completing payment:

```powershell
.\scripts\test-monnify-checkout-init.ps1
```

## Android Production Setup

The mobile apps are wired with production Android package IDs:

- Customer: `com.luumoh.customer`
- Store: `com.luumoh.store`
- Rider: `com.luumoh.rider`

For Play Store release signing, copy each `key.properties.example` to `key.properties`, replace the placeholder values, and place the upload keystore at the configured `storeFile` path. Validate the full Android release setup with:

```powershell
.\scripts\check-android-release-readiness.ps1
```

To test customer support issue creation and admin resolution:

```powershell
.\scripts\test-support-flow.ps1
```

To test Supabase realtime notifications:

```powershell
.\scripts\test-notifications-flow.ps1
```

To test Supabase realtime order messages:

```powershell
.\scripts\test-order-messages-flow.ps1
```

For a fuller pre-launch smoke run:

```powershell
.\scripts\run-launch-smoke.ps1
```

The launch smoke run syncs env config, pushes migrations, deploys functions unless `-SkipDeploy` is supplied, checks cloud endpoints, verifies admin onboarding, and runs order, operations, notification, and message smoke flows. Add `-RunAnalyze` only after the local Dart CLI is responding normally.

## Notifications

In-app notifications are written to `user_notifications` and appear in the customer, store, rider, and admin notification drawers through Supabase Realtime.

The backend currently generates notifications for payment success/failure/expiry/refund, order status changes, rider assignment, ETA updates, store staff assignment/permission changes, support issues, and key admin/store/rider events.

Order messages are written to `order_messages`, exposed through `order_message_summaries`, and streamed with Supabase Realtime. Sending a message also creates `order_message` notifications for the other order participants.

For a repeatable launch runbook, see [docs/LAUNCH_RUNBOOK.md](docs/LAUNCH_RUNBOOK.md).

For external production setup across Supabase, Monnify, Realtime, and Android signing, see [docs/PRODUCTION_EXTERNAL_SETUP.md](docs/PRODUCTION_EXTERNAL_SETUP.md).

To export an operations snapshot:

```powershell
.\scripts\export-admin-ops-report.ps1
```

To build one or all Flutter web apps from the repo root:

```powershell
.\scripts\build-web-apps.ps1 -App customer
.\scripts\build-web-apps.ps1 -App all
```

To serve a built web app locally for browser QA:

```powershell
.\scripts\serve-built-app.ps1 -App customer -Port 7358 -Build
```

7. Create the first admin user:

- Sign up in the app or Supabase Auth.
- Call `claim_first_admin()` once as that signed-in user from SQL editor or RPC.
- After the first admin exists, use `admin_set_profile_role()` for future role changes.

8. Generate platform folders inside each app when the Flutter CLI is responsive:

```bash
cd apps/customer_app
flutter create --platforms=android,ios,web .
```

Repeat for `rider_app`, `store_app`, and `admin_dashboard`.

9. Run an app:

```bash
cd apps/customer_app
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

If you already ran `.\scripts\sync-flutter-env.ps1`, use:

```bash
cd apps/customer_app
flutter run -d chrome
```

Or from the repo root:

```powershell
.\scripts\run-flutter-app.ps1 -App customer
```

Payment checkout now keeps listening to the order after the Monnify link opens. When the webhook confirms payment, the customer dialog changes from pending to confirmed and the order list updates through Supabase realtime.

For mobile payment return, set:

```env
MONNIFY_REDIRECT_URL=https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-return
MONNIFY_APP_RETURN_URL=luumoh://payment-return
```

The `monnify-initiate` function sends Monnify to the hosted return URL and appends `orderId` and `paymentReference`. The return page opens the customer app deep link, shows the payment result, and switches to Tracking.

## Catalog Setup

After the admin user has been created and the project is linked, push the latest migrations so the admin dashboard can create products with inventory:

```bash
npx supabase db push
```

Then run the admin dashboard and sign in with the admin account:

```bash
cd apps/admin_dashboard
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

After syncing local Flutter config, `flutter run -d chrome` is enough.

Use the dashboard to:

- Create a store.
- Create products for that store with price, SKU, initial stock, and reorder level.
- Create rider, store staff, admin, or test customer accounts from the admin onboarding panel.
- Assign user roles such as `rider`, `store_admin`, or `admin`.
- Add store staff to a store with inventory/order permissions.
- Confirm the product appears in the customer catalog.

The product creator writes to `products`, `inventory_items`, and `inventory_movements` together, so the customer app reads the same stock and availability state that the store/admin tools manage.

## Store Operations

After a store and products exist, use the admin dashboard onboarding panel to create the store staff account and assign it to the store. Existing profiles can still be adjusted from the access-management panel.

Then run the store app:

```bash
cd apps/store_app
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... --dart-define=STORE_ID=...
```

For the store app without dart defines, set `STORE_ID` in `.env`, run `.\scripts\sync-flutter-env.ps1`, then run `flutter run -d chrome`.

From the repo root:

```powershell
.\scripts\run-flutter-app.ps1 -App store
```

Store staff can sign in, mark products available/unavailable, adjust stock with inventory notes, and move paid orders to `preparing` or `ready_for_pickup`. Those product availability and stock changes feed the same `customer_catalog` view used by the customer app.

## Rider Operations

Use the admin dashboard access-management panel to set a rider account role to `rider`. Then run the rider app:

```bash
cd apps/rider_app
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

After syncing local Flutter config, `flutter run -d chrome` is enough.

From the repo root:

```powershell
.\scripts\run-flutter-app.ps1 -App rider
```

Riders can accept `ready_for_pickup` paid orders, set/update ETAs, and mark deliveries completed. Customer tracking reads the same order ETA fields updated by the rider app.

## Android Network Troubleshooting

If Android login fails with `SocketException: Failed host lookup`, check two things:

- The app manifest must include `android.permission.INTERNET`.
- The emulator must be able to resolve the Supabase host.

Restart a stuck emulator with explicit DNS:

```bash
adb -s emulator-5554 emu kill
emulator -avd Pixel_9 -dns-server 8.8.8.8,1.1.1.1
```

Then rerun the app so Android installs the updated manifest.

## Optional Local Seed

Local Supabase requires Docker Desktop. For local development with seed users and sample inventory:

```bash
npx supabase start
npx supabase db reset
```

Seed logins all use `Password123!`:

- `customer@luumoh.test`
- `store@luumoh.test`
- `rider@luumoh.test`
- `admin@luumoh.test`
