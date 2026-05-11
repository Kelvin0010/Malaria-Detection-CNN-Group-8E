import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'state.dart';
import 'auth_screens.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

// --- Shared Widgets ---
Widget buildStatusPill(String status, bool isParasitized) {
  return Container(
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
  );
}

// --- History View (Used in Bottom Nav) ---
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final FirebaseService _firebaseService = FirebaseService();
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text('Scan History',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search patients or dates...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: ['All', 'Parasitized', 'Uninfected'].map((filter) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (selected) {
                      setState(() => _filter = filter);
                    },
                    selectedColor:
                        Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    checkmarkColor: Theme.of(context).primaryColor,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firebaseService.getScanHistory(),
              builder: (context, snapshot) {
                try {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    debugPrint("HistoryView error: ${snapshot.error}");
                    return Center(
                        child:
                            Text('Error loading history: ${snapshot.error}'));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No scan history found.'));
                  }

                  final docs = snapshot.data!.docs;
                  // Client-side filtering based on _filter
                  final filteredDocs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status'] as String? ?? 'Unknown';
                    if (_filter == 'All') return true;
                    return status == _filter;
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(child: Text('No $_filter scans found.'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final data =
                          filteredDocs[index].data() as Map<String, dynamic>;
                      final status = data['status'] as String? ?? 'Unknown';
                      final confidence =
                          (data['confidence'] as num?)?.toDouble() ?? 0.0;
                      final isParasitized = status == 'Parasitized';

                      // Format timestamp if available
                      String timeAgo = 'Just now';
                      if (data['timestamp'] != null) {
                        final timestamp = data['timestamp'] as Timestamp;
                        final diff =
                            DateTime.now().difference(timestamp.toDate());
                        if (diff.inDays > 0) {
                          timeAgo = '${diff.inDays} days ago';
                        } else if (diff.inHours > 0) {
                          timeAgo = '${diff.inHours} hours ago';
                        } else if (diff.inMinutes > 0) {
                          timeAgo = '${diff.inMinutes} mins ago';
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.image, color: Colors.grey),
                          ),
                          title: Text('Conf: ${confidence.toStringAsFixed(1)}%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(timeAgo,
                              style: const TextStyle(color: Colors.grey)),
                          trailing: buildStatusPill(status, isParasitized),
                        ),
                      );
                    },
                  );
                } catch (e) {
                  debugPrint("Error building HistoryView: $e");
                  return Center(child: Text('Error: $e'));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Profile View ---
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 80, bottom: 30),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40)),
            ),
            child: ValueListenableBuilder<ProfileData>(
              valueListenable: AppState.profileNotifier,
              builder: (context, profile, _) {
                ImageProvider? avatarImage;
                if (profile.imagePath != null) {
                  avatarImage = kIsWeb
                      ? NetworkImage(profile.imagePath!)
                      : FileImage(File(profile.imagePath!)) as ImageProvider;
                }

                return Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? const Icon(Icons.person,
                                  size: 60, color: Colors.white)
                              : null,
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const EditProfileScreen()));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: Icon(Icons.edit,
                                size: 20,
                                color: Theme.of(context).primaryColor),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(profile.name,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(profile.title,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatCard('Scans', '1,204'),
                        const SizedBox(width: 16),
                        _buildStatCard('Accuracy', '98.5%'),
                      ],
                    )
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildProfileOption(context, Icons.person_outline,
              'Personal Information', const PersonalInfoScreen()),
          _buildProfileOption(context, Icons.work_outline, 'Work Schedule',
              const WorkScheduleScreen()),
          _buildProfileOption(context, Icons.lock_outline, 'Privacy & Security',
              const PrivacySecurityScreen()),
          _buildProfileOption(context, Icons.help_outline, 'Help & Support',
              const HelpSupportScreen()),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white24, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildProfileOption(
      BuildContext context, IconData icon, String title, Widget destination) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => destination));
        },
      ),
    );
  }
}

