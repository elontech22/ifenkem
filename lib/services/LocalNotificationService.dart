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
import 'package:url_launcher/url_launcher.dart';

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

  static final AndroidNotificationChannel _updateChannel =
      AndroidNotificationChannel(
        'update_channel',
        'App Updates',
        description: 'Channel for update notifications',
        importance: Importance.max,
      );

  /// ✅ Initialize Local Notifications & Firebase Messaging
  static Future<void> initialize() async {
    try {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_updateChannel);

      // 🔴 ADDED: Like Notification Channel (for profile likes)
      const AndroidNotificationChannel
      _likeChannel = AndroidNotificationChannel(
        'like_channel', // Channel ID must match the one used in notification
        'Likes',
        description: 'Notifications for profile likes',
        importance: Importance.max,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_likeChannel);
      // 🔴 END OF ADDITION

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: DarwinInitializationSettings(),
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          try {
            final payload = response.payload;
            if (payload == null) return;

            // ✅ FIX: Safe payload split
            final parts = payload.contains(':')
                ? payload.split(':')
                : [payload];
            final type = parts[0];
            final id = parts.length > 1 ? parts[1] : null;

            if (type == 'like' && id != null) {
              await _openUserProfileFromLike(id);
            } else if (type == 'chat' && id != null) {
              await _openChatFromUserId(id);
            } else if (payload == 'update_notification') {
              await launchUrl(
                Uri.parse(
                  "https://play.google.com/store/apps/details?id=com.elontechnology.ifenkem",
                ),
              );
            } else if (id != null) {
              await _openChatFromUserId(id);
            }
          } catch (e) {
            debugPrint("⚠️ Failed handling notification tap: $e");
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

      // ✅ Foreground messages with null checks
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        try {
          final type = message.data['type'] ?? '';
          switch (type) {
            case 'like_notification':
              if (message.data['likerId'] != null) {
                await _showFirebaseLikeNotification(message); // ✅
              }
              break;
            case 'chat_message':
              if (message.data['senderId'] != null) {
                await _showFirebaseChatNotification(message); // ✅
              }
              break;
            case 'update_notification':
              await _showFirebaseUpdateNotification(message);
              break;
            default:
              debugPrint("⚠️ Unknown message type or missing ID: $type"); // ✅
          }
        } catch (e) {
          debugPrint("⚠️ Failed to handle foreground message: $e");
        }
      });

      // ✅ Background tap
      FirebaseMessaging.onMessageOpenedApp.listen((
        RemoteMessage message,
      ) async {
        try {
          final type = message.data['type'] ?? '';
          if (type == 'chat_message' && message.data['senderId'] != null) {
            await _openChatFromUserId(message.data['senderId']);
          } else if (type == 'like_notification' &&
              message.data['likerId'] != null) {
            await _openUserProfileFromLike(message.data['likerId']);
          }
        } catch (e) {
          debugPrint("⚠️ Failed to handle background tap: $e");
        }
      });

      // ✅ Terminated state
      try {
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null && initialMessage.data.isNotEmpty) {
          final type = initialMessage.data['type'] ?? '';
          if (type == 'chat_message' &&
              initialMessage.data['senderId'] != null) {
            await _openChatFromUserId(initialMessage.data['senderId']);
          } else if (type == 'like_notification' &&
              initialMessage.data['likerId'] != null) {
            await _openUserProfileFromLike(initialMessage.data['likerId']);
          }
        }
      } catch (e) {
        debugPrint("⚠️ Failed to handle terminated message: $e");
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

      // ✅ Delay to ensure navigator is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        final nav = navigatorKey.currentState;
        if (nav == null) {
          debugPrint("⚠️ Navigator not ready, skipping navigation."); // ✅
          return;
        }

        bool isCurrentChat = false;
        nav.popUntil((route) {
          if (route.settings.name == 'ChatScreen_${user.id}') {
            isCurrentChat = true;
          }
          return true;
        });

        if (!isCurrentChat) {
          try {
            nav.push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUser: user),
                settings: RouteSettings(name: 'ChatScreen_${user.id}'),
              ),
            );
          } catch (e) {
            debugPrint("⚠️ Failed to push chat screen: $e");
          }
        }
      });
    } catch (e) {
      debugPrint("⚠️ Error opening chat from FCM: $e");
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

      Future.delayed(const Duration(milliseconds: 500), () {
        final nav = navigatorKey.currentState;
        if (nav == null) {
          debugPrint("⚠️ Navigator not ready, skipping navigation."); // ✅
          return;
        }

        try {
          nav.push(
            MaterialPageRoute(
              builder: (_) =>
                  DetailsScreen(user: user, fromLikeNotification: true),
              settings: const RouteSettings(name: 'DetailsScreenFromLike'),
            ),
          );
        } catch (e) {
          debugPrint("⚠️ Failed to push DetailsScreen: $e");
        }
      });
    } catch (e) {
      debugPrint("⚠️ Error opening profile from like notification: $e");
    }
  }

  /// --- Show Firebase Chat Notification --- ✅ Prevent crash if null
  static Future<void> _showFirebaseChatNotification(
    RemoteMessage message,
  ) async {
    try {
      final senderId = message.data['senderId'];
      final senderName = message.data['senderName'] ?? 'Someone';
      final text = message.data['message'] ?? 'New message';

      if (senderId == null) return; // ✅ Prevent crash

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
        senderId.hashCode,
        'Message from $senderName',
        text,
        details,
        payload: 'chat:$senderId',
      );
    } catch (e) {
      debugPrint("⚠️ Failed to show chat notification: $e");
    }
  }

  /// --- Show Firebase Like Notification --- ✅ Prevent crash if null
  static Future<void> _showFirebaseLikeNotification(
    RemoteMessage message,
  ) async {
    try {
      final likerId = message.data['likerId'];
      final likerName = message.data['likerName'] ?? 'Someone';

      if (likerId == null) return; // ✅ Prevent crash

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
        payload: 'like:$likerId',
      );
    } catch (e) {
      debugPrint("⚠️ Failed to show like notification: $e");
    }
  }

  /// --- Show Firebase Update Notification ---
  static Future<void> _showFirebaseUpdateNotification(
    RemoteMessage message,
  ) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _updateChannel.id,
        _updateChannel.name,
        channelDescription: _updateChannel.description,
        importance: _updateChannel.importance,
        priority: Priority.high,
        playSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

      final body =
          message.notification?.body ??
          message.data['body'] ??
          'A new version is ready on Play Store!';

      await _flutterLocalNotificationsPlugin.show(
        0,
        'IfeNkem Update Available 🚀',
        body,
        details,
        payload: 'update_notification',
      );
    } catch (e) {
      debugPrint("⚠️ Failed to show update notification: $e");
    }
  }

  /// ✅ Chat listener for in-app messages
  void startListening(String currentUserId) {
    if (_subscription != null) return;

    _subscription = _chatService.onNewMessage(currentUserId).listen((
      msg,
    ) async {
      try {
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

        try {
          await _showNotification(msg);
        } catch (e) {
          debugPrint("⚠️ Failed to show in-app notification: $e");
        }
      } catch (e) {
        debugPrint("⚠️ Error in chat listener: $e");
      }
    });
  }

  static Future<void> _showNotification(ChatMessage msg) async {
    try {
      final String? senderId = msg.senderId;
      if (senderId == null || senderId.isEmpty) {
        debugPrint("⚠️ Missing senderId in message, skipping notification.");
        return;
      }

      final senderName = (msg.senderName != null && msg.senderName!.isNotEmpty)
          ? msg.senderName!
          : "Someone";

      final lines = (_groupedMessages[senderId] ?? [])
          .map((m) => m.text)
          .take(5)
          .toList();

      final inboxStyle = InboxStyleInformation(
        lines,
        contentTitle: "New messages from $senderName",
        summaryText: "${lines.length} messages",
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
        msg.text ?? '',
        details,
        payload: 'chat:$senderId',
      );
    } catch (e) {
      debugPrint("⚠️ Failed to show grouped notification: $e");
    }
  }

  void removeNotification(ChatMessage msg) {
    try {
      _notifications.removeWhere((n) => n.messageId == msg.messageId);
      if (msg.messageId != null) _shownMessageIds.remove(msg.messageId!);
      notifyListeners();
    } catch (e) {
      debugPrint("⚠️ Failed to remove notification: $e");
    }
  }

  @override
  void dispose() {
    try {
      _subscription?.cancel();
    } catch (e) {
      debugPrint("⚠️ Failed to cancel subscription: $e");
    }
    super.dispose();
  }
}



// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import '../main.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';
// import 'package:ifenkem/models/user_model.dart';
// import 'package:ifenkem/services/ChatService.dart';
// import 'package:ifenkem/screens/Chat_Screen.dart';
// import 'package:ifenkem/screens/details_screen.dart';
// import 'package:url_launcher/url_launcher.dart';

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
//   // 🟢 Update notification channel (class-level static)
//   static final AndroidNotificationChannel _updateChannel =
//       AndroidNotificationChannel(
//         'update_channel',
//         'App Updates',
//         description: 'Channel for update notifications',
//         importance: Importance.max,
//       );

//   /// ✅ Initialize Local Notifications & Firebase Messaging (safe)
//   static Future<void> initialize() async {
//     try {
//       // Setup notification channel
//       await _flutterLocalNotificationsPlugin
//           .resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin
//           >()
//           ?.createNotificationChannel(_channel);

//       // Setup update channel
//       await _flutterLocalNotificationsPlugin
//           .resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin
//           >()
//           ?.createNotificationChannel(_updateChannel);
//       const androidSettings = AndroidInitializationSettings(
//         '@mipmap/ic_launcher',
//       );
//       const initSettings = InitializationSettings(
//         android: androidSettings,
//         iOS: DarwinInitializationSettings(),
//       );

