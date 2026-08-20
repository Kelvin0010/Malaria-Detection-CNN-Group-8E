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

  // Load persisted profile data from SharedPreferences
  static Future<void> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('profile_name') ?? '';
    final title = prefs.getString('profile_title') ?? '';
    final email = prefs.getString('profile_email') ?? '';
    final phone = prefs.getString('profile_phone') ?? '';
    final location = prefs.getString('profile_location') ?? '';
    final imagePath = prefs.getString('profile_imagePath');
    // Load from Firebase Firestore if logged in
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('profile')
            .doc('data')
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          // Override with Firestore values if they exist
          final nameFb = data['name'] as String? ?? name;
          final titleFb = data['title'] as String? ?? title;
          final emailFb = data['email'] as String? ?? email;
          final phoneFb = data['phone'] as String? ?? phone;
          final locationFb = data['location'] as String? ?? location;
          final firestoreImagePath = data['imagePath'] as String?;
          // Prioritize locally stored image path if available
          final finalImagePath = imagePath ?? firestoreImagePath;
          profileNotifier.value = ProfileData(
            name: nameFb,
            title: titleFb,
            email: emailFb,
            phone: phoneFb,
            location: locationFb,
            imagePath: finalImagePath,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading profile from Firestore: $e');
    }
    // Fallback to SharedPreferences values
    profileNotifier.value = ProfileData(
      name: name,
      title: title,
      email: email,
      phone: phone,
      location: location,
      imagePath: imagePath,
    );
  }

  // Save current profile data to SharedPreferences and sync with Firebase
  static Future<void> saveProfile(ProfileData profile) async {
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
                .child('profile.jpg');
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
    } else {
      await prefs.remove('profile_imagePath');
    }

    // Sync to Firebase Firestore
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('profile')
            .doc('data');
        await docRef.set({
          'name': profile.name,
          'title': profile.title,
          'email': profile.email,
          'phone': profile.phone,
          'location': profile.location,
          'imagePath': imagePathToStore,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error syncing profile to Firestore: $e');
    }
  }
}
