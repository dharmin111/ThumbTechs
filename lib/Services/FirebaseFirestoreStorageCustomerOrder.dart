// Services/FirebaseFirestoreStorageCustomerOrder.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../model/ServiceRequestModel.dart';
import 'oneSignalNotificationService.dart';

class FirebaseFirestoreStorageCustomerOrder {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // ==================== IMAGE UPLOAD METHODS ====================

  /// Upload multiple images to Firebase Storage
  Future<List<String>> uploadServiceImages({
    required List<XFile> images,
    required String userId,
  }) async {
    List<String> imageUrls = [];

    for (int i = 0; i < images.length; i++) {
      try {
        final XFile image = images[i];
        final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final Reference storageRef = _storage.ref().child(
            'service_requests/$userId/$fileName'
        );

        await storageRef.putFile(File(image.path));
        final String downloadUrl = await storageRef.getDownloadURL();
        imageUrls.add(downloadUrl);

        print('✅ Image $i uploaded successfully');
      } catch (e) {
        print('❌ Error uploading image $i: $e');
        rethrow;
      }
    }

    return imageUrls;
  }

  // ==================== SERVICE REQUEST METHODS ====================

  /// Save service request with automatic technician matching and notifications
  Future<String> saveServiceRequestWithMatching({
    required ServiceRequestModel request,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Get complete user details
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      // Update request with user details
      final updatedRequest = request.copyWith(
        userId: user.uid,
        userEmail: user.email ?? '',
        userName: userData?['name'] ?? 'Customer',
        userPhone: userData?['phone'] ?? '',
      );

      // Save to Firestore
      final docRef = await _firestore.collection('service_requests').add(updatedRequest.toFirestore());
      final requestId = docRef.id;

      print('📝 Service request saved. ID: $requestId');

      // Send notifications to matching technicians
      await _sendNotificationsToMatchingTechnicians(requestId, updatedRequest);

      // Send confirmation to customer
      await _sendCustomerConfirmation(user.uid, requestId, updatedRequest);

      print('✅ Service request saved successfully. ID: $requestId');
      return requestId;

    } catch (e) {
      print('❌ Error saving service request: $e');
      rethrow;
    }
  }

  // ==================== NOTIFICATION METHODS ====================

  /// Send notifications to matching technicians using OneSignal
  Future<void> _sendNotificationsToMatchingTechnicians(
      String requestId,
      ServiceRequestModel request,
      ) async {
    try {
      print('📤 Sending notifications to matching technicians...');

      await OneSignalNotificationService.notifyMatchingTechnicians(
        serviceType: request.serviceType,
        pincode: request.pincode,
        requestId: requestId,
        serviceName: request.serviceName,
        customerName: request.userName,
      );

      print('✅ Notifications sent to matching technicians');
    } catch (e) {
      print('❌ Error sending notifications: $e');
    }
  }

  /// Send confirmation to customer
  Future<void> _sendCustomerConfirmation(
      String userId,
      String requestId,
      ServiceRequestModel request,
      ) async {
    try {
      await OneSignalNotificationService.sendRequestPostedNotification(
        customerId: userId,
        serviceName: request.serviceName,
        requestId: requestId,
      );

      print('✅ Customer confirmation sent');
    } catch (e) {
      print('❌ Error sending customer confirmation: $e');
    }
  }
// Services/FirebaseFirestoreStorageCustomerOrder.dart

  /// Re-post a rejected service request
  Future<String> rePostRequest({
    required String requestId,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final docRef = _firestore.collection('service_requests').doc(requestId);
      final doc = await docRef.get();

      if (!doc.exists) {
        throw Exception('Request not found');
      }

      final data = doc.data()!;

      // 🔥 Update request status back to pending
      await docRef.update({
        'status': 'pending',
        'technicianId': null,
        'technicianName': null,
        'technicianPhone': null,
        'rejectedAt': null,
        'repostedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'repostCount': FieldValue.increment(1),
      });

      // 🔥 Send notification to matching technicians again
      final request = ServiceRequestModel.fromFirestore(doc, null);
      await _sendNotificationsToMatchingTechnicians(requestId, request);

      // 🔥 Send confirmation to customer
      await _sendCustomerConfirmation(user.uid, requestId, request);

      print('✅ Request re-posted successfully: $requestId');
      return requestId;
    } catch (e) {
      print('❌ Error re-posting request: $e');
      rethrow;
    }
  }

