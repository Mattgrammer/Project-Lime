import 'package:flutter/material.dart';
import 'pages/sign_in_page.dart';

void main () {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WELCCOME TO LIME',
      home:  StartupPage(),
    );
  }
}

// INTRODUCTION TO LIME
class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State <StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {

  @override
    Widget build(BuildContext context){
      return Scaffold(
        backgroundColor: Colors.teal,
        body: Center(
          child: ElevatedButton(
              onPressed: (){
                // NAVIGATE TO SIGN IN PAGE
                Navigator.push(
                  context,
                    MaterialPageRoute(builder: (context) => const SignInPage()),
                  );
                },
              child: const Text('SIGN IN')
            ),
          ),
        );
      }
    }