// Services/FirebaseMessageService.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:rxdart/rxdart.dart';
import '../model/MessageModel.dart';
import 'oneSignalNotificationService .dart';

class FirebaseMessageService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Send a message with proper bidirectional notifications
  Future<void> sendMessage({
    required String requestId,
    required String receiverId,
    required String receiverName,
    required String receiverRole, // 'customer' or 'technician'
    required String message,
    String? imageUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not logged in');

      // Get current user data
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final senderName = userData?['name'] ?? 'User';
      final senderRole = userData?['role'] ?? 'customer';

      print('📨 Sending message:');
      print('   From: $senderName ($senderRole)');
      print('   To: $receiverName ($receiverRole)');
      print('   Message: $message');

      // Generate conversation ID
      final conversationId = _getConversationId(
        requestId: requestId,
        customerId: senderRole == 'customer' ? currentUser.uid : receiverId,
        technicianId: senderRole == 'technician' ? currentUser.uid : receiverId,
      );

      // Create or update conversation
      await _updateConversation(
        conversationId: conversationId,
        requestId: requestId,
        customerId: senderRole == 'customer' ? currentUser.uid : receiverId,
        customerName: senderRole == 'customer' ? senderName : receiverName,
        technicianId: senderRole == 'technician' ? currentUser.uid : receiverId,
        technicianName: senderRole == 'technician' ? senderName : receiverName,
        lastMessage: message,
        serviceName: await _getServiceName(requestId),
        receiverId: receiverId,
        receiverRole: receiverRole,
      );

      // Add message to subcollection
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': senderName,
        'senderRole': senderRole,
        'receiverId': receiverId,
        'receiverName': receiverName,
        'receiverRole': receiverRole,
        'message': message,
        'messageType': imageUrl != null ? 'image' : 'text',
        'imageUrl': imageUrl,
        'isRead': false,
        'sentAt': FieldValue.serverTimestamp(),
        'requestId': requestId,
      });

      // Update unread count for receiver
      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      await conversationRef.update({
        'unreadCount': FieldValue.increment(1),
      });

      // ✅ SEND PUSH NOTIFICATION TO RECEIVER (Both ways)
      await _sendPushNotification(
        receiverId: receiverId,
        receiverRole: receiverRole,
        senderName: senderName,
        message: message,
        conversationId: conversationId,
        requestId: requestId,
      );

      // Send in-app notification
      await _sendInAppNotification(
        receiverId: receiverId,
        title: '💬 New Message from $senderName',
        body: message,
        conversationId: conversationId,
        requestId: requestId,
      );

      print('✅ Message sent and notification delivered');

    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // ✅ Send push notification to receiver (works for both customer and technician)
  Future<void> _sendPushNotification({
    required String receiverId,
    required String receiverRole,
    required String senderName,
    required String message,
    required String conversationId,
    required String requestId,
  }) async {
    try {
      // Get receiver's OneSignal ID
      final userDoc = await _firestore.collection('users').doc(receiverId).get();
      final oneSignalId = userDoc.data()?['oneSignalId'];

      if (oneSignalId == null || oneSignalId.isEmpty) {
        print('⚠️ No OneSignal ID for $receiverRole: $receiverId');
        print('💡 User needs to open app and enable notifications');
        return;
      }

      // Customize notification title based on receiver role
      String notificationTitle;
      if (receiverRole == 'technician') {
        notificationTitle = '🔧 New Message from Customer';
      } else {
        notificationTitle = '👤 New Message from Technician';
      }

      final result = await OneSignalNotificationService.sendNotificationToUser(
        userId: receiverId,
        title: notificationTitle,
        body: message.length > 100 ? '${message.substring(0, 100)}...' : message,
        data: {
          'type': 'new_message',
          'conversationId': conversationId,
          'requestId': requestId,
          'senderName': senderName,
          'senderRole': receiverRole == 'technician' ? 'customer' : 'technician',
        },
      );

      if (result) {
        print('✅ Push notification sent to $receiverRole: $receiverId');
      } else {
        print('❌ Failed to send push notification to $receiverRole');
      }
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }

  // Send in-app notification
  Future<void> _sendInAppNotification({
    required String receiverId,
    required String title,
    required String body,
    required String conversationId,
    required String requestId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': receiverId,
        'userRole': 'user',
        'title': title,
        'body': body,
        'type': 'message',
        'conversationId': conversationId,
        'requestId': requestId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending in-app notification: $e');
    }
  }

  // Update conversation
  Future<void> _updateConversation({
    required String conversationId,
    required String requestId,
    required String customerId,
    required String customerName,
    required String technicianId,
    required String technicianName,
    required String lastMessage,
    required String serviceName,
    required String receiverId,
    required String receiverRole,
  }) async {
    final conversationRef = _firestore.collection('conversations').doc(conversationId);
    final conversationDoc = await conversationRef.get();

    if (!conversationDoc.exists) {
      // Create new conversation
      await conversationRef.set({
        'requestId': requestId,
        'customerId': customerId,
        'customerName': customerName,
        'technicianId': technicianId,
        'technicianName': technicianName,
        'lastMessage': lastMessage,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 1,
        'serviceName': serviceName,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Update existing conversation
      await conversationRef.update({
        'lastMessage': lastMessage,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get messages for a conversation (real-time)
  Stream<List<MessageModel>> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Get conversations for current user (real-time)
  Stream<List<ConversationModel>> getUserConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    final customerConversations = _firestore
        .collection('conversations')
        .where('customerId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'active')
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConversationModel.fromMap(doc.data(), doc.id))
          .toList();
    });

    final technicianConversations = _firestore
        .collection('conversations')
        .where('technicianId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'active')
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ConversationModel.fromMap(doc.data(), doc.id))
          .toList();
    });

    return Rx.combineLatest2<List<ConversationModel>, List<ConversationModel>, List<ConversationModel>>(
      customerConversations,
      technicianConversations,
          (customerList, technicianList) {
        final all = [...customerList, ...technicianList];
        final uniqueMap = <String, ConversationModel>{};
        for (var conversation in all) {
          uniqueMap[conversation.id] = conversation;
        }
        final uniqueList = uniqueMap.values.toList();
        uniqueList.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        return uniqueList;
      },
    );
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messagesRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');

      final unreadMessages = await messagesRef
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();

      // Reset unread count in conversation
      await _firestore.collection('conversations').doc(conversationId).update({
        'unreadCount': 0,
      });
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Get unread message count for current user
  Stream<int> getUnreadMessageCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    return _firestore
        .collection('conversations')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['customerId'] == currentUser.uid || data['technicianId'] == currentUser.uid) {
          final unreadCount = data['unreadCount'];
          if (unreadCount != null) {
            if (unreadCount is int) {
              count += unreadCount;
            } else if (unreadCount is num) {
              count += unreadCount.toInt();
            }
          }
        }
      }
      return count;
    });
  }

  // Get or create conversation ID
  String _getConversationId({
    required String requestId,
    required String customerId,
    required String technicianId,
  }) {
    return '${requestId}_${customerId}_${technicianId}';
  }

  // Get service name from request ID
  Future<String> _getServiceName(String requestId) async {
    try {
      final doc = await _firestore.collection('service_requests').doc(requestId).get();
      if (doc.exists) {
        return doc.data()?['serviceName'] ?? 'Service Request';
      }
      return 'Service Request';
    } catch (e) {
      return 'Service Request';
    }
  }

  // Upload message image
  Future<String?> uploadMessageImage({
    required String conversationId,
    required String senderId,
    required File imageFile,
  }) async {
    try {
      final storage = FirebaseStorage.instance;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = storage.ref().child('messages/$conversationId/$senderId/$fileName');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // Set user online when app starts
  Future<void> setUserOnline() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore.collection('users').doc(currentUser.uid).update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  // Set user offline when app closes
  Future<void> setUserOffline() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore.collection('users').doc(currentUser.uid).update({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}