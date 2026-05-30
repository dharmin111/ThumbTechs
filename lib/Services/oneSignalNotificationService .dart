import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;

class OneSignalNotificationService {
  static bool _isInitialized = false;
  static const String _oneSignalAppId = '36709973-f516-4746-a694-c58ad52a532d';
  // static const String _oneSignalAppId = '3966b6b9-330c-492c-aa2b-a88e88b07a6d';

  static const String _oneSignalApiKey ='os_v2_app_hftlnojtbreszkrlvchirmd2nvblg5qnfz6uqpe6pikonxnqvz2vezj3vdaiqew4fq3se6f4mxmqqeku2tcoxe63rotdaiylbzdvquy';

  // ================= INIT =================
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      OneSignal.initialize(_oneSignalAppId);

      await OneSignal.Notifications.requestPermission(true);

      _isInitialized = true;
      print('✅ OneSignal initialized');

      // CLICK LISTENER
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData ?? {};
        print('📱 Notification Clicked: $data');
      });

      // FOREGROUND LISTENER (FIXED)
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        print('📨 Foreground Notification: ${event.notification.additionalData}');

        event.notification.display(); // MUST call this in v5
      });
    } catch (e) {
      print('❌ OneSignal init error: $e');
    }
  }

  // ================= GET ID =================
  static String? getOneSignalId() {
    try {
      return OneSignal.User.pushSubscription.id;
    } catch (e) {
      print('❌ Error getting OneSignal ID: $e');
      return null;
    }
  }

// Services/OneSignalNotificationService.dart

// Replace the saveOneSignalId method with this:
  static Future<bool> saveOneSignalId({
    required String userId,
    required String userRole,
  }) async {
    try {
      print('📱 Saving OneSignal ID for user: $userId (Role: $userRole)');

      // Wait for OneSignal ID to be available (up to 5 seconds)
      String? oneSignalId;
      for (int i = 0; i < 10; i++) {
        oneSignalId = OneSignal.User.pushSubscription.id;
        if (oneSignalId != null && oneSignalId.isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (oneSignalId == null || oneSignalId.isEmpty) {
        print('❌ OneSignal ID not ready yet');
        return false;
      }

      // Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'oneSignalId': oneSignalId,
        'userRole': userRole,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ OneSignal ID saved: $oneSignalId');
      return true;
    } catch (e) {
      print('❌ Save ID error: $e');
      return false;
    }
  }
// Services/OneSignalNotificationService.dart

// Add this method inside the OneSignalNotificationService class
  static Future<void> saveCurrentUserOneSignalId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ No user logged in');
      return;
    }

    // Get OneSignal ID from device (wait up to 5 seconds)
    String? oneSignalId;
    for (int i = 0; i < 10; i++) {
      oneSignalId = OneSignal.User.pushSubscription.id;
      if (oneSignalId != null && oneSignalId.isNotEmpty) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (oneSignalId == null || oneSignalId.isEmpty) {
      print('❌ OneSignal ID not available');
      return;
    }

    // Update Firestore for the current user
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'oneSignalId': oneSignalId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print('✅ OneSignal ID saved for user: ${user.uid}');
    print('📱 OneSignal ID: $oneSignalId');
  }
  // ================= SEND NOTIFICATION =================
  static Future<bool> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) {
        print('❌ User not found');
        return false;
      }

      final oneSignalId = doc.data()?['oneSignalId'];

      if (oneSignalId == null || oneSignalId.toString().isEmpty) {
        print('❌ No OneSignal ID');
        return false;
      }

      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_oneSignalApiKey',
        },
        body: jsonEncode({
          'app_id': _oneSignalAppId,
          'include_player_ids': [oneSignalId],
          'headings': {'en': title},
          'contents': {'en': body},
          'data': data,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Notification sent');

        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': userId,
          'title': title,
          'body': body,
          'type': data['type'],
          'data': data,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        return true;
      } else {
        print('❌ Failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Send error: $e');
      return false;
    }
  }

  // ================= BULK SEND =================
  static Future<Map<String, bool>> sendNotificationToMultipleUsers({
    required List<String> userIds,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final results = <String, bool>{};

    for (final id in userIds) {
      results[id] = await sendNotificationToUser(
        userId: id,
        title: title,
        body: body,
        data: data,
      );
    }

    return results;
  }
// ================= MATCH TECHNICIANS (WITH MULTIPLE PINCODES) =================
  static Future<void> notifyMatchingTechnicians({
    required String serviceType,
    required String pincode,  // Customer's pincode
    required String requestId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      print('🔍 Looking for technicians:');
      print('   Service: $serviceType');
      print('   Customer Pincode: $pincode');

      final techs = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'technician')
          .get();

      print('📊 Total technicians: ${techs.docs.length}');

      int matchedCount = 0;
      int sentCount = 0;

      for (final doc in techs.docs) {
        final d = doc.data();

        // Get categories
        final categories = List<String>.from(d['categories'] ?? []);

        // ✅ GET MULTIPLE PINCODES
        List<String> technicianPincodes = [];

        // Check for pincodes array first
        if (d['pincodes'] != null && (d['pincodes'] as List).isNotEmpty) {
          technicianPincodes = List<String>.from(d['pincodes']);
        }
        // Fallback to single pincode for backward compatibility
        else if (d['pincode'] != null && d['pincode'].toString().isNotEmpty) {
          technicianPincodes = [d['pincode'].toString()];
        }

        // ✅ Check if category matches AND customer pincode is in technician's pincodes
        final categoryMatches = categories.contains(serviceType);
        final pincodeMatches = technicianPincodes.contains(pincode);

        if (categoryMatches && pincodeMatches) {
          matchedCount++;
          final technicianName = d['name'] ?? 'Technician';

          print('✅ MATCH: $technicianName');
          print('   Serves pincodes: ${technicianPincodes.join(", ")}');
          print('   Categories: ${categories.join(", ")}');

          final success = await sendNotificationToUser(
            userId: doc.id,
            title: title,
            body: body,
            data: {
              ...data,
              'type': 'new_request',
              'requestId': requestId,
              'customerPincode': pincode,
            },
          );

          if (success) {
            sentCount++;

            // Save to pending requests
            await FirebaseFirestore.instance
                .collection('technician_pending_requests')
                .doc('${doc.id}_$requestId')
                .set({
              'technicianId': doc.id,
              'technicianName': technicianName,
              'requestId': requestId,
              'serviceName': data['serviceName'],
              'customerName': data['customerName'],
              'customerPincode': pincode,
              'createdAt': FieldValue.serverTimestamp(),
              'status': 'pending',
            });
          }
        }
      }

      print('📊 Results: Matched=$matchedCount, Notifications Sent=$sentCount');

    } catch (e) {
      print('❌ Matching error: $e');
    }
  }

  // ================= MESSAGE NOTIFICATION =================
  static Future<bool> sendMessageNotification({
    required String receiverId,
    required String senderName,
    required String message,
    required String conversationId,
    required String requestId,
  }) async {
    return sendNotificationToUser(
      userId: receiverId,
      title: '💬 New Message from $senderName',
      body: message.length > 100
          ? '${message.substring(0, 100)}...'
          : message,
      data: {
        'type': 'new_message',
        'conversationId': conversationId,
        'requestId': requestId,
        'senderName': senderName,
      },
    );
  }

  // ================= REMOVE ID =================
  static Future<void> removeOneSignalId(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'oneSignalId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}