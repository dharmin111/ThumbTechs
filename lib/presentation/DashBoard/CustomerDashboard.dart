import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thumstechs/presentation/CostomerScreens/ServiceBookingScreen.dart';
import '../../Services/oneSignalNotificationService .dart';
import '../CostomerScreens/BookingScreen.dart';
import '../CostomerScreens/MyBookingsScreen.dart';
import '../CostomerScreens/ProfileScreen.dart';
import '../CostomerScreens/ServiceDetailScreen.dart';
import '../authScreen/LoginScreen.dart';

const primaryCyan = Color(0xFF42D7D7);
const darkBlue = Color(0xFF0C1B4D);
const lightBlue = Color(0xFF7EC8FF);
const yellow = Color(0xFFFFD428);
const background = Color(0xFFFFFFFF);

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? userData;
  bool isLoading = true;
  String searchQuery = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    loadUserData();
    _ensureOneSignalId();
  }

  Future<void> _ensureOneSignalId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final existingId = doc.data()?['oneSignalId'];

    if (existingId == null || existingId.isEmpty) {
      await OneSignalNotificationService.saveCurrentUserOneSignalId();
    }
  }

  Future<void> loadUserData() async {
    try {
      final user = auth.currentUser;

      if (user == null) {
        navigateToLogin();
        return;
      }

      final doc = await firestore.collection("users").doc(user.uid).get();

      if (doc.exists) {
        setState(() {
          userData = doc.data();
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  String getUserName() {
    if (userData != null && userData!.containsKey('name')) {
      return userData!['name'];
    }
    return "User";
  }

  void navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void onServiceTap(String serviceName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailScreen(serviceName: serviceName),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showNotifications() {
    // TODO: Implement notification screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifications coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Original Home Screen Content - Keeping same UI
  Widget _buildHomeScreen() {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            // Header Section - Thumb Tech Name and Notification Bell
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Thumb Tech Name
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Thumb Tech",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: darkBlue,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Hi, ${getUserName()}",
                        style: TextStyle(
                          fontSize: 14,
                          color: darkBlue.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),

                  // Notification Bell Icon
                  GestureDetector(
                    onTap: _showNotifications,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        children: [
                          Icon(
                            Icons.notifications_none,
                            color: darkBlue,
                            size: 24,
                          ),
                          // Optional: Unread notification badge
                          // Positioned(
                          //   right: 0,
                          //   top: 0,
                          //   child: Container(
                          //     width: 10,
                          //     height: 10,
                          //     decoration: const BoxDecoration(
                          //       color: Colors.red,
                          //       shape: BoxShape.circle,
                          //     ),
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: "Search services...",
                    prefixIcon: Icon(Icons.search, color: primaryCyan),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Categories Section - Scrollable
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildCategorySection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    // Appliance Repair Services with different images
    List<Map<String, String>> applianceServices = [
      {'name': 'AC Repair & Service', 'image': 'assets/Appliance/Ac.jpeg'},
      {'name': 'Washing Machine Repair', 'image': 'assets/Appliance/Ap1.png'},
      {'name': 'Water Purifier', 'image': 'assets/Appliance/waterp.jpeg'},
      {'name': 'Microwave Repair', 'image': 'assets/Appliance/ap2.png'},
      {'name': 'Chimney Repair', 'image': 'assets/Appliance/chimney.jpeg'},
      {'name': 'Geyser Repair', 'image': 'assets/Appliance/ap3.png'},
    ];

    // Home Repair Services with different images
    List<Map<String, String>> homeServices = [
      {'name': 'CCTV Installation & Services', 'image': 'assets/Appliance/hm1.png'},
      {'name': 'TV Repair', 'image': 'assets/Appliance/ap8.png'},
      {'name': 'Plumbing Service', 'image': 'assets/Appliance/ap4.png'},
      {'name': 'Air Cooler Repair', 'image': 'assets/Appliance/ap6.png'},
      {'name': 'Refrigerator Repair', 'image': 'assets/Appliance/ap7.png'},
      {'name': 'Carpenter', 'image': 'assets/Appliance/ap5.png'},
      {'name': 'Water Tank Cleaning', 'image': 'assets/Appliance/hm2.png'},
      {'name': 'Electrical Work', 'image': 'assets/Appliance/elec1.png'},
    ];

    // Filter based on search query
    if (searchQuery.isNotEmpty) {
      applianceServices = applianceServices
          .where((service) =>
          service['name']!.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
      homeServices = homeServices
          .where((service) =>
          service['name']!.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    if (applianceServices.isEmpty && homeServices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No services found'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Three Pictures Row - Horizontally Scrollable (only show when not searching)
        if (searchQuery.isEmpty)
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              itemBuilder: (context, index) {
                List<String> imagePaths = [
                  'assets/AppLogoo/thirdstart.PNG',
                  'assets/AppLogoo/secondstart.PNG',
                  'assets/AppLogoo/firststart.PNG',
                ];
                return _buildPromoImage(imagePaths[index % imagePaths.length]);
              },
            ),
          ),

        if (searchQuery.isEmpty) const SizedBox(height: 18),

        // Appliance Repair & Service - Title
        if (applianceServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Appliance Repair & Service",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkBlue,
              ),
            ),
          ),

        if (applianceServices.isNotEmpty) const SizedBox(height: 16),

        // 2 Column Grid for Appliance Services
        if (applianceServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2,
              ),
              itemCount: applianceServices.length,
              itemBuilder: (context, index) {
                return _buildImageOnly(
                  serviceName: applianceServices[index]['name']!,
                  imagePath: applianceServices[index]['image']!,
                );
              },
            ),
          ),

        if (applianceServices.isNotEmpty && homeServices.isNotEmpty)
          const SizedBox(height: 20),

        // Home Repair & Installation - Title
        if (homeServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Home Repair & Installation",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkBlue,
              ),
            ),
          ),

        if (homeServices.isNotEmpty) const SizedBox(height: 16),

        // 2 Column Grid for Home Services
        if (homeServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2,
              ),
              itemCount: homeServices.length,
              itemBuilder: (context, index) {
                return _buildImageOnly(
                  serviceName: homeServices[index]['name']!,
                  imagePath: homeServices[index]['image']!,
                );
              },
            ),
          ),

        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildImageOnly({required String serviceName, required String imagePath}) {
    return GestureDetector(
      onTap: () {
        onServiceTap(serviceName);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.asset(
            imagePath,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade100,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.miscellaneous_services,
                      size: 40,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Image not found',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                    ),
                    Text(
                      serviceName,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPromoImage(String imagePath) {
    return GestureDetector(
      onTap: () {
        onServiceTap("Promotional Offer");
      },
      child: Container(
        width: 350,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            imagePath,
            width: 280,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 280,
                height: 180,
                color: Colors.grey.shade200,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'Image not found',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // List of screens for each tab
    final List<Widget> _screens = [
      _buildHomeScreen(),        // Home (index 0) - Your original UI
      const ServiceBookingScreen(),     // Booking (index 1)
      const MyBookingsScreen(),  // My Bookings (index 2)
      const ProfileScreen(),     // Profile (index 3)
    ];

    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.white,
          selectedItemColor: primaryCyan,
          unselectedItemColor: darkBlue.withOpacity(0.5),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.book_online_outlined),
              activeIcon: Icon(Icons.book_online),
              label: 'Booking',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              activeIcon: Icon(Icons.list_alt),
              label: 'My Bookings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}