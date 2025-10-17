import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:ifenkem/providers/auth_provider.dart';
import 'package:ifenkem/screens/splash_screen.dart';
import 'firebase_options.dart';
import 'package:ifenkem/services/LocalNotificationService.dart';

/// ✅ Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ Top-level background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🟢 Background message received: ${message.data}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //  2. Ask for notification permission early (important)
  // final fcm = FirebaseMessaging.instance;
  // final settings = await fcm.requestPermission(
  //   alert: true,
  //   badge: true,
  //   sound: true,
  // );
  // debugPrint(
  //   '🟢 Notification permission status: ${settings.authorizationStatus}',
  // );

  // 3. Initialize Google Mobile Ads
  await MobileAds.instance.initialize();

  //  4. Register background FCM message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  //  5. Initialize local notifications
  await LocalNotificationService.initialize();

  //  6. Run the app with providers
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocalNotificationService()),
      ],
      child: const IfeNkemApp(),
    ),
  );
}

class IfeNkemApp extends StatelessWidget {
  const IfeNkemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IfeNkem',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFE91E63), // Pink
        scaffoldBackgroundColor: const Color(0xFFFFF8F8), // Soft cream white
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFFFFCDD2), // Light Pink
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC2185B), // Dark Pink
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:provider/provider.dart';
// import 'package:ifenkem/providers/auth_provider.dart';
// import 'package:ifenkem/screens/splash_screen.dart';
// import 'firebase_options.dart';
// import 'package:ifenkem/services/LocalNotificationService.dart';

// /// ✅ Global navigator key so LocalNotificationService can navigate
// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   // Initialize Firebase
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

//   // Request notification permission
//   if (await Permission.notification.isDenied) {
//     await Permission.notification.request();
//   }

//   // Initialize Google Mobile Ads
//   await MobileAds.instance.initialize();

//   // Initialize Local Notifications
//   await LocalNotificationService.initialize();

//   runApp(
//     MultiProvider(
//       providers: [
//         ChangeNotifierProvider(create: (_) => AuthProvider()),
//         ChangeNotifierProvider(create: (_) => LocalNotificationService()),
//       ],
//       child: const IfeNkemApp(),
//     ),
//   );
// }

// class IfeNkemApp extends StatelessWidget {
//   const IfeNkemApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       navigatorKey: navigatorKey,
//       title: 'IfeNkem',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         primaryColor: const Color(0xFFE91E63), // Pink
//         scaffoldBackgroundColor: const Color(0xFFFFF8F8), // Soft cream white
//         colorScheme: ColorScheme.fromSwatch().copyWith(
//           secondary: const Color(0xFFFFCDD2), // Light Pink
//         ),
//         elevatedButtonTheme: ElevatedButtonThemeData(
//           style: ElevatedButton.styleFrom(
//             backgroundColor: const Color(0xFFC2185B), // Dark Pink
//             foregroundColor: Colors.white,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//           ),
//         ),
//       ),
//       home: const SplashScreen(),
//     );
//   }
// }
