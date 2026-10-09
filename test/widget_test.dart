import 'package:flutter_test/flutter_test.dart';
import 'package:tricrypt_app/main.dart';

void main() {
  testWidgets('TriCryptApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TriCryptApp());
    expect(find.byType(TriCryptApp), findsOneWidget);
  });
}
