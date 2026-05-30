import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:thumstechs/presentation/authScreen/LoginScreen.dart';
import '../../Services/oneSignalNotificationService .dart';
import '../TechnicianScreen/TechnicianHomeScreen.dart';
import '../TechnicianScreen/TechnicianMyServicesScreen.dart';
import '../TechnicianScreen/TechnicianProfileScreen.dart';

class TechnicianDashboard extends StatefulWidget {
  const TechnicianDashboard({super.key});

  @override
  State<TechnicianDashboard> createState() => _TechnicianDashboardState();
}

class _TechnicianDashboardState extends State<TechnicianDashboard> {
  int _selectedIndex = 0;
  bool _isOneSignalSaved = false;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  @override
  void dispose() {
    _isActive = false;
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    if (!_isActive || !mounted) return;

    // First ensure OneSignal is initialized
    await OneSignalNotificationService.initialize();

    // Then save the ID
    await _saveOneSignalId();
  }

  Future<void> _saveOneSignalId() async {
    if (!_isActive || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Check if OneSignal ID already exists
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!_isActive || !mounted) return;

      final existingId = userDoc.data()?['oneSignalId'];

      if (existingId == null || existingId.toString().isEmpty) {
        print('📱 Saving OneSignal ID for technician...');
        final saved = await OneSignalNotificationService.saveOneSignalId(
          userId: user.uid,
          userRole: 'technician',
        );

        if (!_isActive || !mounted) return;

        if (saved) {
          setState(() {
            _isOneSignalSaved = true;
          });
          print('✅ OneSignal ID saved successfully');
        } else {
          print('❌ Failed to save OneSignal ID');
        }
      } else {
        print('✅ OneSignal ID already exists: $existingId');
        setState(() {
          _isOneSignalSaved = true;
        });
      }
    } catch (e) {
      print('❌ Error saving OneSignal ID: $e');
      if (!_isActive || !mounted) return;
    }
  }

  Future<void> _refreshOneSignalId() async {
    if (!_isActive || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enabling notifications...'),
        duration: Duration(seconds: 1),
      ),
    );

    final saved = await OneSignalNotificationService.saveOneSignalId(
      userId: user.uid,
      userRole: 'technician',
    );

    if (!_isActive || !mounted) return;

    if (saved) {
      setState(() {
        _isOneSignalSaved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Notifications enabled!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Failed to enable notifications. Please restart app.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Technician Dashboard             ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          // Show notification status icon
          IconButton(
            icon: Icon(
              _isOneSignalSaved ? Icons.notifications_active : Icons.notifications_off,
              color: _isOneSignalSaved ? Colors.green : Colors.red,
            ),
            onPressed: _refreshOneSignalId,
            tooltip: _isOneSignalSaved ? 'Notifications enabled' : 'Enable notifications',
          ),
          // IconButton(
          //   icon: const Icon(Icons.logout),
          //   onPressed: () {
          //    // _showLogoutDialog();
          //   },
          // ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const TechnicianHomeScreen();
      case 1:
        return const TechnicianMyServicesScreen();
      case 2:
        return const TechnicianProfileScreen();
      default:
        return const TechnicianHomeScreen();
    }
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF2563EB),
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.build_outlined),
          activeIcon: Icon(Icons.build),
          label: 'My Services',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
  // void _showLogoutDialog() {
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (BuildContext dialogContext) => AlertDialog(
  //       title: const Text('Logout'),
  //       content: const Text('Are you sure you want to logout?'),
  //       actions: [
  //         TextButton(
  //           onPressed: () {
  //             Navigator.pop(dialogContext);
  //           },
  //           child: const Text('Cancel'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () async {
  //             // Close the dialog first
  //             if (mounted) {
  //               Navigator.pop(dialogContext);
  //             }
  //
  //             try {
  //               // Show loading indicator using a new dialog
  //               if (mounted) {
  //                 showDialog(
  //                   context: context,
  //                   barrierDismissible: false,
  //                   builder: (BuildContext loadingContext) => const Center(
  //                     child: CircularProgressIndicator(),
  //                   ),
  //                 );
  //               }
  //
  //               // Remove OneSignal ID on logout
  //               final user = FirebaseAuth.instance.currentUser;
  //               if (user != null) {
  //                 await OneSignalNotificationService.removeOneSignalId(user.uid);
  //               }
  //
  //               // Sign out
  //               await FirebaseAuth.instance.signOut();
  //
  //               // Small delay to ensure sign out completes
  //               await Future.delayed(const Duration(milliseconds: 500));
  //
  //               // Check if widget is still mounted before navigation
  //               if (mounted) {
  //                 // Close loading dialog if still open
  //                 if (Navigator.canPop(context)) {
  //                   Navigator.pop(context);
  //                 }
  //
  //                 // Navigate to login screen
  //                 Navigator.pushAndRemoveUntil(
  //                   context,
  //                   MaterialPageRoute(
  //                     builder: (context) => const LoginScreen(),
  //                   ),
  //                       (route) => false,
  //                 );
  //               }
  //             } catch (e) {
  //               print('Logout error: $e');
  //               if (mounted) {
  //                 // Close loading dialog if open
  //                 if (Navigator.canPop(context)) {
  //                   Navigator.pop(context);
  //                 }
  //                 ScaffoldMessenger.of(context).showSnackBar(
  //                   const SnackBar(
  //                     content: Text('Error logging out'),
  //                     backgroundColor: Colors.red,
  //                   ),
  //                 );
  //               }
  //             }
  //           },
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.red,
  //           ),
  //           child: const Text(
  //             'Logout',
  //             style: TextStyle(color: Colors.white),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}