import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Handles Firebase Authentication with Google Sign-In, Email/Password, and Guest Mode.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GoogleSignIn? get _googleSignIn {
    if (kIsWeb) return null;
    try {
      return GoogleSignIn();
    } catch (_) {
      return null;
    }
  }

  /// Current signed-in user (null if not signed in)
  User? get currentUser => _auth.currentUser;

  /// User UID for scoping Firebase data
  String get uid => _auth.currentUser?.uid ?? 'guest_student';

  /// User email or fallback
  String get email => _auth.currentUser?.email ?? 'guest@hellobuddy.local';

  /// User display name or fallback
  String get displayName {
    if (_auth.currentUser?.displayName != null &&
        _auth.currentUser!.displayName!.isNotEmpty) {
      return _auth.currentUser!.displayName!;
    }
    if (_auth.currentUser?.email != null) {
      return _auth.currentUser!.email!.split('@').first;
    }
    return 'Student Buddy';
  }

  /// Whether user is currently signed in
  bool get isSignedIn => _auth.currentUser != null;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with Google
  Future<User?> signInWithGoogle() async {
    final googleSignIn = _googleSignIn;
    if (googleSignIn == null) {
      throw Exception('Google Sign-In is not supported on this platform.');
    }

    try {
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      throw Exception('Google Sign-In failed: $e');
    }
  }

  /// Sign in with email and password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e.code));
    } catch (e) {
      throw Exception('Login error: $e');
    }
  }

  /// Register new account with email and password
  Future<User?> registerWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e.code));
    } catch (e) {
      throw Exception('Registration error: $e');
    }
  }

  /// Sign in anonymously / guest student mode
  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      debugPrint('Anonymous auth fallback: $e');
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Map Firebase error codes to human-readable messages
  String _mapAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email. Tap "Register" below to create one.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password or invalid credentials.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Please sign in instead.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'network-request-failed':
        return 'Network connection failed. Check your internet connection.';
      default:
        return 'Authentication notice: $code';
    }
  }
}
