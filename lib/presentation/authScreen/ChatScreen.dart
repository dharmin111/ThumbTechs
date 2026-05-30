// screens/ChatScreen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../Services/FirebaseMessageService.dart';
import '../../model/MessageModel.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String requestId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserRole;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.requestId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserRole,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseMessageService _messageService = FirebaseMessageService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;
  bool _isLoading = true;
  bool _isOtherUserOnline = false;
  DateTime? _otherUserLastSeen;
  Timer? _typingTimer;
  bool _isOtherUserTyping = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _listenToUserPresence();
    _listenToTypingStatus();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      await _createConversationIfNotExists();
      await _messageService.markMessagesAsRead(widget.conversationId);
    } catch (e) {
      print('Error initializing chat: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _listenToUserPresence() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _isOtherUserOnline = data['isOnline'] ?? false;
          _otherUserLastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
        });
      }
    });
  }

  void _listenToTypingStatus() {
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        final typingUserId = data['typingUserId'];
        setState(() {
          _isOtherUserTyping = typingUserId != null && typingUserId == widget.otherUserId;
        });
      }
    });
  }

  void _onTyping() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({
      'typingUserId': currentUser.uid,
      'typingAt': FieldValue.serverTimestamp(),
    });

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
        'typingUserId': null,
        'typingAt': null,
      });
    });
  }

  Future<void> _createConversationIfNotExists() async {
    try {
      final conversationRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);

      final conversationDoc = await conversationRef.get();

      if (!conversationDoc.exists) {
        final currentUser = FirebaseAuth.instance.currentUser!;

        // Get user name from Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final userName = userDoc.data()?['name'] ?? currentUser.displayName ?? 'User';

        final String customerId;
        final String customerName;
        final String technicianId;
        final String technicianName;

        if (widget.otherUserRole == 'customer') {
          customerId = widget.otherUserId;
          customerName = widget.otherUserName;
          technicianId = currentUser.uid;
          technicianName = userName;
        } else {
          customerId = currentUser.uid;
          customerName = userName;
          technicianId = widget.otherUserId;
          technicianName = widget.otherUserName;
        }

        await conversationRef.set({
          'conversationId': widget.conversationId,
          'requestId': widget.requestId,
          'customerId': customerId,
          'customerName': customerName,
          'technicianId': technicianId,
          'technicianName': technicianName,
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount': 0,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error creating conversation: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _createConversationIfNotExists();

      // Stop typing indicator
      _typingTimer?.cancel();
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({'typingUserId': null});

      await _messageService.sendMessage(
        requestId: widget.requestId,
        receiverId: widget.otherUserId,
        receiverName: widget.otherUserName,
        receiverRole: widget.otherUserRole,
        message: _messageController.text.trim(),
      );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _pickAndSendImage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF2563EB)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2563EB)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _isSending = true;
        });

        await _createConversationIfNotExists();

        final imageUrl = await _messageService.uploadMessageImage(
          conversationId: widget.conversationId,
          senderId: FirebaseAuth.instance.currentUser!.uid,
          imageFile: File(image.path),
        );

        if (imageUrl != null) {
          await _messageService.sendMessage(
            requestId: widget.requestId,
            receiverId: widget.otherUserId,
            receiverName: widget.otherUserName,
            receiverRole: widget.otherUserRole,
            message: '📷 Sent an image',
            imageUrl: imageUrl,
          );
        }

        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _getLastSeenText() {
    if (_isOtherUserOnline) {
      return 'Online';
    }
    if (_otherUserLastSeen != null) {
      final now = DateTime.now();
      final difference = now.difference(_otherUserLastSeen!);

      if (difference.inMinutes < 1) {
        return 'Active now';
      } else if (difference.inMinutes < 60) {
        return 'Active ${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return 'Active ${difference.inHours} hours ago';
      } else {
        return 'Last seen ${_otherUserLastSeen!.day}/${_otherUserLastSeen!.month}';
      }
    }
    return 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOtherUserOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _getLastSeenText(),
                  style: const TextStyle(fontSize: 10),
                ),
                if (_isOtherUserTyping) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'typing...',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _showRequestDetails(),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _messageService.getMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _initializeChat(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a message to start the conversation',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == currentUser.uid;
                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),
          if (_isOtherUserTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.otherUserName} is typing...',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe) {
    final isImage = message.messageType == 'image' && message.imageUrl != null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  message.senderName,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            Container(
              padding: isImage
                  ? const EdgeInsets.all(8)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF2563EB) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isImage)
                    GestureDetector(
                      onTap: () {
                        _showFullImage(message.imageUrl!);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          message.imageUrl!,
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey[200],
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, size: 50),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Text(
                      message.message,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.sentAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Read Receipts
                      if (isMe) ...[
                        if (message.isRead)
                          const Icon(Icons.done_all, size: 12, color: Colors.white70)
                        else
                          const Icon(Icons.done, size: 12, color: Colors.white70),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _isSending ? null : _pickAndSendImage,
            icon: Icon(
              Icons.photo,
              color: _isSending ? Colors.grey : const Color(0xFF2563EB),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _messageController,
                onChanged: (text) {
                  if (text.isNotEmpty) {
                    _onTyping();
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isSending,
              ),
            ),
          ),
          IconButton(
            onPressed: _isSending ? null : _sendMessage,
            icon: Icon(
              _isSending ? Icons.hourglass_empty : Icons.send,
              color: _isSending ? Colors.grey : const Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  void _showRequestDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(widget.requestId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(data['serviceName'] ?? 'Service Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Customer', data['userName'] ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Phone', data['userPhone'] ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Location', data['location'] ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Pincode', data['pincode'] ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Budget', '₹${data['budget'] ?? 0}'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Issue', data['issue'] ?? 'N/A'),
                  if (data['additionalNote'] != null && data['additionalNote'].isNotEmpty)
                    _buildDetailRow('Note', data['additionalNote']),
                  if (data['status'] != null)
                    _buildDetailRow('Status', data['status'].toString().toUpperCase()),
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
    } catch (e) {
      print('Error fetching request details: $e');
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${time.day}/${time.month}/${time.year}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}