import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileData {
  String name;
  String title;
  String? imagePath;
  String email;
  String phone;
  String location;

  ProfileData({
    required this.name,
    required this.title,
    this.imagePath,
    this.email = '',
    this.phone = '',
    this.location = '',
  });
}

class AppState {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  
  static final ValueNotifier<ProfileData> profileNotifier = ValueNotifier(
    ProfileData(
      name: '',
      title: '',
      email: '',
      phone: '',
      location: '',
    ),
  );

  // Load persisted profile data from SharedPreferences and Firestore
  static Future<void> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('profile_name') ?? '';
    String title = prefs.getString('profile_title') ?? '';
    String email = prefs.getString('profile_email') ?? '';
    String phone = prefs.getString('profile_phone') ?? '';
    String location = prefs.getString('profile_location') ?? '';
    String? imagePath = prefs.getString('profile_imagePath');

    // Load from Firebase Firestore if logged in
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Read primary user document
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        // Also check legacy sub-collection doc if primary doesn't have custom fields
        DocumentSnapshot<Map<String, dynamic>>? legacyDoc;
        if (!userDoc.exists || userDoc.data()?['title'] == null) {
          legacyDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('profile')
              .doc('data')
              .get();
        }

        final data = userDoc.data() ?? {};
        final legacyData = legacyDoc?.data() ?? {};

        final firestoreName = (data['name'] ?? legacyData['name'] ?? user.displayName) as String?;
        final firestoreTitle = (data['title'] ?? legacyData['title']) as String?;
        final firestoreEmail = (data['email'] ?? legacyData['email'] ?? user.email) as String?;
        final firestorePhone = (data['phone'] ?? legacyData['phone']) as String?;
        final firestoreLocation = (data['location'] ?? legacyData['location']) as String?;
        final firestoreImagePath = (data['imagePath'] ?? legacyData['imagePath'] ?? user.photoURL) as String?;

        if (firestoreName != null && firestoreName.isNotEmpty) name = firestoreName;
        if (firestoreTitle != null && firestoreTitle.isNotEmpty) title = firestoreTitle;
        if (firestoreEmail != null && firestoreEmail.isNotEmpty) email = firestoreEmail;
        if (firestorePhone != null && firestorePhone.isNotEmpty) phone = firestorePhone;
        if (firestoreLocation != null && firestoreLocation.isNotEmpty) location = firestoreLocation;
        
        // Prioritize non-null image path
        if (firestoreImagePath != null && firestoreImagePath.isNotEmpty) {
          imagePath = firestoreImagePath;
        }

        // Cache loaded values to SharedPreferences
        await prefs.setString('profile_name', name);
        await prefs.setString('profile_title', title);
        await prefs.setString('profile_email', email);
        await prefs.setString('profile_phone', phone);
        await prefs.setString('profile_location', location);
        if (imagePath != null) {
          await prefs.setString('profile_imagePath', imagePath);
        }
      }
    } catch (e) {
      debugPrint('Error loading profile from Firestore: $e');
    }

    // Update global state notifier
    profileNotifier.value = ProfileData(
      name: name.isNotEmpty ? name : 'User',
      title: title.isNotEmpty ? title : 'Diagnostic Specialist',
      email: email,
      phone: phone,
      location: location,
      imagePath: imagePath,
    );
  }

  // Save current profile data to SharedPreferences and sync with Firebase
  static Future<void> saveProfile(ProfileData profile) async {
    // 1. Immediately update UI state
    profileNotifier.value = profile;

    // 2. Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', profile.name);
    await prefs.setString('profile_title', profile.title);
    await prefs.setString('profile_email', profile.email);
    await prefs.setString('profile_phone', profile.phone);
    await prefs.setString('profile_location', profile.location);

    // Upload profile image to Firebase Storage if a local file path is provided
    String? uploadedImageUrl;
    if (profile.imagePath != null && !profile.imagePath!.startsWith('http')) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final file = File(profile.imagePath!);
          if (await file.exists()) {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('users')
                .child(user.uid)
                .child('profile_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await storageRef.putFile(file);
            uploadedImageUrl = await storageRef.getDownloadURL();
          }
        }
      } catch (e) {
        debugPrint('Error uploading profile image: $e');
      }
    }

    // Determine which image path to store (uploaded URL or original)
    final imagePathToStore = uploadedImageUrl ?? profile.imagePath;
    if (imagePathToStore != null) {
      await prefs.setString('profile_imagePath', imagePathToStore);
      profile.imagePath = imagePathToStore;
      profileNotifier.value = profile;
    } else {
      await prefs.remove('profile_imagePath');
    }

    // Sync to Firebase Firestore (both root user doc and legacy subcollection)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profileMap = {
          'name': profile.name,
          'title': profile.title,
          'email': profile.email,
          'phone': profile.phone,
          'location': profile.location,
          'imagePath': imagePathToStore,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Update main user document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(profileMap, SetOptions(merge: true));

        // Update legacy doc location for compatibility
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('profile')
            .doc('data')
            .set(profileMap, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error syncing profile to Firestore: $e');
    }
  }

  // Clear local profile cache on logout
  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_name');
    await prefs.remove('profile_title');
    await prefs.remove('profile_email');
    await prefs.remove('profile_phone');
    await prefs.remove('profile_location');
    await prefs.remove('profile_imagePath');

    profileNotifier.value = ProfileData(
      name: '',
      title: '',
      email: '',
      phone: '',
      location: '',
      imagePath: null,
    );
  }
}
