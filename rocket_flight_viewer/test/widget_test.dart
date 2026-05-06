import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rocket_flight_viewer/controllers/flight_controller.dart';
import 'package:rocket_flight_viewer/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FlightController(),
        child: const RocketFlightViewerApp(),
      ),
    );
    expect(find.text('Rocket Flight Viewer'), findsOneWidget);
  });
}