// --- Edit Profile Screen ---
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();
    final profile = AppState.profileNotifier.value;
    _nameController.text = profile.name;
    _titleController.text = profile.title;
    _selectedImagePath = profile.imagePath;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImagePath = pickedFile.path);
    }
  }

  void _saveProfile() {
    AppState.profileNotifier.value = ProfileData(
      name: _nameController.text,
      title: _titleController.text,
      imagePath: _selectedImagePath,
    );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')));
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (_selectedImagePath != null) {
      avatarImage = kIsWeb
          ? NetworkImage(_selectedImagePath!)
          : FileImage(File(_selectedImagePath!)) as ImageProvider;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor:
                        Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Icon(Icons.person,
                            size: 60, color: Theme.of(context).primaryColor)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 20),
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'Full Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: 'Job Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Save Changes',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- Profile Sub-Pages ---
class PersonalInfoScreen extends StatelessWidget {
  const PersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Information')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ListTile(
              title: Text('Email Address'),
              subtitle: Text('doctor@hospital.com'),
              leading: Icon(Icons.email)),
          ListTile(
              title: Text('Phone Number'),
              subtitle: Text('+1 (555) 123-4567'),
              leading: Icon(Icons.phone)),
          ListTile(
              title: Text('Location'),
              subtitle: Text('Global Health Clinic, NY'),
              leading: Icon(Icons.location_on)),
        ],
      ),
    );
  }
}

class WorkScheduleScreen extends StatelessWidget {
  const WorkScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Work Schedule')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ListTile(
              title: Text('Monday - Friday'),
              subtitle: Text('08:00 AM - 05:00 PM')),
          ListTile(title: Text('Saturday'), subtitle: Text('On Call')),
          ListTile(title: Text('Sunday'), subtitle: Text('Off')),
        ],
      ),
    );
  }
}

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(
        children: [
          SwitchListTile(
              title: const Text('Biometric Login (Face/Touch ID)'),
              value: true,
              onChanged: (val) {}),
          SwitchListTile(
              title: const Text('Two-Factor Authentication'),
              value: false,
              onChanged: (val) {}),
          const ListTile(
              title: Text('Change Password'),
              trailing: Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        children: const [
          ListTile(title: Text('FAQs'), trailing: Icon(Icons.chevron_right)),
          ListTile(
              title: Text('Contact Support'),
              subtitle: Text('support@malariadetector.app'),
              leading: Icon(Icons.support_agent)),
          ListTile(
              title: Text('App Version'), subtitle: Text('v1.0.0 (Build 42)')),
        ],
      ),
    );
  }
}

