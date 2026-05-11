import 'package:flutter_test/flutter_test.dart';
import 'package:malaria_app/main.dart';

void main() {
  testWidgets('Malaria app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MalariaDetectorApp());

    // Verify that our initial text is shown.
    expect(find.text('Upload Blood Smear'), findsOneWidget);
  });
}
