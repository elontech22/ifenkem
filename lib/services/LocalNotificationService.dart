import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import 'package:ifenkem/models/ChatMessageModel.dart';
import 'package:ifenkem/models/user_model.dart';
import 'package:ifenkem/services/ChatService.dart';
import 'package:ifenkem/screens/Chat_Screen.dart';
import 'package:ifenkem/screens/details_screen.dart';

class LocalNotificationService extends ChangeNotifier {
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  final ChatService _chatService = ChatService();
  StreamSubscription<ChatMessage?>? _subscription;
  final List<ChatMessage> _notifications = [];
  List<ChatMessage> get notifications => List.unmodifiable(_notifications);

  static final Map<String, List<ChatMessage>> _groupedMessages = {};
  static final Set<String> _shownMessageIds = {};

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'chat_channel',
    'Chat Messages',
    description: 'Channel for chat message notifications',
    importance: Importance.max,
  );

  /// ✅ Initialize Local Notifications & Firebase Messaging (safe)
  static Future<void> initialize() async {
    try {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: DarwinInitializationSettings(),
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse response) async {
              final payload = response.payload;
              if (payload == null) return;

              final parts = payload.split(':');
              if (parts.length == 2) {
                final type = parts[0];
                final id = parts[1];

                if (type == 'like') {
                  await _openUserProfileFromLike(id);
                } else if (type == 'chat') {
                  await _openChatFromUserId(id);
                }
              } else {
                await _openChatFromUserId(payload);
              }
            },
      );

      final messaging = FirebaseMessaging.instance;

      // Safe token retrieval
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final token = await messaging.getToken();
          if (token != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update({'fcmToken': token});
            debugPrint("🟢 FCM token stored for user $uid: $token");
          }
        }
      } catch (e) {
        debugPrint("⚠️ Failed to get FCM token: $e");
      }

      // Token refresh listener
      messaging.onTokenRefresh.listen((token) async {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update({'fcmToken': token});
            debugPrint("🟢 FCM token refreshed and stored: $token");
          }
        } catch (e) {
          debugPrint("⚠️ Failed to refresh FCM token: $e");
        }
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint("🟢 Foreground message: ${message.data}");
        switch (message.data['type']) {
          case 'like_notification':
            await _showFirebaseLikeNotification(message);
            break;
          case 'chat_message':
            await _showFirebaseChatNotification(message);
            break;
          case 'update_notification':
            await _showFirebaseUpdateNotification(message);
            break;
        }
      });

      // Background tap
      FirebaseMessaging.onMessageOpenedApp.listen((
        RemoteMessage message,
      ) async {
        final data = message.data;
        if (data['type'] == 'chat_message') {
          await _openChatFromUserId(data['senderId']);
        } else if (data['type'] == 'like_notification') {
          await _openUserProfileFromLike(data['likerId']);
        }
      });

      // Terminated state
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && initialMessage.data.isNotEmpty) {
        final data = initialMessage.data;
        if (data['type'] == 'chat_message') {
          await _openChatFromUserId(data['senderId']);
        } else if (data['type'] == 'like_notification') {
          await _openUserProfileFromLike(data['likerId']);
        }
      }
    } catch (e) {
      debugPrint("⚠️ LocalNotificationService initialization failed: $e");
    }
  }

  /// ✅ Open chat from userId
  static Future<void> _openChatFromUserId(String senderId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(senderId)
          .get();
      if (!userDoc.exists) return;

      final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

      bool isCurrentChat = false;
      navigatorKey.currentState?.popUntil((route) {
        if (route.settings.name == 'ChatScreen_${user.id}') {
          isCurrentChat = true;
        }
        return true;
      });

      if (!isCurrentChat) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(peerUser: user),
            settings: RouteSettings(name: 'ChatScreen_${user.id}'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error opening chat from FCM: $e");
    }
  }

  /// ✅ Open user profile from Like notification
  static Future<void> _openUserProfileFromLike(String likerId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(likerId)
          .get();
      if (!userDoc.exists) return;

      final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => DetailsScreen(user: user, fromLikeNotification: true),
          settings: const RouteSettings(name: 'DetailsScreenFromLike'),
        ),
      );
    } catch (e) {
      debugPrint("Error opening profile from like notification: $e");
    }
  }

  /// ✅ PUBLIC notification methods for background access
  static Future<void> showFirebaseLikeNotification(RemoteMessage message) =>
      _showFirebaseLikeNotification(message);

  static Future<void> showFirebaseChatNotification(RemoteMessage message) =>
      _showFirebaseChatNotification(message);

  static Future<void> showFirebaseUpdateNotification(RemoteMessage message) =>
      _showFirebaseUpdateNotification(message);

  /// PRIVATE methods that actually show notifications
  static Future<void> _showFirebaseLikeNotification(
    RemoteMessage message,
  ) async {
    final likerName = message.data['likerName'] ?? 'Someone';

    const androidDetails = AndroidNotificationDetails(
      'like_channel',
      'Likes',
      channelDescription: 'Notifications for profile likes',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      'New Like ❤️',
      '$likerName liked your profile!',
      details,
      // payload: message.data['likerId'],
      payload: 'like:${message.data['likerId']}',
    );
  }

  static Future<void> _showFirebaseChatNotification(
    RemoteMessage message,
  ) async {
    final senderName = message.data['senderName'] ?? 'Someone';
    final text = message.data['message'] ?? 'New message';

    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Messages',
      channelDescription: 'Channel for chat message notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      'Message from $senderName',
      text,
      details,
      // payload: message.data['senderId'],
      payload: 'chat:${message.data['senderId']}',
    );
  }

  static Future<void> _showFirebaseUpdateNotification(
    RemoteMessage message,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'update_channel',
      'App Updates',
      channelDescription: 'Channel for update notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      'Update Available 🚀',
      message.notification?.body ?? 'A new version is ready on Play Store!',
      details,
    );
  }

  /// ✅ Chat listener for in-app messages
  void startListening(String currentUserId) {
    if (_subscription != null) return;

    _subscription = _chatService.onNewMessage(currentUserId).listen((
      msg,
    ) async {
      if (msg == null || msg.senderId == currentUserId) return;

      if (msg.senderName == null || msg.senderName!.isEmpty) {
        try {
          final senderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(msg.senderId)
              .get();
          msg.senderName = senderDoc.exists
              ? senderDoc.get('name') ?? 'Someone'
              : 'Someone';
        } catch (_) {
          msg.senderName = 'Someone';
        }
      }

      if (msg.messageId == null || _shownMessageIds.contains(msg.messageId))
        return;
      _shownMessageIds.add(msg.messageId!);

      final senderId = msg.senderId;
      _groupedMessages.putIfAbsent(senderId, () => []);
      if (!_groupedMessages[senderId]!.any(
        (m) => m.messageId == msg.messageId,
      )) {
        _groupedMessages[senderId]!.insert(0, msg);
      }

      _notifications.insert(0, msg);
      notifyListeners();

      await _showNotification(msg);
    });
  }

  static Future<void> _showNotification(ChatMessage msg) async {
    final senderId = msg.senderId;
    final senderName = msg.senderName?.isNotEmpty == true
        ? msg.senderName
        : "Someone";

    final lines = _groupedMessages[senderId]!
        .map((m) => m.text)
        .take(5)
        .toList();

    final inboxStyle = InboxStyleInformation(
      lines,
      contentTitle: "New messages from $senderName",
      summaryText: "${_groupedMessages[senderId]!.length} messages",
    );

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: inboxStyle,
      playSound: true,
      enableVibration: true,
      ticker: 'New Message',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      senderId.hashCode,
      "Message from $senderName",
      msg.text,
      details,
      payload: senderId,
    );
  }

  void removeNotification(ChatMessage msg) {
    _notifications.removeWhere((n) => n.messageId == msg.messageId);
    if (msg.messageId != null) _shownMessageIds.remove(msg.messageId!);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}



// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';
// import 'package:ifenkem/models/user_model.dart';
// import 'package:ifenkem/services/ChatService.dart';
// import 'package:ifenkem/screens/Chat_Screen.dart';
// import 'package:ifenkem/screens/details_screen.dart';
// import '../main.dart';
// import 'package:firebase_auth/firebase_auth.dart';

// class LocalNotificationService extends ChangeNotifier {
//   static final FlutterLocalNotificationsPlugin
//   _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

//   final ChatService _chatService = ChatService();
//   StreamSubscription<ChatMessage?>? _subscription;

//   final List<ChatMessage> _notifications = [];
//   List<ChatMessage> get notifications => List.unmodifiable(_notifications);

//   static final Map<String, List<ChatMessage>> _groupedMessages = {};
//   static final Set<String> _shownMessageIds = {};

//   static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
//     'chat_channel',
//     'Chat Messages',
//     description: 'Channel for chat message notifications',
//     importance: Importance.max,
//   );

//   /// ✅ Initialize Local Notifications & Firebase Messaging
//   static Future<void> initialize() async {
//     await _flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//           AndroidFlutterLocalNotificationsPlugin
//         >()
//         ?.createNotificationChannel(_channel);

//     const androidSettings = AndroidInitializationSettings(
//       '@mipmap/ic_launcher',
//     );

