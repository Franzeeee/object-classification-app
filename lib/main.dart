import 'package:flutter/material.dart';
import 'package:object_classification_1/pages/home_page.dart';
import 'package:object_classification_1/pages/detect_page.dart';
import 'package:object_classification_1/pages/about_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Object Classification Demo",
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: MainPage()
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {

  int _activePage = 0;

  final List<Widget> _pages = [
    HomePage(),
    DetectPage(),
    AboutPage()
  ];

  void _onPageChanged(int index) {
    setState(() {
      _activePage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_activePage],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _activePage,
        backgroundColor: const Color.fromARGB(204, 54, 33, 236),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        onTap: _onPageChanged,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: "Detect"),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: "About")
        ],
      ),
    );
  }
}