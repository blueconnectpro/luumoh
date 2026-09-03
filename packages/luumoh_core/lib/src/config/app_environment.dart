import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_env.dart';

class AppEnvironment {
  const AppEnvironment({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.mapboxAccessToken,
  });

  factory AppEnvironment.fromDartDefines() {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabasePublishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    );
    const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
    final resolvedSupabaseUrl = _normalizeSupabaseUrl(
      supabaseUrl.isNotEmpty ? supabaseUrl : LocalEnv.supabaseUrl,
    );
    final resolvedPublishableKey = supabasePublishableKey.isNotEmpty
        ? supabasePublishableKey
        : LocalEnv.supabasePublishableKey;
    final resolvedMapboxAccessToken = mapboxAccessToken.isNotEmpty
        ? mapboxAccessToken
        : LocalEnv.mapboxAccessToken;

    if (resolvedSupabaseUrl.isEmpty || resolvedPublishableKey.isEmpty) {
      debugPrint(
        'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY. Run scripts/sync-flutter-env.ps1 or pass dart defines.',
      );
    }

    return AppEnvironment(
      supabaseUrl: resolvedSupabaseUrl,
      supabasePublishableKey: resolvedPublishableKey,
      mapboxAccessToken: resolvedMapboxAccessToken,
    );
  }

  static String storeIdFromConfig() {
    const dartDefineStoreId = String.fromEnvironment('STORE_ID');
    return dartDefineStoreId.isNotEmpty ? dartDefineStoreId : LocalEnv.storeId;
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String mapboxAccessToken;

  String? get supabaseConfigurationError {
    if (supabaseUrl.trim().isEmpty || supabasePublishableKey.trim().isEmpty) {
      return 'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY.';
    }

    final uri = Uri.tryParse(supabaseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return 'SUPABASE_URL must be a valid absolute URL.';
    }

    if (kReleaseMode && uri.scheme != 'https') {
      return 'SUPABASE_URL must use HTTPS in release builds.';
    }

    return null;
  }

  Future<void> initializeSupabase() {
    final error = supabaseConfigurationError;
    if (error != null) {
      throw StateError(error);
    }

    return Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  static Future<void> recoverPersistedSession(SupabaseClient client) async {
    final session = client.auth.currentSession;
    if (session == null || !session.isExpired) {
      return;
    }

    try {
      await client.auth.refreshSession().timeout(const Duration(seconds: 12));
    } on Object {
      await client.auth.signOut();
    }
  }
}

String _normalizeSupabaseUrl(String value) {
  final decoded = Uri.decodeFull(value.trim()).trim();
  final match = RegExp(r'https://[^\s/]+').firstMatch(decoded);
  if (match != null) {
    return match.group(0)!.replaceAll(RegExp(r'/+$'), '');
  }
  return decoded.replaceAll(RegExp(r'/+$'), '');
}
