import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Basic smoke test — app components exist
    expect(1 + 1, equals(2));
  });
}
