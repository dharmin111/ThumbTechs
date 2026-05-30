// widgets/TechnicianHomeScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TechnicianHomeScreen extends StatefulWidget {
  const TechnicianHomeScreen({super.key});

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  String? technicianName;
  List<String> technicianCategories = [];
  List<String> technicianPincodes = [];
  bool isAvailable = true;
  int totalPending = 0;
  List<QueryDocumentSnapshot> pendingRequests = [];
  bool isLoading = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _fetchTechnicianData();
  }

  @override
  void dispose() {
    _isActive = false;
    super.dispose();
  }

  Future<void> _fetchTechnicianData() async {
    if (!_isActive || !mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;

          List<String> pincodesList = [];
          if (data['pincodes'] != null && (data['pincodes'] as List).isNotEmpty) {
            pincodesList = List<String>.from(data['pincodes']);
          } else if (data['pincode'] != null && data['pincode'].toString().isNotEmpty) {
            pincodesList = [data['pincode'].toString()];
          }

          if (!_isActive || !mounted) return;

          setState(() {
            technicianName = data['name'] ?? 'Technician';
            technicianCategories = List<String>.from(data['categories'] ?? []);
            technicianPincodes = pincodesList;
            isAvailable = data['isActive'] ?? true;
          });

          if (technicianCategories.isNotEmpty && technicianPincodes.isNotEmpty) {
            await _fetchPendingRequests();
          } else {
            if (!_isActive || !mounted) return;
            setState(() {
              isLoading = false;
            });
            _showIncompleteProfileDialog();
          }
        } else {
          if (!_isActive || !mounted) return;
          setState(() {
            isLoading = false;
          });
          _showIncompleteProfileDialog();
        }
      }
    } catch (e) {
      print('Error fetching technician data: $e');
      if (!_isActive || !mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fetchPendingRequests() async {
    if (technicianCategories.isEmpty || technicianPincodes.isEmpty) {
      if (!_isActive || !mounted) return;
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('service_requests')
          .where('status', isEqualTo: 'pending')
          .where('technicianId', isNull: true)
          .orderBy('createdAt', descending: true)
          .get();

      final filteredRequests = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final serviceType = data['serviceType'] ?? '';
        final customerPincode = data['pincode']?.toString() ?? '';

        final categoryMatches = technicianCategories.contains(serviceType);
        final pincodeMatches = technicianPincodes.contains(customerPincode);

        return categoryMatches && pincodeMatches;
      }).toList();

      if (!_isActive || !mounted) return;

      setState(() {
        pendingRequests = filteredRequests;
        totalPending = filteredRequests.length;
        isLoading = false;
      });

      print('📊 Found ${filteredRequests.length} matching requests');
    } catch (e) {
      print('Error fetching pending requests: $e');
      if (!_isActive || !mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _acceptRequest(String requestId, Map<String, dynamic> requestData) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .update({
        'technicianId': user.uid,
        'technicianName': technicianName,
        'technicianPhone': user.phoneNumber ?? '',
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': requestData['userId'],
        'userRole': 'customer',
        'title': '✅ Request Accepted!',
        'body': '$technicianName has accepted your service request.',
        'type': 'request_accepted',
        'requestId': requestId,
        'technicianName': technicianName,
        'technicianPhone': user.phoneNumber ?? '',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!_isActive || !mounted) {
        Navigator.pop(context);
        return;
      }

      setState(() {
        pendingRequests.removeWhere((doc) => doc.id == requestId);
        totalPending = pendingRequests.length;
      });

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service request accepted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      Navigator.pop(context);
      print('Error accepting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!_isActive || !mounted) return;

      setState(() {
        pendingRequests.removeWhere((doc) => doc.id == requestId);
        totalPending = pendingRequests.length;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request rejected'),
          backgroundColor: Colors.orange,
        ),
      );

    } catch (e) {
      print('Error rejecting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rejecting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'isActive': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!_isActive || !mounted) return;

      setState(() {
        isAvailable = value;
      });

      if (value) {
        await _fetchPendingRequests();
      } else {
        if (!_isActive || !mounted) return;
        setState(() {
          pendingRequests = [];
          totalPending = 0;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'You are now available for service' : 'You are now offline'),
          backgroundColor: value ? Colors.green : Colors.orange,
        ),
      );

    } catch (e) {
      print('Error toggling availability: $e');
    }
  }

  void _showIncompleteProfileDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Profile Incomplete'),
        content: const Text(
          'Please complete your technician profile with categories and pincodes to start receiving service requests.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            child: const Text('Complete Profile'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _fetchPendingRequests,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildWelcomeBanner(),
            _buildAvailabilityToggle(),
            _buildStatsCards(),
            _buildPendingRequests(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2563EB).withOpacity(0.1),
            const Color(0xFF2563EB).withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            technicianName ?? 'Technician',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          if (technicianCategories.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: technicianCategories.map((category) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    category,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB)),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 4),
          Text(
            'Service Areas: ${technicianPincodes.isNotEmpty ? technicianPincodes.join(", ") : "Not set"}',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isAvailable ? Icons.circle : Icons.circle_outlined,
                color: isAvailable ? Colors.green : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isAvailable ? 'Available for Service' : 'Offline',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isAvailable ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          Switch(
            value: isAvailable,
            onChanged: _toggleAvailability,
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Pending Tasks',
              totalPending.toString(),
              Icons.pending_actions,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Categories',
              technicianCategories.length.toString(),
              Icons.category,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Areas',
              technicianPincodes.length.toString(),
              Icons.location_on,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequests() {
    if (technicianCategories.isEmpty || technicianPincodes.isEmpty) {
      return _buildIncompleteProfileWidget();
    }

    if (!isAvailable) {
      return _buildOfflineWidget();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Service Requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tasks matching your categories and service areas',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          if (pendingRequests.isEmpty)
            _buildEmptyWidget()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pendingRequests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                var request = pendingRequests[index];
                return _buildRequestCard(request);
              },
            ),
        ],
      ),
    );
  }

  // ✅ Updated Request Card with 3-minute countdown timer
  Widget _buildRequestCard(QueryDocumentSnapshot request) {
    Map<String, dynamic> data = request.data() as Map<String, dynamic>;
    final createdAt = (data['createdAt'] as Timestamp).toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with timer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'New Request',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                _buildCountdownTimer(createdAt),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        data['serviceName'] ?? 'Service Request',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '₹${data['budget']?.toString() ?? '0'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['userName'] ?? 'Customer',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['userPhone'] ?? 'No phone',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['location'] ?? 'Location not specified',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_city, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Pincode: ${data['pincode'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                if (data['issue'] != null && data['issue'].isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Issue:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data['issue'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _showRequestDetails(request.id, data);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF2563EB)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _showAcceptDialog(request.id, data);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _showRejectDialog(request.id);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 3-Minute Countdown Timer Widget (Shows 0:00 when expired)
  Widget _buildCountdownTimer(DateTime createdAt) {
    return StatefulBuilder(
      builder: (context, setStateTimer) {
        final expiryTime = createdAt.add(const Duration(minutes: 3));

        return StreamBuilder(
          stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
          builder: (context, snapshot) {
            final now = DateTime.now();
            final remaining = expiryTime.difference(now);

            if (remaining.isNegative) {
              // Show "0:00" when expired (not hide)
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_off, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    const Text(
                      '0:00',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            }

            final minutes = remaining.inMinutes;
            final seconds = remaining.inSeconds.remainder(60);

            // Color changes based on time left
            Color timerColor;
            if (minutes >= 2) {
              timerColor = Colors.green;
            } else if (minutes >= 1) {
              timerColor = Colors.orange;
            } else {
              timerColor = Colors.red;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: timerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: timerColor),
                  const SizedBox(width: 4),
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAcceptDialog(String requestId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to accept this service request?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service: ${data['serviceName']}'),
                  const SizedBox(height: 4),
                  Text('Budget: ₹${data['budget']}'),
                  const SizedBox(height: 4),
                  Text('Customer: ${data['userName']}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptRequest(requestId, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request'),
        content: const Text('Are you sure you want to reject this request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectRequest(requestId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _showRequestDetails(String requestId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['serviceName'] ?? 'Service Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Customer Name', data['userName'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Phone', data['userPhone'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Email', data['userEmail'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Service Type', data['serviceType'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Location', data['location'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Pincode', data['pincode'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildDetailRow('Budget', '₹${data['budget'] ?? 0}'),
              const SizedBox(height: 8),
              _buildDetailRow('Issue', data['issue'] ?? 'N/A'),
              if (data['additionalNote'] != null && data['additionalNote'].isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Additional Note', data['additionalNote']),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildIncompleteProfileWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[400]),
          const SizedBox(height: 16),
          const Text(
            'Profile Incomplete',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please complete your profile to start receiving requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.toggle_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'You are offline',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Turn on availability to see pending service requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No pending requests',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Tasks matching your categories and pincode will appear here',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}