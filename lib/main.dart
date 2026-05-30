import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'Services/oneSignalNotificationService .dart';
import 'firebase_options.dart';
import 'presentation/authScreen/splashScreen.dart';
import 'presentation/CostomerScreens/ServiceDetailScreen.dart';
import 'presentation/authScreen/ChatScreen.dart';
import 'presentation/CostomerScreens/BookingScreen.dart';
import 'presentation/DashBoard/CustomerDashboard.dart';
import 'presentation/DashBoard/TechnicianDashboard.dart';
import 'presentation/authScreen/LoginScreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ================= FIREBASE =================
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ================= ONESIGNAL v5 =================
  OneSignal.initialize("3966b6b9-330c-492c-aa2b-a88e88b07a6d");
  await OneSignalNotificationService.initialize();
  // Request permission
  OneSignal.Notifications.requestPermission(true);

  print("✅ OneSignal Initialized");

  // ================= USER ID (OPTIONAL LINK WITH FIREBASE) =================
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    OneSignal.login(user.uid); // replaces setExternalUserId
  }

  // ================= NOTIFICATION CLICK HANDLER =================
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData ?? {};

    print('📱 Notification clicked: $data');

    _handleNotificationTap(Map<String, dynamic>.from(data));
  });

  runApp(const MyApp());
}

// ================= HANDLE NAVIGATION =================
void _handleNotificationTap(Map<String, dynamic> data) {
  String type = data['type'] ?? '';

  if (type == 'new_request') {
    navigatorKey.currentState?.pushNamed(
      '/service-details',
      arguments: {
        'serviceName': data['serviceName'] ?? 'Service Request',
      },
    );
  }

  else if (type == 'new_message') {
    navigatorKey.currentState?.pushNamed(
      '/chat',
      arguments: {
        'conversationId': data['conversationId'],
        'requestId': data['requestId'],
        'otherUserId': data['senderId'] ?? '',
        'otherUserName': data['senderName'] ?? 'User',
        'otherUserRole': data['senderRole'] ?? 'customer',
      },
    );
  }

  else if (type == 'request_accepted') {
    navigatorKey.currentState?.pushNamed('/my-bookings');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'Thumb Tech',

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42D7D7),
          primary: const Color(0xFF42D7D7),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),

      initialRoute: '/',

      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/customer-dashboard': (context) => const CustomerDashboard(),
        '/technician-dashboard': (context) => const TechnicianDashboard(),

        '/service-details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
          as Map<String, dynamic>;
          return ServiceDetailScreen(
            serviceName: args['serviceName'] ?? '',
          );
        },

        '/chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
          as Map<String, dynamic>;
          return ChatScreen(
            conversationId: args['conversationId'],
            requestId: args['requestId'],
            otherUserId: args['otherUserId'],
            otherUserName: args['otherUserName'],
            otherUserRole: args['otherUserRole'],
          );
        },

        '/my-bookings': (context) => const BookingScreen(),
      },
    );
  }
}