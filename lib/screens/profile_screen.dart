import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/generic_app_bar.dart';
import '../main.dart'; // Import themeModeNotifier

class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: GenericAppBar(
        title: 'Profile',
        onNotificationTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Notification tapped!')),
          );
        },
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Welcome, ${user?.email ?? "Unknown"}!', style: TextStyle(fontSize: 18)),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  child: Text('Logout'),
                )
              ],
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              return SwitchListTile(
                title: Text('Dark Theme'),
                value: mode == ThemeMode.dark,
                onChanged: (isDark) {
                  themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
                },
                secondary: Icon(
                  mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
