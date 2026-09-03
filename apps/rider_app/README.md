# Luumoh Rider App

Flutter app for riders to accept pickup-ready paid orders, update customer-facing ETAs, and mark deliveries completed.

Run it with Supabase credentials:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

The signed-in account must have the `rider` role in `profiles`.