//     const initSettings = InitializationSettings(
//       android: androidSettings,
//       iOS: DarwinInitializationSettings(),
//     );

//     await _flutterLocalNotificationsPlugin.initialize(
//       initSettings,
//       onDidReceiveNotificationResponse: (NotificationResponse response) async {
//         final senderId = response.payload;
//         if (senderId == null) return;
//         await _openChatFromUserId(senderId);
//       },
//     );

//     // ✅ Firebase Messaging
//     FirebaseMessaging messaging = FirebaseMessaging.instance;

//     // ✅ Get and update FCM token for current user
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid != null) {
//       final token = await messaging.getToken();
//       if (token != null) {
//         await FirebaseFirestore.instance.collection('users').doc(uid).update({
//           'fcmToken': token, // ✅ store token in Firestore
//         });
//         debugPrint("🟢 FCM token stored for user $uid: $token");
//       }
//     }

//     // ✅ Listen for token refresh
//     messaging.onTokenRefresh.listen((token) async {
//       final uid = FirebaseAuth.instance.currentUser?.uid;
//       if (uid != null) {
//         await FirebaseFirestore.instance.collection('users').doc(uid).update({
//           'fcmToken': token, // ✅ update token in Firestore
//         });
//         debugPrint("🟢 FCM token refreshed and stored: $token");
//       }
//     });

//     // ✅ Foreground messages
//     FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
//       debugPrint("🟢 Foreground message: ${message.data}");
//       switch (message.data['type']) {
//         case 'like_notification':
//           await _showFirebaseLikeNotification(message);
//           break;
//         case 'chat_message':
//           await _showFirebaseChatNotification(message);
//           break;
//         case 'update_notification':
//           await _showFirebaseUpdateNotification(message);
//           break;
//       }
//     });

//     // ✅ Background tap
//     FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
//       debugPrint("🟢 Notification opened from background: ${message.data}");
//       final data = message.data;
//       if (data['type'] == 'chat_message') {
//         await _openChatFromUserId(data['senderId']);
//       } else if (data['type'] == 'like_notification') {
//         await _openUserProfileFromLike(data['likedUserId']);
//       }
//     });

//     // ✅ App launched from terminated state
//     final initialMessage = await messaging.getInitialMessage();
//     if (initialMessage != null && initialMessage.data.isNotEmpty) {
//       final data = initialMessage.data;
//       if (data['type'] == 'chat_message') {
//         await _openChatFromUserId(data['senderId']);
//       } else if (data['type'] == 'like_notification') {
//         await _openUserProfileFromLike(data['likedUserId']);
//       }
//     }
//   }

//   /// ✅ Open chat from userId using updated UserModel
//   static Future<void> _openChatFromUserId(String senderId) async {
//     try {
//       final userDoc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(senderId)
//           .get();
//       if (!userDoc.exists) return;

//       final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//       bool isCurrentChat = false;
//       navigatorKey.currentState?.popUntil((route) {
//         if (route.settings.name == 'ChatScreen_${user.id}') {
//           isCurrentChat = true;
//         }
//         return true;
//       });

//       if (!isCurrentChat) {
//         navigatorKey.currentState?.push(
//           MaterialPageRoute(
//             builder: (_) => ChatScreen(peerUser: user),
//             settings: RouteSettings(name: 'ChatScreen_${user.id}'),
//           ),
//         );
//       }
//     } catch (e) {
//       debugPrint("Error opening chat from FCM: $e");
//     }
//   }

//   /// ✅ Open user profile from Like notification using UserModel
//   static Future<void> _openUserProfileFromLike(String likerId) async {
//     try {
//       final userDoc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(likerId)
//           .get();
//       if (!userDoc.exists) return;

//       final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//       navigatorKey.currentState?.push(
//         MaterialPageRoute(
//           builder: (_) => DetailsScreen(
//             user: user,
//             fromLikeNotification: true, // ✅ triggers blur later
//           ),
//           settings: const RouteSettings(name: 'DetailsScreenFromLike'),
//         ),
//       );
//     } catch (e) {
//       debugPrint("Error opening profile from like notification: $e");
//     }
//   }

//   /// ✅ Show “Like” Notification
//   static Future<void> _showFirebaseLikeNotification(
//     RemoteMessage message,
//   ) async {
//     final likerName = message.data['likerName'] ?? 'Someone';

//     const androidDetails = AndroidNotificationDetails(
//       'like_channel',
//       'Likes',
//       channelDescription: 'Notifications for profile likes',
//       importance: Importance.max,
//       priority: Priority.high,
//       playSound: true,
//     );

//     const details = NotificationDetails(
//       android: androidDetails,
//       iOS: DarwinNotificationDetails(),
//     );

//     await _flutterLocalNotificationsPlugin.show(
//       message.hashCode,
//       'New Like ❤️',
//       '$likerName liked your profile!',
//       details,
//       payload: message.data['likerId'],
//     );
//   }

//   /// ✅ Show “Chat” Notification
//   static Future<void> _showFirebaseChatNotification(
//     RemoteMessage message,
//   ) async {
//     final senderName = message.data['senderName'] ?? 'Someone';
//     final text = message.data['message'] ?? 'New message';

//     const androidDetails = AndroidNotificationDetails(
//       'chat_channel',
//       'Chat Messages',
//       channelDescription: 'Channel for chat message notifications',
//       importance: Importance.max,
//       priority: Priority.high,
//       playSound: true,
//     );

//     const details = NotificationDetails(
//       android: androidDetails,
//       iOS: DarwinNotificationDetails(),
//     );

//     await _flutterLocalNotificationsPlugin.show(
//       message.hashCode,
//       'Message from $senderName',
//       text,
//       details,
//       payload: message.data['senderId'],
//     );
//   }

//   /// ✅ Show “Update Available” Notification
//   static Future<void> _showFirebaseUpdateNotification(
//     RemoteMessage message,
//   ) async {
//     const androidDetails = AndroidNotificationDetails(
//       'update_channel',
//       'App Updates',
//       channelDescription: 'Channel for update notifications',
//       importance: Importance.max,
//       priority: Priority.high,
//       playSound: true,
//     );

//     const details = NotificationDetails(
//       android: androidDetails,
//       iOS: DarwinNotificationDetails(),
//     );

//     await _flutterLocalNotificationsPlugin.show(
//       message.hashCode,
//       'Update Available 🚀',
//       message.notification?.body ?? 'A new version is ready on Play Store!',
//       details,
//     );
//   }

//   // ✅ Existing chat listener logic remains unchanged
//   void startListening(String currentUserId) {
//     if (_subscription != null) return;

//     _subscription = _chatService.onNewMessage(currentUserId).listen((
//       msg,
//     ) async {
//       if (msg == null || msg.senderId == currentUserId) return;

//       if (msg.senderName == null || msg.senderName!.isEmpty) {
//         try {
//           final senderDoc = await FirebaseFirestore.instance
//               .collection('users')
//               .doc(msg.senderId)
//               .get();
//           msg.senderName = senderDoc.exists
//               ? senderDoc.get('name') ?? 'Someone'
//               : 'Someone';
//         } catch (_) {
//           msg.senderName = 'Someone';
//         }
//       }

//       if (msg.messageId == null || _shownMessageIds.contains(msg.messageId))
//         return;
//       _shownMessageIds.add(msg.messageId!);

//       final senderId = msg.senderId;
//       _groupedMessages.putIfAbsent(senderId, () => []);
//       if (!_groupedMessages[senderId]!.any(
//         (m) => m.messageId == msg.messageId,
//       )) {
//         _groupedMessages[senderId]!.insert(0, msg);
//       }

//       _notifications.insert(0, msg);
//       notifyListeners();

//       await _showNotification(msg);
//     });
//   }

//   static Future<void> _showNotification(ChatMessage msg) async {
//     final senderId = msg.senderId;
//     final senderName = msg.senderName?.isNotEmpty == true
//         ? msg.senderName
//         : "Someone";

//     final lines = _groupedMessages[senderId]!
//         .map((m) => m.text)
//         .take(5)
//         .toList();

//     final inboxStyle = InboxStyleInformation(
//       lines,
//       contentTitle: "New messages from $senderName",
//       summaryText: "${_groupedMessages[senderId]!.length} messages",
//     );

//     final androidDetails = AndroidNotificationDetails(
//       _channel.id,
//       _channel.name,
//       channelDescription: _channel.description,
//       importance: Importance.max,
//       priority: Priority.high,
//       styleInformation: inboxStyle,
//       playSound: true,
//       enableVibration: true,
//       ticker: 'New Message',
//     );

//     final details = NotificationDetails(
//       android: androidDetails,
//       iOS: const DarwinNotificationDetails(
//         presentAlert: true,
//         presentSound: true,
//         presentBadge: true,
//       ),
//     );

//     await _flutterLocalNotificationsPlugin.show(
//       senderId.hashCode,
//       "Message from $senderName",
//       msg.text,
//       details,
//       payload: senderId,
//     );
//   }

//   void removeNotification(ChatMessage msg) {
//     _notifications.removeWhere((n) => n.messageId == msg.messageId);
//     if (msg.messageId != null) _shownMessageIds.remove(msg.messageId!);
//     notifyListeners();
//   }

//   @override
//   void dispose() {
//     _subscription?.cancel();
//     super.dispose();
//   }
// }



// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';
// import 'package:ifenkem/services/ChatService.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:ifenkem/models/user_model.dart';
// import 'package:ifenkem/screens/Chat_Screen.dart';
// import '../main.dart';

// class LocalNotificationService extends ChangeNotifier {
//   static final FlutterLocalNotificationsPlugin
//   _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

//   final ChatService _chatService = ChatService();
//   StreamSubscription<ChatMessage?>? _subscription;

//   final List<ChatMessage> _notifications = [];
//   List<ChatMessage> get notifications => List.unmodifiable(_notifications);

//   static final Map<String, List<ChatMessage>> _groupedMessages = {};
//   static final Set<String> _shownMessageIds = {}; // track shown messages

//   /// Android notification channel
//   static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
//     'chat_channel',
//     'Chat Messages',
//     description: 'Channel for chat message notifications',
//     importance: Importance.max,
//   );

//   /// Initialize plugin
//   static Future<void> initialize() async {
//     await _flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//           AndroidFlutterLocalNotificationsPlugin
//         >()
//         ?.createNotificationChannel(_channel);

//     const AndroidInitializationSettings androidSettings =
//         AndroidInitializationSettings('@mipmap/ic_launcher');

//     const InitializationSettings initSettings = InitializationSettings(
//       android: androidSettings,
//       iOS: DarwinInitializationSettings(),
//     );

//     await _flutterLocalNotificationsPlugin.initialize(
//       initSettings,
//       onDidReceiveNotificationResponse: (NotificationResponse response) async {
//         final senderId = response.payload;
//         if (senderId == null) return;

//         try {
//           final userDoc = await FirebaseFirestore.instance
//               .collection('users')
//               .doc(senderId)
//               .get();
//           if (!userDoc.exists) return;

//           final user = UserModel.fromMap(
//             userDoc.data() as Map<String, dynamic>,
//             id: userDoc.id,
//           );

//           bool isCurrentChat = false;
//           navigatorKey.currentState?.popUntil((route) {
//             if (route.settings.name == 'ChatScreen_${user.id}') {
//               isCurrentChat = true;
//             }
//             return true;
//           });

//           if (!isCurrentChat) {
//             navigatorKey.currentState?.push(
//               MaterialPageRoute(
//                 builder: (_) => ChatScreen(peerUser: user),
//                 settings: RouteSettings(name: 'ChatScreen_${user.id}'),
//               ),
//             );
//           }
//         } catch (e) {
//           debugPrint("Error opening chat screen: $e");
//         }
//       },
//     );
//   }

//   /// Start listening to new messages for currentUserId
//   void startListening(String currentUserId) {
//     // Prevent multiple subscriptions
//     if (_subscription != null) return;

//     _subscription = _chatService.onNewMessage(currentUserId).listen((
//       msg,
//     ) async {
//       if (msg == null) return;
//       if (msg.senderId == currentUserId) return; // Ignore own messages

//       // Ensure senderName is fetched before notification
//       if (msg.senderName == null || msg.senderName!.isEmpty) {
//         try {
//           final senderDoc = await FirebaseFirestore.instance
//               .collection('users')
//               .doc(msg.senderId)
//               .get();
//           msg.senderName = senderDoc.exists
//               ? senderDoc.get('name') ?? 'Someone'
//               : 'Someone';
//         } catch (e) {
//           msg.senderName = 'Someone';
//         }
//       }

//       //  Prevent duplicate notifications
//       if (msg.messageId == null || _shownMessageIds.contains(msg.messageId))
//         return;
//       _shownMessageIds.add(msg.messageId!);

//       final senderId = msg.senderId;
//       _groupedMessages.putIfAbsent(senderId, () => []);
//       if (!_groupedMessages[senderId]!.any(
//         (m) => m.messageId == msg.messageId,
//       )) {
//         _groupedMessages[senderId]!.insert(0, msg);
//       }

//       _notifications.insert(0, msg);
//       notifyListeners();

//       await _showNotification(msg);
//     });
//   }

//   static Future<void> _showNotification(ChatMessage msg) async {
//     final senderId = msg.senderId;
//     final senderName = msg.senderName?.isNotEmpty == true
//         ? msg.senderName
//         : "Someone";

//     final List<String> lines = _groupedMessages[senderId]!
//         .map((m) => m.text)
//         .take(5)
//         .toList();

//     final inboxStyle = InboxStyleInformation(
//       lines,
//       contentTitle: "New messages from $senderName",
//       summaryText: "${_groupedMessages[senderId]!.length} messages",
//     );

//     final androidDetails = AndroidNotificationDetails(
//       _channel.id,
//       _channel.name,
//       channelDescription: _channel.description,
//       importance: Importance.max,
//       priority: Priority.high,
//       styleInformation: inboxStyle,
//       playSound: true,
//       enableVibration: true,
//       ticker: 'New Message',
//     );

//     final NotificationDetails details = NotificationDetails(
//       android: androidDetails,
//       iOS: const DarwinNotificationDetails(
//         presentAlert: true,
//         presentSound: true,
//         presentBadge: true,
//       ),
//     );

//     await _flutterLocalNotificationsPlugin.show(
//       senderId.hashCode, // Unique per sender
//       "Message from $senderName",
//       msg.text,
//       details,
//       payload: senderId,
//     );
//   }

//   void removeNotification(ChatMessage msg) {
//     _notifications.removeWhere((n) => n.messageId == msg.messageId);
//     if (msg.messageId != null) {
//       _shownMessageIds.remove(msg.messageId!); //  remove from shown IDs
//     }
//     notifyListeners();
//   }

//   @override
//   void dispose() {
//     _subscription?.cancel();
//     super.dispose();
//   }
// }




