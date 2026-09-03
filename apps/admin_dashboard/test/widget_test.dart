import 'package:flutter_test/flutter_test.dart';
import 'package:luumoh_core/luumoh_core.dart';

import 'package:luumoh_admin_dashboard/main.dart';

void main() {
  testWidgets('shows setup message when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AdminDashboardApp(
        environment: AppEnvironment(
          supabaseUrl: '',
          supabasePublishableKey: '',
          mapboxAccessToken: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setup needed'), findsOneWidget);
  });
}
