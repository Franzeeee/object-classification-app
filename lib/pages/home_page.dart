import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Object Classification Demo", style: TextStyle(color: Colors.white),),
        backgroundColor: const Color.fromARGB(204, 54, 33, 236),
      ),
      body: Center(
        child: Text("Welcome to Object Classification Demo",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20.0,
            color: Colors.black,
            fontWeight: FontWeight.bold,

          ),),
      ),
    );
  }
}