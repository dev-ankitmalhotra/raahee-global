import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:google_sign_in_web/google_sign_in_web.dart'; // Only for web
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'; // <-- Add this import
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;

  String _email = '';
  String _password = '';
  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  void _trySubmit() async {
    final isValid = _formKey.currentState?.validate();
    FocusScope.of(context).unfocus(); // Close keyboard

    if (!isValid!) return;

    _formKey.currentState?.save();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(email: _email, password: _password);
      } else {
        await _auth.createUserWithEmailAndPassword(email: _email, password: _password);
      }
      Navigator.of(context).pushReplacementNamed('/home'); // Navigate to main app
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: code=${e.code}, message=${e.message}'); // More details
      setState(() {
        _error = e.message ?? 'Authentication error (${e.code})';
      });
} catch (e) {
      print('Unexpected error: $e'); // <-- Add this line
      setState(() {
        _error = 'An unexpected error occurred.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      GoogleSignIn googleSignIn;
      // Only set clientId for iOS/macOS
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
        googleSignIn = GoogleSignIn(
          clientId: '16978501659-pt4311isi2jkbinh7rkp2mvsv624h1ma.apps.googleusercontent.com',
        );
      } else {
        googleSignIn = GoogleSignIn();
      }
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // User cancelled
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await _auth.signInWithCredential(oauthCredential);
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() => _error = 'Apple sign-in failed: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // RAAHEE Logo
              Image.asset(
                'raahee_logo.png',
                height: 150, // Adjust size as needed
                width: 150,
              ),
              SizedBox(height: 32),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isLogin ? 'Login to Your Account' : 'Register an Account',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (_error != null) ...[
                            SizedBox(height: 12),
                            Text(_error!, style: TextStyle(color: Colors.red)),
                          ],
                          SizedBox(height: 16),
                          TextFormField(
                            key: ValueKey('email'),
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(labelText: 'Email'),
                            validator: (value) {
                              if (value == null || !value.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                            onSaved: (value) {
                              _email = value!.trim();
                            },
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            key: ValueKey('password'),
                            decoration: InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                            onSaved: (value) {
                              _password = value!.trim();
                            },
                          ),
                          SizedBox(height: 24),
                          if (_isLoading)
                            CircularProgressIndicator()
                          else
                            ElevatedButton(
                              onPressed: _trySubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(_isLogin ? 'Login' : 'Register'),
                            ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _error = null;
                              });
                            },
                            child: Text(_isLogin
                                ? 'Don’t have an account? Register here'
                                : 'Already have an account? Login'),
                          ),
                          SizedBox(height: 12),
                          Text('or', style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 12),
                          if (!_isLoading) ...[
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: Icon(Icons.login),
                              label: Text('Sign in with Google'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                minimumSize: Size(double.infinity, 44),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              onPressed: _signInWithGoogle,
                            ),
                            if (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
                              SizedBox(height: 8),
                            if (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
                              ElevatedButton.icon(
                                icon: Icon(Icons.apple),
                                label: Text('Sign in with Apple'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(double.infinity, 44),
                                ),
                                onPressed: _signInWithApple,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } 
}

// Custom widget for web Google Sign-In button
// class GoogleSignInButton extends StatefulWidget {
//   @override
//   _GoogleSignInButtonState createState() => _GoogleSignInButtonState();
// }

// class _GoogleSignInButtonState extends State<GoogleSignInButton> {
//   @override
//   void initState() {
//     super.initState();
//     GoogleSignIn().onCurrentUserChanged.listen((account) {
//       if (account != null) {
//         // User signed in, navigate or update state
//         Navigator.of(context).pushReplacementNamed('/home');
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     // This will render the Google button using the new web API
//     return SizedBox(
//       height: 48,
//       child: GoogleSignIn().renderButton(),
//     );
//   }
// }
