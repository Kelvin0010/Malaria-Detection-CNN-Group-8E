import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'ml_service.dart';
import 'firebase_service.dart';
import 'screens.dart';
import 'chat_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  late final ErrorWidgetBuilder _previousErrorWidgetBuilder;

  @override
  void initState() {
    super.initState();
    debugPrint('MainLayout initState called');
    _previousErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      final message = details.exceptionAsString();
      debugPrint('MainLayout ErrorWidget.builder called: $message');
      return Container(
        color: Colors.white,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            const Text('Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    };
  }

  @override
  void dispose() {
    ErrorWidget.builder = _previousErrorWidgetBuilder;
    super.dispose();
  }

  void _showScanSheet() {
    Future.microtask(() {
      try {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const ScanBottomSheet(),
        );
      } catch (e, stackTrace) {
        debugPrint('Failed to open scan sheet: $e');
        debugPrintStack(stackTrace: stackTrace);
        _showErrorSnackbar('Unable to open scan sheet. Please try again.');
      }
    });
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MainLayout build, currentIndex=$_currentIndex');
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildViewWithErrorBoundary(
            'Dashboard',
            DashboardView(
                onSeeAllClicked: () => setState(() => _currentIndex = 1)),
          ),
          _buildViewWithErrorBoundary('History', const HistoryView()),
          _buildViewWithErrorBoundary('Profile', const ProfileView()),
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
        color: Theme.of(context).colorScheme.surface,
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

  Widget _buildViewWithErrorBoundary(String name, Widget child) {
    return Builder(
      builder: (context) {
        try {
          return child;
        } catch (e, stackTrace) {
          debugPrint('Error in $name view: $e');
          debugPrintStack(stackTrace: stackTrace);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: Theme.of(context).primaryColor),
                const SizedBox(height: 16),
                Text('Error loading $name'),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }
      },
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
  String _invalidReason = '';
  final ImagePicker _picker = ImagePicker();
  final MLService _mlService = MLService();
  final FirebaseService _firebaseService = FirebaseService();
  late AnimationController _scanController;

  /// True only on Android / iOS — features like camera and TFLite
  /// are not available on Windows / macOS / Linux desktop.
  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
      _invalidReason = '';
    });
  }

  Future<void> _analyzeImage() async {
    if (_imagePath == null) return;

    setState(() {
      _isProcessing = true;
      _result = '';
      _invalidReason = '';
    });

    final result = await _mlService.processImage(File(_imagePath!));
    final status = result['status'] as String;
    final confidence = (result['confidence'] as num).toDouble();
    final reason = result['reason'] as String? ?? '';

    // Only save valid scan results to Firebase
    if (status != 'Invalid') {
      try {
        await _firebaseService.saveScanResult(
          status: status,
          confidence: confidence,
          imagePath: _imagePath,
        );
      } catch (e) {
        debugPrint("Failed to save to Firebase: $e");
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _result = status;
        _confidence = confidence;
        _invalidReason = reason;
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
                  // Camera capture is only available on mobile platforms
                  if (_imagePath == null && _isMobilePlatform)
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

                    // ── Invalid image ──────────────────────────────────────
                    if (_result == 'Invalid') ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'Not a Blood Smear Image',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _invalidReason.isNotEmpty
                                  ? _invalidReason
                                  : 'Please upload a Giemsa-stained or bright-field blood smear microscopy image.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[700]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _clearImage,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try Again'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Valid scan result ──────────────────────────────────
                    if (_result != 'Invalid') ...[
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
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold),
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
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                scanResult: _result,
                                confidence: _confidence,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Get AI Doctor Recommendations'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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