//       await _flutterLocalNotificationsPlugin.initialize(
//         initSettings,
//         onDidReceiveNotificationResponse: (NotificationResponse response) async {
//           try {
//             final payload = response.payload;
//             if (payload == null) return;

//             final parts = payload.split(':');
//             if (parts.length == 2) {
//               final type = parts[0];
//               final id = parts[1];

//               if (type == 'like') {
//                 await _openUserProfileFromLike(id);
//               } else if (type == 'chat') {
//                 await _openChatFromUserId(id);
//               }
//             } else if (payload == 'update_notification') {
//               // ✅ Handle update tap
//               // Use url_launcher to open Play Store
//               await launchUrl(
//                 Uri.parse(
//                   "https://play.google.com/store/apps/details?id=com.elontechnology.ifenkem",
//                 ),
//               );
//             } else {
//               await _openChatFromUserId(payload);
//             }
//           } catch (e) {
//             debugPrint("⚠️ Failed handling notification tap: $e");
//           }
//         },
//       );

//       final messaging = FirebaseMessaging.instance;

//       // Safe token retrieval
//       try {
//         final uid = FirebaseAuth.instance.currentUser?.uid;
//         if (uid != null) {
//           final token = await messaging.getToken();
//           if (token != null) {
//             await FirebaseFirestore.instance
//                 .collection('users')
//                 .doc(uid)
//                 .update({'fcmToken': token});
//             debugPrint("🟢 FCM token stored for user $uid: $token");
//           }
//         }
//       } catch (e) {
//         debugPrint("⚠️ Failed to get FCM token: $e");
//       }

//       // Token refresh listener
//       messaging.onTokenRefresh.listen((token) async {
//         try {
//           final uid = FirebaseAuth.instance.currentUser?.uid;
//           if (uid != null) {
//             await FirebaseFirestore.instance
//                 .collection('users')
//                 .doc(uid)
//                 .update({'fcmToken': token});
//             debugPrint("🟢 FCM token refreshed and stored: $token");
//           }
//         } catch (e) {
//           debugPrint("⚠️ Failed to refresh FCM token: $e");
//         }
//       });

//       // Foreground messages
//       FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
//         try {
//           debugPrint("🟢 Foreground message: ${message.data}");
//           switch (message.data['type']) {
//             case 'like_notification':
//               await _showFirebaseLikeNotification(message);
//               break;
//             case 'chat_message':
//               await _showFirebaseChatNotification(message);
//               break;
//             case 'update_notification':
//               await _showFirebaseUpdateNotification(message);
//               break;
//           }
//         } catch (e) {
//           debugPrint("⚠️ Failed to handle foreground message: $e");
//         }
//       });

