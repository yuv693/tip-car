import 'package:flutter_test/flutter_test.dart';
import 'package:tip_car_bus/main.dart';

void main() {
  testWidgets('Tip Car app shows setup guidance when backend is not configured', (tester) async {
    await tester.pumpWidget(const TipCarApp(configured: false));
    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
  });
}
