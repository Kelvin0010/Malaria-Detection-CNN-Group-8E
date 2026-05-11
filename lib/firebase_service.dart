import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- AUTHENTICATION ---

  // Get currently logged-in user
  User? get currentUser => _auth.currentUser;

  // Listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with Email and Password
  Future<UserCredential?> signUpWithEmailPassword(
      String email, String password, String name) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update the display name
      await credential.user?.updateDisplayName(name);

      // Create an initial profile document in Firestore
      if (credential.user != null) {
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'uid': credential.user!.uid,
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("Signup Error: ${e.message}");
      rethrow;
    }
  }

  // Login with Email and Password
  Future<UserCredential?> loginWithEmailPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint("Login Error: ${e.message}");
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }

  // --- FIRESTORE DATABASE ---

  // Save a new scan result
  Future<void> saveScanResult({
    required String status,
    required double confidence,
    required String? imagePath,
  }) async {
    if (currentUser == null) {
      throw Exception("Must be logged in to save scans.");
    }

    try {
      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('scans')
          .add({
        'status': status,
        'confidence': confidence,
        'imagePath':
            imagePath, // Optional: if using Firebase Storage, you'd upload first and save URL
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error saving scan: $e");
      rethrow;
    }
  }

  // Get stream of past scans
  Stream<QuerySnapshot> getScanHistory() {
    try {
      final uid = currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        // When no user, return a stream from a dummy collection
        return _firestore
            .collection('scans_placeholder')
            .where('uid', isEqualTo: '')
            .snapshots();
      }

      return _firestore
          .collection('users')
          .doc(uid)
          .collection('scans')
          .orderBy('timestamp', descending: true)
          .snapshots();
    } catch (e) {
      debugPrint("Error in getScanHistory: $e");
      // On error, return a dummy stream that will show no data
      return _firestore
          .collection('scans_placeholder')
          .where('uid', isEqualTo: '')
          .snapshots();
    }
  }

  // Get user profile from Firestore
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (currentUser == null) return null;

    try {
      final doc =
          await _firestore.collection('users').doc(currentUser!.uid).get();
      return doc.data();
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      return null;
    }
  }
}