// --- Notifications Screen ---
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications cleared.')));
            },
            child: const Text('Clear All'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text('TODAY',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildNotificationCard(
              context,
              'New Report Available',
              'Patient A\'s malaria smear analysis is complete.',
              '2 mins ago',
              true),
          _buildNotificationCard(
              context,
              'System Update',
              'The diagnostic AI model has been updated to v2.1.',
              '1 hour ago',
              false),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text('YESTERDAY',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildNotificationCard(context, 'Meeting Reminder',
              'Team sync in 30 minutes.', '1 day ago', false),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, String title,
      String subtitle, String time, bool isUnread) {
    return Card(
      elevation: 0,
      color: isUnread
          ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
          : Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isUnread
            ? BorderSide(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor:
              isUnread ? Theme.of(context).primaryColor : Colors.grey[200],
          child: Icon(Icons.notifications,
              color: isUnread ? Colors.white : Colors.grey[600]),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(subtitle),
        ),
        trailing: Text(time,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }
}

// --- Reports Screen ---
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics & Reports')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monthly Overview',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                    child: _buildMetricCard(context, 'Total Scans', '428',
                        Icons.document_scanner, Colors.blue)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildMetricCard(context, 'Positive Rate', '14%',
                        Icons.coronavirus, Colors.red)),
              ],
            ),
            const SizedBox(height: 32),
            const Text('Diagnostic Confidence',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                            value: 0.95,
                            strokeWidth: 12,
                            backgroundColor: Colors.grey[200],
                            color: Colors.green),
                        const Center(
                            child: Text('95%',
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('High Accuracy',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        SizedBox(height: 8),
                        Text(
                            'The AI model is operating with 95% average confidence across all smears this week.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Weekly Volume',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Container(
              height: 200,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildMockBar(0.4, 'Mon'),
                  _buildMockBar(0.7, 'Tue'),
                  _buildMockBar(0.5, 'Wed'),
                  _buildMockBar(0.9, 'Thu'),
                  _buildMockBar(0.6, 'Fri'),
                  _buildMockBar(0.3, 'Sat'),
                  _buildMockBar(0.2, 'Sun'),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 16),
          Text(value,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMockBar(double heightFactor, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 20,
          height: 120 * heightFactor,
          decoration: BoxDecoration(
            color: const Color(0xFF4A64FE),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// --- Patients Screen ---
class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Directory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search patients...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 12,
              itemBuilder: (context, index) {
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    child: Text('P${index + 1}',
                        style:
                            TextStyle(color: Theme.of(context).primaryColor)),
                  ),
                  title: Text('Patient ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: #883${index}2'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                PatientDetailsScreen(patientId: index + 1)));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Patient Details Screen ---
class PatientDetailsScreen extends StatelessWidget {
  final int patientId;
  const PatientDetailsScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Patient $patientId')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor:
                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: Text('P$patientId',
                    style: TextStyle(
                        fontSize: 32, color: Theme.of(context).primaryColor)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('Patient $patientId',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            Center(
              child: Text('ID: #883${patientId}2 • Male • 34 yrs',
                  style: const TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 32),
            const Text('Medical History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                title: const Text('Blood Smear Analysis',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Date: 2 days ago'),
                trailing: buildStatusPill('Uninfected', false),
              ),
            ),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                title: const Text('Blood Smear Analysis',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Date: 4 months ago'),
                trailing: buildStatusPill('Parasitized', true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Guidelines Screen ---
class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guidelines & Protocols')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ExpansionTile(
            title: Text('Sample Preparation',
                style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                  '1. Prepare a thick or thin blood smear on a clean glass slide.\n2. Allow the smear to air dry completely.\n3. Stain the slide using Giemsa or Field\'s stain according to standard protocols.\n4. Ensure the stain is properly washed and dried before placing it under the microscope.')
            ],
          ),
          ExpansionTile(
            title: Text('Capturing Images for AI',
                style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                  '1. Use a high-quality smartphone camera or digital microscope camera.\n2. Ensure uniform lighting across the smear.\n3. Focus strictly on the erythrocytes (red blood cells).\n4. Avoid capturing edges of the slide or air bubbles.')
            ],
          ),
          ExpansionTile(
            title: Text('WHO Malaria Protocol',
                style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                  'The World Health Organization recommends microscopy as the gold standard for malaria diagnosis. This AI tool is designed to assist microscopists by highlighting potential parasites, but final diagnosis must be confirmed by a trained professional.')
            ],
          ),
        ],
      ),
    );
  }
}

// --- Settings Screen ---
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppState.themeNotifier,
        builder: (context, currentMode, _) {
          bool isDark = currentMode == ThemeMode.dark;
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('PREFERENCES',
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: isDark,
                onChanged: (val) {
                  AppState.themeNotifier.value =
                      val ? ThemeMode.dark : ThemeMode.light;
                },
              ),
              SwitchListTile(
                title: const Text('Push Notifications'),
                value: true,
                onChanged: (val) {},
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('ACCOUNT',
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                title: const Text('Language'),
                trailing:
                    const Text('English', style: TextStyle(color: Colors.grey)),
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                title: const Text('About Malaria Detector'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Malaria Detector',
                    applicationVersion: '1.0.0',
                    applicationIcon: const Icon(Icons.science, size: 48),
                  );
                },
              ),
              ListTile(
                title:
                    const Text('Logout', style: TextStyle(color: Colors.red)),
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to log out?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          },
                          child: const Text('Logout',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
