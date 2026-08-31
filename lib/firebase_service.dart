import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- AUTHENTICATION ---

  // Get currently logged-in user
  User? get currentUser => _auth.currentUser;

  // Listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // On Web: use Firebase Auth's signInWithPopup directly.
        // The google_sign_in package's signIn() popup is broken on web
        // due to Cross-Origin-Opener-Policy headers blocking communication.
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // On Mobile: use the google_sign_in package flow
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          // User canceled the sign-in flow
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      // Save/Update user profile in Firestore safely
      final user = userCredential.user;
      if (user != null) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();

          if (!userDoc.exists) {
            // First time sign in, create profile
            await _firestore.collection('users').doc(user.uid).set({
              'uid': user.uid,
              'name': user.displayName ?? 'User',
              'title': 'Diagnostic Specialist',
              'email': user.email ?? '',
              'phone': '',
              'location': '',
              'imagePath': user.photoURL, // Store Google photo URL
              'createdAt': FieldValue.serverTimestamp(),
              'lastLogin': FieldValue.serverTimestamp(),
            });
          } else {
            // Document exists: record login time, do NOT overwrite custom name/photo
            await _firestore.collection('users').doc(user.uid).update({
              'lastLogin': FieldValue.serverTimestamp(),
            });
          }
        } catch (fsError) {
          debugPrint("Firestore User Profile save warning: $fsError");
        }
      }

      return userCredential;
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    await _auth.signOut();
  }

  // --- FIRESTORE DATABASE ---

  // Save a new scan result
  // This method also creates a patient record for each valid scan (Parasitized or Uninfected).
  // The patient ID is automatically generated as BS-XXX using a Firestore counter.
  Future<void> saveScanResult({
    required String status,
    required double confidence,
    required String? imagePath,
  }) async {
    if (currentUser == null) {
      throw Exception("Must be logged in to save scans.");
    }

    try {
      // Add scan document and capture reference
      DocumentReference scanRef = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('scans')
          .add({
        'status': status,
        'confidence': confidence,
        'imagePath': imagePath,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Create patient record for valid scans (exclude Invalid)
      if (status != 'Invalid') {
        // Atomically get and increment patient counter
        DocumentReference counterRef = _firestore
            .collection('users')
            .doc(currentUser!.uid)
            .collection('metadata')
            .doc('patient_counter');

        await _firestore.runTransaction((transaction) async {
          DocumentSnapshot counterSnap = await transaction.get(counterRef);
          int nextNumber = 1;
          if (counterSnap.exists && counterSnap.data() != null) {
            final data = counterSnap.data() as Map<String, dynamic>;
            nextNumber = (data['next'] as int?) ?? 1;
          }
          // Update counter for next call
          transaction.set(counterRef, {'next': nextNumber + 1});
          // Build patient ID
          String patientId = 'BS-${nextNumber.toString().padLeft(3, '0')}';
          // Create patient document
          transaction.set(
            _firestore
                .collection('users')
                .doc(currentUser!.uid)
                .collection('patients')
                .doc(),
            {
              'patientId': patientId,
              'name': '',
              'address': '',
              'contact': '',
              'gender': '',
              'status': status,
              'confidence': confidence,
              'scanDate': FieldValue.serverTimestamp(),
              'imagePath': imagePath,
              'scanRef': scanRef.id,
            },
          );
        });
      }
    } catch (e) {
      debugPrint("Error saving scan or patient: $e");
      rethrow;
    }
  }

  // Stream of patient records ordered by most recent scan date
  Stream<QuerySnapshot> getPatients() {
    if (currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('patients')
        .orderBy('scanDate', descending: true)
        .snapshots();
  }

  // Update editable fields of a patient document
  Future<void> updatePatient(String docId, Map<String, dynamic> data) async {
    if (currentUser == null) return;
    await _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('patients')
        .doc(docId)
        .update(data);
  }

  // Delete a patient record
  Future<void> deletePatient(String docId) async {
    if (currentUser == null) return;
    await _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('patients')
        .doc(docId)
        .delete();
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
