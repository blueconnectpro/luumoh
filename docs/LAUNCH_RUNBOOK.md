# Luumoh Launch Runbook

This runbook covers the repeatable pre-launch path for Android release setup, Supabase Realtime notifications/messages, production Monnify testing, security/RLS audit, finance reconciliation, and full end-to-end QA.

## Preflight

1. Confirm `.env` has cloud Supabase and Monnify values.
2. Sync Flutter config:

```powershell
.\scripts\sync-flutter-env.ps1
```

3. Run local release readiness checks:

```powershell
.\scripts\check-release-readiness.ps1
.\scripts\check-android-release-readiness.ps1 -AllowMissingExternal
.\scripts\check-ios-release-readiness.ps1 -AllowMissingExternal
```

4. Push migrations, then check realtime publication/RLS:

```powershell
.\scripts\push-supabase-db.ps1
.\scripts\check-supabase-realtime-readiness.ps1
```

## Cloud Smoke

Run the main launch smoke:

```powershell
.\scripts\run-launch-smoke.ps1
```

This checks Supabase env generation, release readiness, migrations, Edge Function deployment, cloud health, admin onboarding, customer order placement, paid operations, customer support, realtime notifications, and realtime order messages.

## Operational Export

Generate a quick admin operations snapshot:

```powershell
.\scripts\export-admin-ops-report.ps1
```

The report exports orders, payments, settlements, open issues, catalog state, promo codes, reviews, rider ratings, rider locations, store staff activity, realtime notifications, order messages, payment webhook events, realtime readiness, security/RLS audit, and finance reconciliation into `reports/`.

For smaller launch checks, limit rows and the recent-order window:

```powershell
.\scripts\export-admin-ops-report.ps1 -Limit 250 -RecentDays 7
```

Each run also writes `manifest.json` and `health_summary.json` so Luumoh staff can quickly see export row counts and any finance, security, or realtime risks.

## Big Blocker Gates

Run these before production launch:

```powershell
.\scripts\check-android-release-readiness.ps1
.\scripts\check-ios-release-readiness.ps1
.\scripts\check-supabase-realtime-readiness.ps1 -FailOnWarnings
.\scripts\check-monnify-readiness.ps1 -RequireProduction
.\scripts\check-security-rls.ps1 -FailOnWarnings
.\scripts\check-finance-reconciliation.ps1 -FailOnIssues
```

`check-android-release-readiness.ps1` intentionally fails until Android release signing files are present.
`check-ios-release-readiness.ps1` intentionally fails until Apple `DEVELOPMENT_TEAM` values are configured in Xcode.

## Payment Routes

Monnify should use the hosted return page, not the mobile deep link directly:

```env
MONNIFY_REDIRECT_URL=https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-return
MONNIFY_APP_RETURN_URL=luumoh://payment-return
```

Monnify webhook URL:

```text
https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-webhook
```

Verify with:

```powershell
.\scripts\test-monnify-checkout-init.ps1
```

`check-monnify-readiness.ps1` authenticates with Monnify and verifies that the hosted return URL, mobile deep link, and webhook URL all match the configured Supabase project. Use `-RequireProduction` only after switching from sandbox credentials to the production Monnify account.

## Android Release Setup

Each mobile app has its own production Android package ID and release signing hook:

- Customer: `com.luumoh.customer`
- Store: `com.luumoh.store`
- Rider: `com.luumoh.rider`

Android build toolchain:

- Android Gradle Plugin: `9.3.1`
- Gradle wrapper: `9.6.1`
- Kotlin Gradle plugin: `2.4.10`

The apps currently keep `android.newDsl=false` and `android.builtInKotlin=false` in `android/gradle.properties` so Flutter plugins that still apply or expect the Kotlin Gradle plugin can build on AGP 9. Each app's root Android Gradle script explicitly applies the Kotlin Gradle plugin to Mapbox and supplies fallback namespaces for older Flutter Android libraries. Revisit these compatibility shims after the Flutter/Mapbox dependency stack supports AGP built-in Kotlin and AGP 9's new DSL cleanly.

Create each app's signing file from the committed example:

```powershell
Copy-Item apps\customer_app\android\key.properties.example apps\customer_app\android\key.properties
Copy-Item apps\store_app\android\key.properties.example apps\store_app\android\key.properties
Copy-Item apps\rider_app\android\key.properties.example apps\rider_app\android\key.properties
```

Then replace the placeholder values and place each upload keystore at the `storeFile` path. These files are ignored by git.
Release builds fail if `android/key.properties` is missing, so production artifacts cannot be debug-signed by accident.

## iOS Release Setup

The iOS bundle IDs are configured for production:

- Customer: `com.luumoh.customer`
- Store: `com.luumoh.store`
- Rider: `com.luumoh.rider`

Open each app's iOS project in Xcode and set the Apple Developer Team for the Runner target before archiving for App Store Connect. Verify with:

```powershell
.\scripts\check-ios-release-readiness.ps1
```

## Final QA

Development-mode QA:

```powershell
.\scripts\run-full-prelaunch-qa.ps1 -SkipDeploy
```

Strict production QA:

```powershell
.\scripts\run-production-final-qa.ps1
```

During development, omit strict switches:

```powershell
.\scripts\run-full-prelaunch-qa.ps1
```

Add `-RunAnalyze` only after the local Dart CLI is responding normally.

For a lighter cloud smoke pass that still runs the hardened release, Monnify, realtime, RLS, finance, and flow checks without redeploying functions:

```powershell
.\scripts\run-launch-smoke.ps1 -SkipDeploy
```
