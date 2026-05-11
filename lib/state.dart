import 'package:flutter/material.dart';

class ProfileData {
  String name;
  String title;
  String? imagePath;

  ProfileData({
    required this.name,
    required this.title,
    this.imagePath,
  });
}

class AppState {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  
  static final ValueNotifier<ProfileData> profileNotifier = ValueNotifier(
    ProfileData(
      name: 'Dr. John Doe',
      title: 'Diagnostic Specialist',
    ),
  );
}
