# Production External Setup

Use this checklist for work that must happen outside the repository before strict launch QA can pass.

## Supabase

- Confirm the project is linked with `SUPABASE_PROJECT_REF`.
- Keep `SUPABASE_SERVICE_ROLE_KEY` server-side only.
- Set Edge Function secrets from `.env` with `.\scripts\deploy-supabase-functions.ps1`.
- Run `.\scripts\push-supabase-db.ps1`.
- Verify cloud functions with `.\scripts\check-cloud-health.ps1`.
- Verify realtime tables, RLS, and policies with `.\scripts\check-supabase-realtime-readiness.ps1`.

## Realtime Notifications And Messages

Luumoh uses Supabase Realtime for production notifications and order messages.

- Notifications are stored in `user_notifications`.
- Order message threads are stored in `order_messages`.
- Apps subscribe through `PlatformRepository.watchMyNotifications()` and `PlatformRepository.watchOrderMessages()`.
- Realtime publication/RLS readiness is checked by `.\scripts\check-supabase-realtime-readiness.ps1`.

No Firebase or FCM setup is required for the current launch path.

## Monnify

- Switch `MONNIFY_BASE_URL` from sandbox to the production Monnify base URL only after sandbox QA is clean.
- Confirm `MONNIFY_CONTRACT_CODE`, API key, and secret key match the production business account.
- Register the webhook URL for `monnify-webhook`.
- Use `MONNIFY_REDIRECT_URL=https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-return`.
- Keep `MONNIFY_APP_RETURN_URL=luumoh://payment-return` for mobile deep-link return.
- Register `https://nrhezcdnqzgteppkcife.supabase.co/functions/v1/monnify-webhook` as the Monnify webhook URL.
- Verify with `.\scripts\check-monnify-readiness.ps1 -RequireProduction`.

## Android Signing

For each mobile app:

```powershell
Copy-Item apps\customer_app\android\key.properties.example apps\customer_app\android\key.properties
Copy-Item apps\store_app\android\key.properties.example apps\store_app\android\key.properties
Copy-Item apps\rider_app\android\key.properties.example apps\rider_app\android\key.properties
```

Replace placeholder passwords and aliases, then place the upload keystore at the configured `storeFile` path. Release builds intentionally fail when these files are missing.

## iOS Signing

The production bundle IDs are:

- Customer: `com.luumoh.customer`
- Store: `com.luumoh.store`
- Rider: `com.luumoh.rider`

Create the matching identifiers in Apple Developer, enable required capabilities, then set each Runner target's Apple Developer Team in Xcode. Verify locally with:

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

The strict command should fail until Android signing, iOS signing, Supabase Realtime readiness, production Monnify, security/RLS, and finance reconciliation are clean.
