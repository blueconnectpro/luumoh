import 'package:flutter_test/flutter_test.dart';
import 'package:luumoh_core/luumoh_core.dart';

import 'package:luumoh_rider_app/main.dart';

void main() {
  testWidgets('shows setup message when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RiderApp(
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
