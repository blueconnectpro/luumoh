# Luumoh Admin Dashboard

Flutter web dashboard for creating and monitoring Luumoh stores, products, and platform operations.

Run it with the cloud Supabase Dart defines:

```bash
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Before creating products, push the latest Supabase migrations from the repository root:

```bash
npx supabase db push
```
