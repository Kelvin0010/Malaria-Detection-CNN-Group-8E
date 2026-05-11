import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'state.dart';
import 'auth_screens.dart';
import 'ml_service.dart';
import 'firebase_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MalariaDetectorApp());
}

class MalariaDetectorApp extends StatelessWidget {
  const MalariaDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Malaria Detector',
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF4A64FE), // Deep vibrant blue/indigo
            scaffoldBackgroundColor:
                const Color(0xFFF4F7FC), // Soft light background
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4A64FE),
              secondary: Color(0xFF10B981),
              surface: Colors.white,
            ),
            fontFamily: 'Roboto',
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF4A64FE),
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4A64FE),
              secondary: Color(0xFF10B981),
              surface: Color(0xFF1E1E1E),
            ),
            fontFamily: 'Roboto',
            useMaterial3: true,
          ),
          home: const LoginScreen(),
        );
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  void _showScanSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ScanBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardView(
              onSeeAllClicked: () => setState(() => _currentIndex = 1)),
          const HistoryView(),
          const ProfileView(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showScanSheet,
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.document_scanner, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 10,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(Icons.home,
                    color: _currentIndex == 0
                        ? Theme.of(context).primaryColor
                        : Colors.grey),
                onPressed: () => setState(() => _currentIndex = 0),
              ),
              const SizedBox(width: 48), // Space for FAB
              IconButton(
                icon: Icon(Icons.person,
                    color: _currentIndex == 2
                        ? Theme.of(context).primaryColor
                        : Colors.grey),
                onPressed: () => setState(() => _currentIndex = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  final VoidCallback onSeeAllClicked;
  const DashboardView({super.key, required this.onSeeAllClicked});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return SingleChildScrollView(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Curved Header
              Container(
                height: 240,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, const Color(0xFF7C8DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
                ),
                padding: const EdgeInsets.only(top: 60, left: 24, right: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<ProfileData>(
                          valueListenable: AppState.profileNotifier,
                          builder: (context, profile, _) {
                            final firstName = (profile.name.isNotEmpty
                                ? profile.name.split(" ").first
                                : 'User');
                            return Text(
                              'Hello, $firstName!',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ready for today\'s diagnoses?',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()));
                      },
                      child: const CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.notifications, color: Colors.white),
                      ),
                    )
                  ],
                ),
              ),
              // Overlapping Card
              Positioned(
                top: 150,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(Icons.science, color: primaryColor, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Malaria Detector',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap the + button to start a scan',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 50), // Space for overlapping card

          // Categories Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Categories',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCategoryIcon(context, Icons.analytics, 'Reports',
                        const Color(0xFF4A64FE), () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ReportsScreen()));
                    }),
                    _buildCategoryIcon(context, Icons.people, 'Patients',
                        const Color(0xFF00C853), () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PatientsScreen()));
                    }),
                    _buildCategoryIcon(context, Icons.library_books,
                        'Guidelines', const Color(0xFFFF9100), () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const GuidelinesScreen()));
                    }),
                    _buildCategoryIcon(context, Icons.settings, 'Settings',
                        const Color(0xFF9C27B0), () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()));
                    }),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Recent Scans
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Scans',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: onSeeAllClicked,
                      child: const Text('See all'),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                _buildHistoryCard(context, 'Patient A - Smear', '2 hours ago',
                    'Parasitized', true),
                const SizedBox(height: 12),
                _buildHistoryCard(context, 'Patient B - Smear', 'Yesterday',
                    'Uninfected', false),
                const SizedBox(height: 12),
                _buildHistoryCard(context, 'Patient C - Smear', '2 days ago',
                    'Uninfected', false),
                const SizedBox(height: 80), // Space for bottom nav
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryIcon(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, String title, String date,
      String status, bool isParasitized) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.image, color: Colors.grey[400]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(date,
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isParasitized
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: isParasitized ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanBottomSheet extends StatefulWidget {
  const ScanBottomSheet({super.key});

  @override
  State<ScanBottomSheet> createState() => _ScanBottomSheetState();
}

class _ScanBottomSheetState extends State<ScanBottomSheet>
    with SingleTickerProviderStateMixin {
  String? _imagePath;
  bool _isProcessing = false;
  String _result = '';
  double _confidence = 0.0;
  final ImagePicker _picker = ImagePicker();
  final MLService _mlService = MLService();
  final FirebaseService _firebaseService = FirebaseService();
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _imagePath = pickedFile.path;
          _result = '';
          _confidence = 0.0;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _imagePath = null;
      _result = '';
      _confidence = 0.0;
    });
  }

  Future<void> _analyzeImage() async {
    if (_imagePath == null) return;

    setState(() {
      _isProcessing = true;
      _result = '';
    });

    final result = await _mlService.processImage(File(_imagePath!));

    try {
      // Push the result to Firebase!
      await _firebaseService.saveScanResult(
        status: result['status'],
        confidence: result['confidence'],
        imagePath: _imagePath,
      );
    } catch (e) {
      debugPrint("Failed to save to Firebase (are you logged in?): $e");
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _result = result['status'];
        _confidence = result['confidence'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'New Analysis',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () => _imagePath == null
                        ? _pickImage(ImageSource.gallery)
                        : null,
                    child: Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _imagePath != null
                              ? Colors.transparent
                              : Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: _imagePath != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: kIsWeb
                                      ? Image.network(_imagePath!,
                                          fit: BoxFit.cover)
                                      : Image.file(File(_imagePath!),
                                          fit: BoxFit.cover),
                                ),
                                if (_isProcessing)
                                  AnimatedBuilder(
                                    animation: _scanController,
                                    builder: (context, child) {
                                      return Positioned(
                                        top: _scanController.value * 230,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).primaryColor,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Theme.of(context)
                                                    .primaryColor
                                                    .withValues(alpha: 0.6),
                                                blurRadius: 8,
                                                spreadRadius: 2,
                                              )
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                if (!_isProcessing)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.white),
                                        onPressed: _clearImage,
                                        tooltip: 'Remove Image',
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 64,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tap to select from gallery',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 16),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_imagePath == null)
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side:
                              BorderSide(color: Theme.of(context).primaryColor),
                        ),
                        elevation: 0,
                      ),
                    ),
                  if (_imagePath != null && _result.isEmpty) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _analyzeImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Analyze Image',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                    ),
                  ],
                  if (_result.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: CircularProgressIndicator(
                              value: _confidence / 100,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey[200],
                              color: _result == 'Parasitized'
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_confidence.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Confidence',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _result == 'Parasitized'
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          'Result: $_result',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _result == 'Parasitized'
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
