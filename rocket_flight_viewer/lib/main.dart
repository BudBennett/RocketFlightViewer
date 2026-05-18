import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'controllers/flight_controller.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => FlightController(),
      child: const RocketFlightViewerApp(),
    ),
  );
}

class RocketFlightViewerApp extends StatelessWidget {
  const RocketFlightViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FlightController>(
      builder: (context, ctrl, _) => MaterialApp(
        title: 'Rocket Flight Viewer',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        themeMode: ctrl.themeMode,
        home: const HomeScreen(),
      ),
    );
  }
}
