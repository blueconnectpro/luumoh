import 'package:flutter_test/flutter_test.dart';
import 'package:luumoh_core/luumoh_core.dart';

import 'package:luumoh_customer_app/main.dart';

void main() {
  testWidgets('shows setup screen when Supabase config is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const CustomerApp(
        environment: AppEnvironment(
          supabaseUrl: '',
          supabasePublishableKey: '',
          mapboxAccessToken: '',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Setup needed'), findsOneWidget);
    expect(
      find.textContaining('Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY'),
      findsOneWidget,
    );
  });
}