//       // Background tap
//       FirebaseMessaging.onMessageOpenedApp.listen((
//         RemoteMessage message,
//       ) async {
//         try {
//           final data = message.data;
//           if (data['type'] == 'chat_message') {
//             await _openChatFromUserId(data['senderId']);
//           } else if (data['type'] == 'like_notification') {
//             await _openUserProfileFromLike(data['likerId']);
//           }
//         } catch (e) {
//           debugPrint("⚠️ Failed to handle background tap: $e");
//         }
//       });

//       // Terminated state
//       try {
//         final initialMessage = await messaging.getInitialMessage();
//         if (initialMessage != null && initialMessage.data.isNotEmpty) {
//           final data = initialMessage.data;
//           if (data['type'] == 'chat_message') {
//             await _openChatFromUserId(data['senderId']);
//           } else if (data['type'] == 'like_notification') {
//             await _openUserProfileFromLike(data['likerId']);
//           }
//         }
//       } catch (e) {
//         debugPrint("⚠️ Failed to handle terminated message: $e");
//       }
//     } catch (e) {
//       debugPrint("⚠️ LocalNotificationService initialization failed: $e");
//     }
//   }

//   /// ✅ Open chat from userId
//   // static Future<void> _openChatFromUserId(String senderId) async {
//   //   try {
//   //     final userDoc = await FirebaseFirestore.instance
//   //         .collection('users')
//   //         .doc(senderId)
//   //         .get();
//   //     if (!userDoc.exists) return;

//   //     final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//   //     bool isCurrentChat = false;
//   //     navigatorKey.currentState?.popUntil((route) {
//   //       if (route.settings.name == 'ChatScreen_${user.id}') {
//   //         isCurrentChat = true;
//   //       }
//   //       return true;
//   //     });

//   //     if (!isCurrentChat) {
//   //       try {
//   //         navigatorKey.currentState?.push(
//   //           MaterialPageRoute(
//   //             builder: (_) => ChatScreen(peerUser: user),
//   //             settings: RouteSettings(name: 'ChatScreen_${user.id}'),
//   //           ),
//   //         );
//   //       } catch (e) {
//   //         debugPrint("⚠️ Failed to push chat screen: $e");
//   //       }
//   //     }
//   //   } catch (e) {
//   //     debugPrint("⚠️ Error opening chat from FCM: $e");
//   //   }
//   // }

//   static Future<void> _openChatFromUserId(String senderId) async {
//     try {
//       final userDoc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(senderId)
//           .get();
//       if (!userDoc.exists) return;

//       final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//       Future.delayed(const Duration(milliseconds: 500), () {
//         final nav = navigatorKey.currentState;
//         if (nav == null) {
//           debugPrint("⚠️ Navigator not ready, skipping navigation.");
//           return;
//         }

//         bool isCurrentChat = false;
//         nav.popUntil((route) {
//           if (route.settings.name == 'ChatScreen_${user.id}') {
//             isCurrentChat = true;
//           }
//           return true;
//         });

//         if (!isCurrentChat) {
//           try {
//             nav.push(
//               MaterialPageRoute(
//                 builder: (_) => ChatScreen(peerUser: user),
//                 settings: RouteSettings(name: 'ChatScreen_${user.id}'),
//               ),
//             );
//           } catch (e) {
//             debugPrint("⚠️ Failed to push chat screen: $e");
//           }
//         }
//       });
//     } catch (e) {
//       debugPrint("⚠️ Error opening chat from FCM: $e");
//     }
//   }

//   /// ✅ Open user profile from Like notification
//   static Future<void> _openUserProfileFromLike(String likerId) async {
//     try {
//       final userDoc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(likerId)
//           .get();
//       if (!userDoc.exists) return;

//       final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//       // ✅ Wait until the app's navigator is ready
//       Future.delayed(const Duration(milliseconds: 500), () {
//         final nav = navigatorKey.currentState;
//         if (nav == null) {
//           debugPrint("⚠️ Navigator not ready, skipping navigation.");
//           return;
//         }

