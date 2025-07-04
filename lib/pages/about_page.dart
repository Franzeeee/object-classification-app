import 'package:flutter/material.dart';
import 'package:object_classification_1/main.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset('assets/images/user.png', width: 100, height: 100, ),
            const Text(
              'Object Classification Demo',
              style: TextStyle(
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
                color: Colors.red
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'This app demonstrates object classification using machine learning.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.0),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage())); // Navigate to the route named '/home'
              },
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}