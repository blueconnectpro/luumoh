# Luumoh Store App

Flutter app for store staff to manage inventory availability, stock adjustments, and paid order preparation.

Run it with Supabase credentials and the selected store ID:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... --dart-define=STORE_ID=...
```

The signed-in account must be a member of the selected store in `store_members`.