//         try {
//           nav.push(
//             MaterialPageRoute(
//               builder: (_) =>
//                   DetailsScreen(user: user, fromLikeNotification: true),
//               settings: const RouteSettings(name: 'DetailsScreenFromLike'),
//             ),
//           );
//         } catch (e) {
//           debugPrint("⚠️ Failed to push DetailsScreen: $e");
//         }
//       });
//     } catch (e) {
//       debugPrint("⚠️ Error opening profile from like notification: $e");
//     }
//   }

//   // static Future<void> _openUserProfileFromLike(String likerId) async {
//   //   try {
//   //     final userDoc = await FirebaseFirestore.instance
//   //         .collection('users')
//   //         .doc(likerId)
//   //         .get();
//   //     if (!userDoc.exists) return;

//   //     final user = UserModel.fromMap(userDoc.data()!, id: userDoc.id);

//   //     try {
//   //       navigatorKey.currentState?.push(
//   //         MaterialPageRoute(
//   //           builder: (_) =>
//   //               DetailsScreen(user: user, fromLikeNotification: true),
//   //           settings: const RouteSettings(name: 'DetailsScreenFromLike'),
//   //         ),
//   //       );
//   //     } catch (e) {
//   //       debugPrint("⚠️ Failed to push DetailsScreen: $e");
//   //     }
//   //   } catch (e) {
//   //     debugPrint("⚠️ Error opening profile from like notification: $e");
//   //   }
//   // }

//   /// ✅ PUBLIC notification methods
//   static Future<void> showFirebaseLikeNotification(RemoteMessage message) =>
//       _showFirebaseLikeNotification(message);

//   static Future<void> showFirebaseChatNotification(RemoteMessage message) =>
//       _showFirebaseChatNotification(message);

//   static Future<void> showFirebaseUpdateNotification(RemoteMessage message) =>
//       _showFirebaseUpdateNotification(message);

//   /// PRIVATE notification methods with try-catch
//   static Future<void> _showFirebaseLikeNotification(
//     RemoteMessage message,
//   ) async {
//     try {
//       final likerName = message.data['likerName'] ?? 'Someone';

//       const androidDetails = AndroidNotificationDetails(
//         'like_channel',
//         'Likes',
//         channelDescription: 'Notifications for profile likes',
//         importance: Importance.max,
//         priority: Priority.high,
//         playSound: true,
//       );

//       const details = NotificationDetails(
//         android: androidDetails,
//         iOS: DarwinNotificationDetails(),
//       );

//       await _flutterLocalNotificationsPlugin.show(
//         message.hashCode,
//         'New Like ❤️',
//         '$likerName liked your profile!',
//         details,
//         payload: 'like:${message.data['likerId']}',
//       );
//     } catch (e) {
//       debugPrint("⚠️ Failed to show like notification: $e");
//     }
//   }

//   static Future<void> _showFirebaseChatNotification(
//     RemoteMessage message,
//   ) async {
//     try {
//       final senderName = message.data['senderName'] ?? 'Someone';
//       final text = message.data['message'] ?? 'New message';

//       const androidDetails = AndroidNotificationDetails(
//         'chat_channel',
//         'Chat Messages',
//         channelDescription: 'Channel for chat message notifications',
//         importance: Importance.max,
//         priority: Priority.high,
//         playSound: true,
//       );

//       const details = NotificationDetails(
//         android: androidDetails,
//         iOS: DarwinNotificationDetails(),
//       );

//       await _flutterLocalNotificationsPlugin.show(
//         message.hashCode,
//         'Message from $senderName',
//         text,
//         details,
//         payload: 'chat:${message.data['senderId']}',
//       );
//     } catch (e) {
//       debugPrint("⚠️ Failed to show chat notification: $e");
//     }
//   }

//   static Future<void> _showFirebaseUpdateNotification(
//     RemoteMessage message,
//   ) async {
//     try {
//       // 🟢 Use the _updateChannel constant instead of hardcoding
//       final androidDetails = AndroidNotificationDetails(
//         _updateChannel.id,
//         _updateChannel.name,
//         channelDescription: _updateChannel.description,
//         importance: _updateChannel.importance,
//         priority: Priority.high,
//         playSound: true,
//       );

