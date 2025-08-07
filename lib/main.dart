import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'delivery_login_screen.dart';
import 'delivery_person_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _initializeFirebaseMessaging();

  runApp(const MyApp());
}

// Initialize Firebase Messaging
Future<void> _initializeFirebaseMessaging() async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get token and save it to Firestore
  String? token = await messaging.getToken();
  if (token != null) {
    await _saveFcmTokenToFirestore(token);
  }

  // Handle token refresh
  messaging.onTokenRefresh.listen((newToken) async {
    await _saveFcmTokenToFirestore(newToken);
  });

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    print('Foreground message received: ${message.messageId}');
    await _handleNotification(message);
  });

  // Handle when app is opened from terminated state
  RemoteMessage? initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    print('App opened from terminated state: ${initialMessage.messageId}');
    await _handleNotification(initialMessage);
  }

  // Handle when app is in background and opened from notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    print('App opened from background: ${message.messageId}');
    await _handleNotification(message);
  });
}

// Save FCM token to Firestore
Future<void> _saveFcmTokenToFirestore(String token) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('FCM token saved to Firestore');
  }
}

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');
  await _handleNotification(message);
}

// Handle notification
Future<void> _handleNotification(RemoteMessage message) async {
  final notification = message.notification;
  final data = message.data;

  if (notification != null) {
    print('Notification Title: ${notification.title}');
    print('Notification Body: ${notification.body}');
  }

  // Save notification to Firestore
  await FirebaseFirestore.instance.collection('notifications').add({
    'title': notification?.title ?? data['title'] ?? 'New Order',
    'body': notification?.body ?? data['body'] ?? 'You have a new delivery order',
    'createdAt': FieldValue.serverTimestamp(),
    'isRead': false,
    'type': data['type'] ?? 'order',
    'orderId': data['orderId'],
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talabak Express',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const RootScreen(),
      routes: {
        '/Delivery': (context) => const DeliveryPersonScreen(),
      },
    );
  }
}

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          return const DeliveryPersonScreen();
        } else {
          return LoginScreen();
        }
      },
    );
  }
}