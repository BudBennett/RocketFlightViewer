import 'package:flutter/material.dart';
import 'home_screen.dart';

// Update kAppVersion when bumping pubspec.yaml version.
const String kAppVersion = 'v2.0.1';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF263238), // blueGrey[900]
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/icon.png'),
              width: 120,
              height: 120,
            ),
            SizedBox(height: 28),
            Text(
              'Rocket Flight Viewer',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'by Bud Bennett',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF90A4AE), // blueGrey[300]
              ),
            ),
            SizedBox(height: 4),
            Text(
              kAppVersion,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF607D8B), // blueGrey[500]
              ),
            ),
          ],
        ),
      ),
    );
  }
}