  /// Permanently delete a request
  Future<void> permanentlyDeleteRequest(String requestId) async {
    try {
      await _firestore.collection('service_requests').doc(requestId).delete();
      print('✅ Request permanently deleted: $requestId');
    } catch (e) {
      print('❌ Error deleting request: $e');
      rethrow;
    }
  }

  /// Send notification when no technicians available
  Future<void> _sendNoTechniciansNotification(
      String userId,
      String requestId,
      ServiceRequestModel request,
      ) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'userRole': 'customer',
        'title': 'No Technicians Available',
        'body': 'Currently no technicians available in your area for ${request.serviceName}. We will notify you when someone is available.',
        'type': 'no_technicians',
        'requestId': requestId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error sending no technicians notification: $e');
    }
  }

  /// Accept service request by technician
  Future<void> acceptServiceRequest({
    required String requestId,
    required String technicianId,
    required String technicianName,
    required String technicianPhone,
    double? estimatedPrice,
    String? estimatedTime,
  }) async {
    try {
      final requestDoc = await _firestore.collection('service_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        throw Exception('Service request not found');
      }

      final requestData = requestDoc.data()!;

      // Update service request status
      await _firestore.collection('service_requests').doc(requestId).update({
        'technicianId': technicianId,
        'technicianName': technicianName,
        'technicianPhone': technicianPhone,
        'estimatedPrice': estimatedPrice,
        'estimatedTime': estimatedTime,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Remove from technician's pending requests
      final pendingDoc = await _firestore
          .collection('technician_pending_requests')
          .doc('${technicianId}_$requestId')
          .get();

      if (pendingDoc.exists) {
        await pendingDoc.reference.delete();
      }

      // 🔥 Send notification to customer using OneSignal
      await OneSignalNotificationService.sendNotificationToUser(
        userId: requestData['userId'],
        title: '🎉 Service Request Accepted!',
        body: 'Your request has been accepted by $technicianName. They will contact you soon.',
        data: {
          'type': 'request_accepted',
          'requestId': requestId,
          'technicianId': technicianId,
          'technicianName': technicianName,
          'technicianPhone': technicianPhone,
          'estimatedPrice': estimatedPrice,
        },
      );

      // 🔥 Send confirmation to technician using OneSignal
      await OneSignalNotificationService.sendNotificationToUser(
        userId: technicianId,
        title: '✅ Request Accepted!',
        body: 'You have accepted the service request from ${requestData['userName']}.',
        data: {
          'type': 'offer_accepted',
          'requestId': requestId,
          'customerName': requestData['userName'],
          'customerPhone': requestData['userPhone'],
        },
      );

      print('✅ Technician $technicianName accepted request $requestId');

    } catch (e) {
      print('❌ Error accepting request: $e');
      rethrow;
    }
  }

  /// Update service request status
  Future<void> updateServiceRequestStatus({
    required String requestId,
    required String status,
    String? cancellationReason,
  }) async {
    try {
      final updates = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (cancellationReason != null) {
        updates['cancellationReason'] = cancellationReason;
      }

      if (status == 'completed') {
        updates['completedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore.collection('service_requests').doc(requestId).update(updates);
      print('✅ Service request $requestId status updated to $status');

    } catch (e) {
      print('❌ Error updating status: $e');
      rethrow;
    }
  }

  /// Get all service requests for current user
  Stream<List<ServiceRequestModel>> getUserServiceRequests() {
    final user = currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('service_requests')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ServiceRequestModel.fromFirestore(doc, null))
          .toList();
    });
  }

  /// Get service request by ID
  Future<ServiceRequestModel?> getServiceRequestById(String requestId) async {
    try {
      final doc = await _firestore.collection('service_requests').doc(requestId).get();
      if (doc.exists) {
        return ServiceRequestModel.fromFirestore(doc, null);
      }
      return null;
    } catch (e) {
      print('❌ Error getting service request: $e');
      return null;
    }
  }

  // ==================== HELPER METHODS ====================

  bool isUserLoggedIn() {
    return currentUser != null;
  }

  String? getCurrentUserId() {
    return currentUser?.uid;
  }

  String? getCurrentUserEmail() {
    return currentUser?.email;
  }

  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.data();
    } catch (e) {
      print('❌ Error getting user data: $e');
      return null;
    }
  }
}