//       final details = NotificationDetails(
//         android: androidDetails,
//         iOS: DarwinNotificationDetails(
//           presentAlert: true,
//           presentSound: true,
//           presentBadge: true,
//         ),
//       );

//       final body =
//           message.notification?.body ??
//           message.data['body'] ??
//           'A new version is ready on Play Store!';

//       await _flutterLocalNotificationsPlugin.show(
//         0, // fixed ID for updates
//         'Update Available 🚀',
//         body,
//         details,
//         payload: 'update_notification',
//       );
//     } catch (e) {
//       debugPrint("⚠️ Failed to show update notification: $e");
//     }
//   }

//   /// ✅ Chat listener for in-app messages
//   void startListening(String currentUserId) {
//     if (_subscription != null) return;

//     _subscription = _chatService.onNewMessage(currentUserId).listen((
//       msg,
//     ) async {
//       try {
//         if (msg == null || msg.senderId == currentUserId) return;

//         if (msg.senderName == null || msg.senderName!.isEmpty) {
//           try {
//             final senderDoc = await FirebaseFirestore.instance
//                 .collection('users')
//                 .doc(msg.senderId)
//                 .get();
//             msg.senderName = senderDoc.exists
//                 ? senderDoc.get('name') ?? 'Someone'
//                 : 'Someone';
//           } catch (_) {
//             msg.senderName = 'Someone';
//           }
//         }

//         if (msg.messageId == null || _shownMessageIds.contains(msg.messageId))
//           return;
//         _shownMessageIds.add(msg.messageId!);

//         final senderId = msg.senderId;
//         _groupedMessages.putIfAbsent(senderId, () => []);
//         if (!_groupedMessages[senderId]!.any(
//           (m) => m.messageId == msg.messageId,
//         )) {
//           _groupedMessages[senderId]!.insert(0, msg);
//         }

//         _notifications.insert(0, msg);
//         notifyListeners();

//         try {
//           await _showNotification(msg);
//         } catch (e) {
//           debugPrint("⚠️ Failed to show in-app notification: $e");
//         }
//       } catch (e) {
//         debugPrint("⚠️ Error in chat listener: $e");
//       }
//     });
//   }

//   static Future<void> _showNotification(ChatMessage msg) async {
//     try {
//       final senderId = msg.senderId;
//       final senderName = msg.senderName?.isNotEmpty == true
//           ? msg.senderName
//           : "Someone";

//       final lines = _groupedMessages[senderId]!
//           .map((m) => m.text)
//           .take(5)
//           .toList();

//       final inboxStyle = InboxStyleInformation(
//         lines,
//         contentTitle: "New messages from $senderName",
//         summaryText: "${_groupedMessages[senderId]!.length} messages",
//       );

//       final androidDetails = AndroidNotificationDetails(
//         _channel.id,
//         _channel.name,
//         channelDescription: _channel.description,
//         importance: Importance.max,
//         priority: Priority.high,
//         styleInformation: inboxStyle,
//         playSound: true,
//         enableVibration: true,
//         ticker: 'New Message',
//       );

//       final details = NotificationDetails(
//         android: androidDetails,
//         iOS: const DarwinNotificationDetails(
//           presentAlert: true,
//           presentSound: true,
//           presentBadge: true,
//         ),
//       );

//       await _flutterLocalNotificationsPlugin.show(
//         senderId.hashCode,
//         "Message from $senderName",
//         msg.text,
//         details,
//         payload: senderId,
//       );
//     } catch (e) {
//       debugPrint("⚠️ Failed to show grouped notification: $e");
//     }
//   }

//   void removeNotification(ChatMessage msg) {
//     try {
//       _notifications.removeWhere((n) => n.messageId == msg.messageId);
//       if (msg.messageId != null) _shownMessageIds.remove(msg.messageId!);
//       notifyListeners();
//     } catch (e) {
//       debugPrint("⚠️ Failed to remove notification: $e");
//     }
//   }

//   @override
//   void dispose() {
//     try {
//       _subscription?.cancel();
//     } catch (e) {
//       debugPrint("⚠️ Failed to cancel subscription: $e");
//     }
//     super.dispose();
//   }
// }







