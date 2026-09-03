# Luumoh Engineering Standards

## Architecture

- Keep app-specific presentation in each app under `lib/features/<feature>`.
- Keep shared Supabase access, Mapbox access, domain models, and payment helpers in `packages/luumoh_core`.
- Prefer feature files over expanding app `main.dart`; app `main.dart` should only own startup, dependency wiring, high-level navigation, and temporary glue while a feature is being split.
- Keep backend behavior in versioned Supabase migrations and Edge Functions. Client apps should call RLS-protected tables/views or explicit RPCs, not duplicate business rules.
- Reuse shared models for Supabase rows so customer, store, rider, and admin apps agree on field names and parsing behavior.

## Configuration

- Production builds must receive `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` through Dart defines or generated local env files.
- `SUPABASE_URL` is validated centrally by `AppEnvironment`; release builds must use HTTPS.
- Mapbox and payment secrets must not be shipped in mobile apps. Use public client tokens in apps and keep Monnify secret keys in Supabase Edge Function environment variables.
- Do not commit `.env`, generated `local_env.dart`, Android keystores, Google service files, or Apple signing assets.

## Security

- Use Supabase Row Level Security as the primary data boundary.
- Keep privileged account operations in Edge Functions that use the service role key server-side only.
- Do not log access tokens, payment secrets, customer addresses, or full webhook payloads in app logs.
- Use migrations for policy/function changes and include `notify pgrst, 'reload schema';` when PostgREST schema cache must refresh.
- Prefer typed RPC/function inputs and explicit role checks for admin, rider admin, store admin, and store manager workflows.

## Quality Gates

- Every app and package must include the workspace root `analysis_options.yaml`.
- Run `flutter analyze` for `packages/luumoh_core` and each app before merging.
- Run the app smoke tests after startup/configuration changes.
- Add focused tests when changing payment, order lifecycle, notifications, account deletion, address selection, or role access behavior.
