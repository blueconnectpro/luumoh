import 'package:flutter_test/flutter_test.dart';
import 'package:luumoh_workspace/main.dart';

void main() {
  testWidgets('workspace shell lists the Luumoh apps', (tester) async {
    await tester.pumpWidget(const LuumohWorkspaceApp());

    expect(find.text('Luumoh Workspace'), findsWidgets);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Rider'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
