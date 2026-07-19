// lib/presentation/membership/MembershipScreen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/MembershipService.dart';


class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _planStatus;

  // 🔥 Web URL for payment (Firebase Hosting)
  static const String _webUrl = 'https://thumbtech-521ae.web.app/plans';

  @override
  void initState() {
    super.initState();
    _loadPlanStatus();
  }

// In MembershipScreen.dart
  Future<void> _loadPlanStatus() async {
    setState(() => _isLoading = true);
    try {
      // 🔥 Now this works!
      _planStatus = await MembershipService.getPlanStatus();

      if (_planStatus!['isActive'] == true) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
    setState(() => _isLoading = false);
  }

  // 🔥 Open Web Link for Payment
  Future<void> _openWebPayment() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Please login first');
      }

      // 🔥 Open web URL with userId
      final url = Uri.parse('$_webUrl?userId=${user.uid}');

      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        // User will come back after payment
        // Refresh plan status when app resumes
      } else {
        throw 'Could not launch payment page';
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Membership Plans',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0C1B4D),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0C1B4D)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // 🔥 Plan Status Card
              _buildPlanStatusCard(),

              const SizedBox(height: 24),

              // 🔥 Plans Grid
              _buildPlansGrid(),

              const SizedBox(height: 16),

              // 🔥 Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // 🔥 Note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You will be redirected to our secure payment page to complete your subscription.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 Plan Status Card
  Widget _buildPlanStatusCard() {
    if (_planStatus == null) {
      return const SizedBox.shrink();
    }

    final isActive = _planStatus!['isActive'] ?? false;
    final isExpired = _planStatus!['isExpired'] ?? true;
    final daysRemaining = _planStatus!['daysRemaining'] ?? 0;
    final isFreeTrial = _planStatus!['isFreeTrial'] ?? false;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isActive) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      if (isFreeTrial) {
        statusText = 'Free Trial Active - $daysRemaining days remaining';
      } else {
        statusText = 'Plan Active - $daysRemaining days remaining';
      }
    } else if (isExpired) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Plan Expired - Please Subscribe';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = 'Plan Inactive - Please Subscribe';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? '✅ Plan Active' : '❌ Plan Expired',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 Plans Grid
  Widget _buildPlansGrid() {
    final plans = [
      {
        'title': '2 Days',
        'price': '₹199',
        'duration': '2 Days',
        'badge': 'QUICK',
        'planType': '2_days',
        'days': 2,
        'amount': 199,
        'features': [
          '✅ Access to all services',
          '✅ View service requests',
          '✅ Accept jobs',
          '✅ Chat with customers',
        ],
      },
      {
        'title': '5 Days',
        'price': '₹399',
        'duration': '5 Days',
        'badge': 'POPULAR',
        'planType': '5_days',
        'days': 5,
        'amount': 399,
        'features': [
          '✅ Access to all services',
          '✅ View service requests',
          '✅ Accept jobs',
          '✅ Chat with customers',
          '✅ Priority support',
        ],
      },
      {
        'title': '30 Days',
        'price': '₹1499',
        'duration': '30 Days',
        'badge': 'BEST VALUE',
        'planType': '30_days',
        'days': 30,
        'amount': 1499,
        'features': [
          '✅ Access to all services',
          '✅ View service requests',
          '✅ Accept jobs',
          '✅ Chat with customers',
          '✅ Priority support',
          '✅ Save 25%',
        ],
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        childAspectRatio: 0.9,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        final isPopular = index == 1;

        return _buildPlanCard(
          title: plan['title'] as String,
          price: plan['price'] as String,
          duration: plan['duration'] as String,
          badge: plan['badge'] as String,
          isPopular: isPopular,
          features: plan['features'] as List<String>,
          planType: plan['planType'] as String,
          days: plan['days'] as int,
          amount: plan['amount'] as int,
        );
      },
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String duration,
    required String badge,
    required bool isPopular,
    required List<String> features,
    required String planType,
    required int days,
    required int amount,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? const Color(0xFF42D7D7) : Colors.grey.shade200,
          width: isPopular ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? const Color(0xFF42D7D7).withOpacity(0.2)
                : Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge & Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C1B4D),
                  ),
                ),
                if (badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPopular
                          ? const Color(0xFFFF6B35)
                          : const Color(0xFF42D7D7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            // Price
            Row(
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C1B4D),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ $duration',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Features
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                feature,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF0C1B4D),
                ),
              ),
            )),

            const Spacer(),

            // Subscribe Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openWebPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPopular
                      ? const Color(0xFF42D7D7)
                      : const Color(0xFF0C1B4D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Subscribe Now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}