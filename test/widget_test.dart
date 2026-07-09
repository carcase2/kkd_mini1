import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discipline_tracker/main.dart';
import 'package:discipline_tracker/providers/app_state.dart';

void main() {
  testWidgets('App loads home', (WidgetTester tester) async {
    final appState = AppState();
    // skip load for unit test (empty state)
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const DisciplineApp(),
      ),
    );
    await tester.pump();
    expect(find.text('절제'), findsOneWidget);
  });
}
