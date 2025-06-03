import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_stripe/flutter_stripe.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/add_book_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/auth_screen.dart'; // ✅ Login + Register

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Stripe.publishableKey = 'pk_test_51RUBb506qYbiVpDgiR1gF4WmtLH91pOZH6YMxDGKM6gNyMvTPveeCjdDd15kxUmBm0ntbzrHvjiO9evmpgATBZC000M8OzKYkW'; // Your Stripe Publishable Key
  tz.initializeTimeZones();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(BookApp());
}

class BookApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'RAAHEE GLOBAL BOOKS LIBRARY',
          theme: ThemeData(
            primarySwatch: Colors.deepOrange, // Primary color for the app
            scaffoldBackgroundColor: Colors.white, // Background color for all screens
            textTheme: TextTheme(
              displayLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // Large titles
              titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), // Section titles
              bodyLarge: TextStyle(fontSize: 12, color: Colors.black), // Default body text
              bodyMedium: TextStyle(fontSize: 10, color: Colors.grey[700]), // Secondary text
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange, // Button color
                foregroundColor: Colors.white, // Text color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), // Rounded corners
                ),
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              selectedItemColor: Colors.deepOrange, // Selected item color
              unselectedItemColor: Colors.grey, // Unselected item color
              backgroundColor: Colors.white, // Background color
            ),
            chipTheme: ChipThemeData(
              backgroundColor: Colors.deepOrange.shade50,
              selectedColor: Colors.deepOrange.shade100,
              labelStyle: TextStyle(color: Colors.deepOrange),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.deepOrange,
            scaffoldBackgroundColor: Colors.black,
            textTheme: TextTheme(
              displayLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              bodyLarge: TextStyle(fontSize: 12, color: Colors.white),
              bodyMedium: TextStyle(fontSize: 10, color: Colors.grey[300]),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              selectedItemColor: Colors.deepOrange,
              unselectedItemColor: Colors.grey,
              backgroundColor: Colors.grey[900],
            ),
            chipTheme: ChipThemeData(
              backgroundColor: Colors.deepOrange.shade900,
              selectedColor: Colors.deepOrange.shade700,
              labelStyle: TextStyle(color: Colors.white),
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: MainNavigation(key: mainNavKey),
          routes: {
            '/home': (context) => MainNavigation(), // ✅ Add this
            '/register': (context) => AuthScreen(), // Optional
          },
          themeMode: mode,
        );
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  MainNavigationState createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    BrowseScreen(),
    AddBookScreen(),
    LibraryScreen(),
    // ProfileScreen(), // Removed
  ];

  void onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return AuthScreen(); // 👈 Redirect to login if logged out
        }
        return Scaffold(
          body: _screens[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: onItemTapped,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Browse'),
              BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Add Book'),
              BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'My Library'),
              // BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'), // Removed
            ],
          ),
        );
      },
    );
  }
}

final GlobalKey<MainNavigationState> mainNavKey = GlobalKey<MainNavigationState>();
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();
