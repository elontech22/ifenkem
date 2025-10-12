import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ifenkem/widgets/InAppNotificationBanner.dart';
import 'package:provider/provider.dart';
import 'package:ifenkem/models/ChatMessageModel.dart';
import 'package:ifenkem/screens/PremiumScreen.dart';
import 'package:ifenkem/services/ChatService.dart';
import 'package:ifenkem/services/LocalNotificationService.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final UserModel peerUser;
  const ChatScreen({super.key, required this.peerUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String currentUserId;
  bool isChatReady = false;
  final ChatService _chatService = ChatService();
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final localService = Provider.of<LocalNotificationService>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      currentUserId = authProvider.currentUser!.uid;
      localService.startListening(currentUserId);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
  }

  @override
  void dispose() {
    _sendTypingStatus(false);
    _typingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (currentUserId.isEmpty) return;

    if (state == AppLifecycleState.resumed) {
      await _chatService.updateUserStatus(currentUserId, true);
    } else {
      // ✅ update offline timestamp accurately
      await _chatService.updateLastSeen(currentUserId);
    }
  }

  void _initChat() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      Navigator.pop(context);
      return;
    }

    currentUserId = currentUser.uid;

    try {
      // await FirebaseFirestore.instance
      //     .collection('users')
      //     .doc(currentUserId)
      //     .update({'isOnline': true});
      await _chatService.updateUserStatus(currentUserId, true);
    } catch (e) {
      if (kDebugMode) print("Firestore update error: $e");
    }

    setState(() => isChatReady = true);
  }

  void _sendTypingStatus(bool typing) {
    final chatId = _chat_service_getChatIdSafe(
      currentUserId,
      widget.peerUser.uid,
    );
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(currentUserId)
        .set({'isTyping': typing}, SetOptions(merge: true));
  }

  String _chat_service_getChatIdSafe(String a, String b) =>
      _chat_service_getChatId(a, b);
  String _chat_service_getChatId(String a, String b) =>
      _chat_service_getChatId_impl(a, b);
  String _chat_service_getChatId_impl(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  void _handleUserTyping(String text) {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _sendTypingStatus(text.isNotEmpty);
    if (text.isNotEmpty) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _sendTypingStatus(false);
      });
    } else {
      _sendTypingStatus(false);
    }
  }

  void _reportUser() async {
    final reasonController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Report User"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: "Reason"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await _chat_service_reportUserSafe(
                currentUserId,
                widget.peerUser.uid,
                reasonController.text.trim().isEmpty
                    ? "No reason provided"
                    : reasonController.text.trim(),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("User reported")));
            },
            child: const Text("Report"),
          ),
        ],
      ),
    );
  }

  Future<void> _chat_service_reportUserSafe(
    String r,
    String d,
    String reason,
  ) => _chatService.reportUser(r, d, reason);

  Map<String, List<ChatMessage>> _groupMessages(List<ChatMessage> messages) {
    Map<String, List<ChatMessage>> grouped = {};
    for (var msg in messages) {
      final dt = msg.timestamp.toDate();
      String key;
      final now = DateTime.now();

      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        key = "Today";
      } else if (dt.day == now.subtract(const Duration(days: 1)).day &&
          dt.month == now.month &&
          dt.year == now.year) {
        key = "Yesterday";
      } else {
        key = DateFormat('dd/MM/yyyy').format(dt);
      }

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(msg);
    }

    for (var key in grouped.keys) {
      grouped[key]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return grouped;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scroll_controller_getMinExtent(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  double _scroll_controller_getMinExtent() =>
      _scrollController.position.minScrollExtent;

  String _formatLastSeen(Timestamp? timestamp) {
    if (timestamp == null) return "last seen recently";

    final dt = timestamp.toDate();
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastSeenDate = DateTime(dt.year, dt.month, dt.day);

    if (lastSeenDate == today) {
      return "last seen today at ${DateFormat.jm().format(dt)}"; // ✅ today
    } else if (lastSeenDate == yesterday) {
      return "last seen yesterday at ${DateFormat.jm().format(dt)}"; // ✅ yesterday
    } else {
      return "last seen on ${DateFormat('dd/MM/yyyy, hh:mm a').format(dt)}"; // ✅ older
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, LocalNotificationService>(
      builder: (context, authProvider, notifService, _) {
        final currentUser = authProvider.currentUser;

        if (!isChatReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (currentUser == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                "User not logged in.",
                style: TextStyle(fontSize: 18),
              ),
            ),
          );
        }

        final isPremiumActive =
            currentUser.isPremium &&
            currentUser.premiumEnd != null &&
            DateTime.now().isBefore(currentUser.premiumEnd!);

        if (!isPremiumActive) {
          return Scaffold(
            appBar: AppBar(title: const Text("Chat")),
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PremiumScreen()),
                  );
                },
                child: const Text("Upgrade to Premium to chat"),
              ),
            ),
          );
        }

        final chatId = _chatService.getChatId(
          currentUserId,
          widget.peerUser.uid,
        );

        return Scaffold(
          appBar: AppBar(
            title: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.peerUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Text(widget.peerUser.name);
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final isOnline = data['isOnline'] ?? false;
                final lastActive = data['lastActive'] as Timestamp?;

                // ✅ Only show lastActive if exists, no fake fallback
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.peerUser.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (isOnline)
                                CircleAvatar(
                                  radius: 6,
                                  backgroundColor: Colors.green,
                                ),
                              if (isOnline) const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  isOnline
                                      ? "Online"
                                      : lastActive != null
                                      ? _formatLastSeen(
                                          lastActive,
                                        ) // ✅ accurate last seen
                                      : "last seen recently",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            actions: [
              StreamBuilder<bool>(
                stream: _chatService.isBlockedStream(
                  currentUserId,
                  widget.peerUser.uid,
                ),
                builder: (context, snapshot) {
                  final isBlocked = snapshot.data ?? false;
                  return PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == "block") {
                        await _chatService.blockUser(
                          currentUserId,
                          widget.peerUser.uid,
                        );
                      } else if (value == "unblock") {
                        await _chatService.unblockUser(
                          currentUserId,
                          widget.peerUser.uid,
                        );
                      } else if (value == "report") {
                        _reportUser();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: isBlocked ? "unblock" : "block",
                        child: Text(isBlocked ? "Unblock" : "Block"),
                      ),
                      const PopupMenuItem(
                        value: "report",
                        child: Text("Report"),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),

          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _chatService.getMessages(
                        currentUserId,
                        widget.peerUser.uid,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text("No messages yet. Say hi 👋"),
                          );
                        }

                        final messages = snapshot.data!;
                        final grouped = _groupMessages(messages);
                        final sortedGroups = grouped.entries.toList()
                          ..sort(
                            (a, b) => a.value.first.timestamp.compareTo(
                              b.value.first.timestamp,
                            ),
                          );

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          itemCount: sortedGroups.length,
                          itemBuilder: (context, index) {
                            final entry =
                                sortedGroups[sortedGroups.length - 1 - index];
                            final dateLabel = entry.key;
                            final msgs = entry.value;

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    dateLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                ...msgs.map((msg) {
                                  final isMe = msg.senderId == currentUserId;

                                  if (!isMe && !msg.read) {
                                    final msgChatId = _chatService.getChatId(
                                      msg.senderId,
                                      msg.receiverId,
                                    );
                                    _chatService.markAsRead(
                                      msgChatId,
                                      msg.messageId ?? '',
                                      currentUserId,
                                    );
                                  }

                                  return Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? AppTheme.primaryColor
                                            : const Color(0xFFFFCDD2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            msg.text,
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                msg.getFormattedTime(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isMe
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                              if (isMe)
                                                const SizedBox(width: 6),
                                              if (isMe)
                                                Icon(
                                                  msg.read
                                                      ? Icons.done_all
                                                      : msg.delivered
                                                      ? Icons.done
                                                      : Icons.access_time,
                                                  size: 14,
                                                  color: msg.read
                                                      ? Colors.blue
                                                      : Colors.white70,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(chatId)
                        .collection('typing')
                        .snapshots(),
                    builder: (context, snapshot) {
                      bool peerTyping = false;
                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>?;
                          if (doc.id != currentUserId &&
                              data?['isTyping'] == true) {
                            peerTyping = true;
                            break;
                          }
                        }
                      }
                      return peerTyping
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: Text(
                                "Typing...",
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    },
                  ),
                  const Divider(height: 1),
                  StreamBuilder<bool>(
                    stream: _chatService.isBlockedStream(
                      widget.peerUser.uid,
                      currentUser.uid,
                    ),
                    builder: (context, snapshot) {
                      final amIBlocked = snapshot.data ?? false;
                      if (amIBlocked) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            "You can’t send messages to this user.",
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: const InputDecoration(
                                  hintText: "Type a message",
                                ),
                                onChanged: _handleUserTyping,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: AppTheme.primaryColor,
                              ),
                              onPressed: () async {
                                final text = _controller.text.trim();
                                if (text.isEmpty) return;

                                try {
                                  await _chatService.sendMessage(
                                    currentUserId,
                                    widget.peerUser.uid,
                                    text,
                                    // senderName: currentUser.name,
                                  );
                                  _controller.clear();
                                  _sendTypingStatus(false);
                                  _scrollToBottom();
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              // Notification Banner
              if (notifService.notifications.isNotEmpty)
                InAppNotificationBannerList(
                  notifications: notifService.notifications,
                  onTap: (msg) async {
                    notifService.removeNotification(msg);

                    final senderDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(msg.senderId)
                        .get();
                    if (!senderDoc.exists) return;

                    final senderUser = UserModel.fromMap(
                      senderDoc.data() as Map<String, dynamic>,
                      id: senderDoc.id,
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(peerUser: senderUser),
                      ),
                    );
                  },
                  onDismiss: (msg) {
                    notifService.removeNotification(msg);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback resumeCallBack;
  final AsyncCallback suspendingCallBack;

  LifecycleEventHandler({
    required this.resumeCallBack,
    required this.suspendingCallBack,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resumeCallBack();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        suspendingCallBack();
        break;
    }
  }
}




// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:ifenkem/widgets/InAppNotificationBanner.dart';
// import 'package:provider/provider.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';
// import 'package:ifenkem/screens/PremiumScreen.dart';
// import 'package:ifenkem/services/ChatService.dart';
// import 'package:ifenkem/services/LocalNotificationService.dart';
// import '../models/user_model.dart';
// import '../providers/auth_provider.dart';
// import '../utils/app_theme.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:intl/intl.dart';

// class ChatScreen extends StatefulWidget {
//   final UserModel peerUser;
//   const ChatScreen({super.key, required this.peerUser});

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
//   final TextEditingController _controller = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   late String currentUserId;
//   bool isChatReady = false;
//   final ChatService _chatService = ChatService();
//   Timer? _typingTimer;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);

//     final localService = Provider.of<LocalNotificationService>(
//       context,
//       listen: false,
//     );
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);

//     if (authProvider.currentUser != null) {
//       currentUserId = authProvider.currentUser!.uid;
//       localService.startListening(currentUserId);
//     }

//     WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
//   }

//   @override
//   void dispose() {
//     _sendTypingStatus(false);
//     _typingTimer?.cancel();
//     WidgetsBinding.instance.removeObserver(this);
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) async {
//     if (currentUserId.isEmpty) return;
//     final userRef = FirebaseFirestore.instance
//         .collection('users')
//         .doc(currentUserId);

//     if (state == AppLifecycleState.resumed) {
//       await userRef.update({'isOnline': true});
//     } else {
//       await userRef.update({'isOnline': false});
//     }
//   }

//   void _initChat() async {
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;

//     if (currentUser == null) {
//       Navigator.pop(context);
//       return;
//     }

//     currentUserId = currentUser.uid;

//     try {
//       await FirebaseFirestore.instance
//           .collection('users')
//           .doc(currentUserId)
//           .update({'isOnline': true});
//     } catch (e) {
//       if (kDebugMode) print("Firestore update error: $e");
//     }

//     setState(() => isChatReady = true);
//   }

//   void _sendTypingStatus(bool typing) {
//     final chatId = _chatService.getChatId(currentUserId, widget.peerUser.uid);
//     FirebaseFirestore.instance
//         .collection('chats')
//         .doc(chatId)
//         .collection('typing')
//         .doc(currentUserId)
//         .set({'isTyping': typing}, SetOptions(merge: true));
//   }

//   void _handleUserTyping(String text) {
//     if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
//     _sendTypingStatus(text.isNotEmpty);
//     if (text.isNotEmpty) {
//       _typingTimer = Timer(const Duration(seconds: 3), () {
//         _sendTypingStatus(false);
//       });
//     } else {
//       _sendTypingStatus(false);
//     }
//   }

//   void _reportUser() async {
//     final reasonController = TextEditingController();
//     await showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text("Report User"),
//         content: TextField(
//           controller: reasonController,
//           decoration: const InputDecoration(hintText: "Reason"),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text("Cancel"),
//           ),
//           TextButton(
//             onPressed: () async {
//               await _chatService.reportUser(
//                 currentUserId,
//                 widget.peerUser.uid,
//                 reasonController.text.trim().isEmpty
//                     ? "No reason provided"
//                     : reasonController.text.trim(),
//               );
//               Navigator.pop(ctx);
//               ScaffoldMessenger.of(
//                 context,
//               ).showSnackBar(const SnackBar(content: Text("User reported")));
//             },
//             child: const Text("Report"),
//           ),
//         ],
//       ),
//     );
//   }

//   Map<String, List<ChatMessage>> _groupMessages(List<ChatMessage> messages) {
//     Map<String, List<ChatMessage>> grouped = {};
//     for (var msg in messages) {
//       final dt = msg.timestamp.toDate();
//       String key;
//       final now = DateTime.now();

//       if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
//         key = "Today";
//       } else if (dt.day == now.subtract(const Duration(days: 1)).day &&
//           dt.month == now.month &&
//           dt.year == now.year) {
//         key = "Yesterday";
//       } else {
//         key = DateFormat('dd/MM/yyyy').format(dt);
//       }

//       grouped.putIfAbsent(key, () => []);
//       grouped[key]!.add(msg);
//     }

//     for (var key in grouped.keys) {
//       grouped[key]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
//     }

//     return grouped;
//   }

//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       _scrollController.animateTo(
//         _scrollController.position.minScrollExtent,
//         duration: const Duration(milliseconds: 300),
//         curve: Curves.easeOut,
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Consumer2<AuthProvider, LocalNotificationService>(
//       builder: (context, authProvider, notifService, _) {
//         final currentUser = authProvider.currentUser;

//         if (!isChatReady) {
//           return const Scaffold(
//             body: Center(child: CircularProgressIndicator()),
//           );
//         }

//         if (currentUser == null) {
//           return const Scaffold(
//             body: Center(
//               child: Text(
//                 "User not logged in.",
//                 style: TextStyle(fontSize: 18),
//               ),
//             ),
//           );
//         }

//         final isPremiumActive =
//             currentUser.isPremium &&
//             currentUser.premiumEnd != null &&
//             DateTime.now().isBefore(currentUser.premiumEnd!);

//         if (!isPremiumActive) {
//           return Scaffold(
//             appBar: AppBar(title: const Text("Chat")),
//             body: Center(
//               child: ElevatedButton(
//                 onPressed: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(builder: (_) => PremiumScreen()),
//                   );
//                 },
//                 child: const Text("Upgrade to Premium to chat"),
//               ),
//             ),
//           );
//         }

//         final chatId = _chatService.getChatId(
//           currentUserId,
//           widget.peerUser.uid,
//         );

//         return Scaffold(
//           appBar: AppBar(
//             title: Row(
//               children: [
//                 Text(widget.peerUser.name),
//                 const SizedBox(width: 8),
//                 StreamBuilder<DocumentSnapshot>(
//                   stream: FirebaseFirestore.instance
//                       .collection('users')
//                       .doc(widget.peerUser.uid)
//                       .snapshots(),
//                   builder: (context, snapshot) {
//                     bool isOnline = false;
//                     if (snapshot.hasData && snapshot.data!.exists) {
//                       final data =
//                           snapshot.data!.data() as Map<String, dynamic>;
//                       isOnline = data['isOnline'] ?? false;
//                     }
//                     return CircleAvatar(
//                       radius: 6,
//                       backgroundColor: isOnline ? Colors.green : Colors.grey,
//                     );
//                   },
//                 ),
//               ],
//             ),
//             actions: [
//               StreamBuilder<bool>(
//                 stream: _chatService.isBlockedStream(
//                   currentUserId,
//                   widget.peerUser.uid,
//                 ),
//                 builder: (context, snapshot) {
//                   final isBlocked = snapshot.data ?? false;
//                   return PopupMenuButton<String>(
//                     onSelected: (value) async {
//                       if (value == "block") {
//                         await _chatService.blockUser(
//                           currentUserId,
//                           widget.peerUser.uid,
//                         );
//                       } else if (value == "unblock") {
//                         await _chatService.unblockUser(
//                           currentUserId,
//                           widget.peerUser.uid,
//                         );
//                       } else if (value == "report") {
//                         _reportUser();
//                       }
//                     },
//                     itemBuilder: (ctx) => [
//                       PopupMenuItem(
//                         value: isBlocked ? "unblock" : "block",
//                         child: Text(isBlocked ? "Unblock" : "Block"),
//                       ),
//                       const PopupMenuItem(
//                         value: "report",
//                         child: Text("Report"),
//                       ),
//                     ],
//                   );
//                 },
//               ),
//             ],
//           ),
//           body: Stack(
//             children: [
//               Column(
//                 children: [
//                   Expanded(
//                     child: StreamBuilder<List<ChatMessage>>(
//                       stream: _chatService.getMessages(
//                         currentUserId,
//                         widget.peerUser.uid,
//                       ),
//                       builder: (context, snapshot) {
//                         if (snapshot.connectionState ==
//                             ConnectionState.waiting) {
//                           return const Center(
//                             child: CircularProgressIndicator(),
//                           );
//                         }

//                         if (!snapshot.hasData || snapshot.data!.isEmpty) {
//                           return const Center(
//                             child: Text("No messages yet. Say hi 👋"),
//                           );
//                         }

//                         final messages = snapshot.data!;
//                         final grouped = _groupMessages(messages);
//                         final sortedGroups = grouped.entries.toList()
//                           ..sort(
//                             (a, b) => a.value.first.timestamp.compareTo(
//                               b.value.first.timestamp,
//                             ),
//                           );

//                         return ListView.builder(
//                           controller: _scrollController,
//                           reverse: true,
//                           itemCount: sortedGroups.length,
//                           itemBuilder: (context, index) {
//                             final entry =
//                                 sortedGroups[sortedGroups.length - 1 - index];
//                             final dateLabel = entry.key;
//                             final msgs = entry.value;

//                             return Column(
//                               children: [
//                                 Padding(
//                                   padding: const EdgeInsets.symmetric(
//                                     vertical: 8,
//                                   ),
//                                   child: Text(
//                                     dateLabel,
//                                     style: const TextStyle(
//                                       fontSize: 12,
//                                       color: Colors.grey,
//                                       fontWeight: FontWeight.w500,
//                                     ),
//                                   ),
//                                 ),
//                                 ...msgs.map((msg) {
//                                   final isMe = msg.senderId == currentUserId;

//                                   if (!isMe && !msg.read) {
//                                     final msgChatId = _chatService.getChatId(
//                                       msg.senderId,
//                                       msg.receiverId,
//                                     );
//                                     _chatService.markAsRead(
//                                       msgChatId,
//                                       msg.messageId ?? '',
//                                       currentUserId,
//                                     );
//                                   }

//                                   return Align(
//                                     alignment: isMe
//                                         ? Alignment.centerRight
//                                         : Alignment.centerLeft,
//                                     child: Container(
//                                       padding: const EdgeInsets.symmetric(
//                                         horizontal: 12,
//                                         vertical: 8,
//                                       ),
//                                       margin: const EdgeInsets.symmetric(
//                                         horizontal: 12,
//                                         vertical: 4,
//                                       ),
//                                       decoration: BoxDecoration(
//                                         color: isMe
//                                             ? AppTheme.primaryColor
//                                             : const Color(0xFFFFCDD2),
//                                         borderRadius: BorderRadius.circular(16),
//                                       ),
//                                       child: Column(
//                                         crossAxisAlignment:
//                                             CrossAxisAlignment.end,
//                                         children: [
//                                           Text(
//                                             msg.text,
//                                             style: TextStyle(
//                                               color: isMe
//                                                   ? Colors.white
//                                                   : Colors.black,
//                                             ),
//                                           ),
//                                           const SizedBox(height: 4),
//                                           Row(
//                                             mainAxisSize: MainAxisSize.min,
//                                             children: [
//                                               Text(
//                                                 msg.getFormattedTime(),
//                                                 style: TextStyle(
//                                                   fontSize: 10,
//                                                   color: isMe
//                                                       ? Colors.white70
//                                                       : Colors.black54,
//                                                 ),
//                                               ),
//                                               if (isMe)
//                                                 const SizedBox(width: 6),
//                                               if (isMe)
//                                                 Icon(
//                                                   msg.read
//                                                       ? Icons.done_all
//                                                       : msg.delivered
//                                                       ? Icons.done
//                                                       : Icons.access_time,
//                                                   size: 14,
//                                                   color: msg.read
//                                                       ? Colors.blue
//                                                       : Colors.white70,
//                                                 ),
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   );
//                                 }).toList(),
//                               ],
//                             );
//                           },
//                         );
//                       },
//                     ),
//                   ),
//                   StreamBuilder<QuerySnapshot>(
//                     stream: FirebaseFirestore.instance
//                         .collection('chats')
//                         .doc(chatId)
//                         .collection('typing')
//                         .snapshots(),
//                     builder: (context, snapshot) {
//                       bool peerTyping = false;
//                       if (snapshot.hasData) {
//                         for (var doc in snapshot.data!.docs) {
//                           final data = doc.data() as Map<String, dynamic>?;
//                           if (doc.id != currentUserId &&
//                               data?['isTyping'] == true) {
//                             peerTyping = true;
//                             break;
//                           }
//                         }
//                       }
//                       return peerTyping
//                           ? const Padding(
//                               padding: EdgeInsets.all(4),
//                               child: Text(
//                                 "Typing...",
//                                 style: TextStyle(
//                                   fontStyle: FontStyle.italic,
//                                   color: Colors.grey,
//                                 ),
//                               ),
//                             )
//                           : const SizedBox.shrink();
//                     },
//                   ),
//                   const Divider(height: 1),
//                   StreamBuilder<bool>(
//                     stream: _chatService.isBlockedStream(
//                       widget.peerUser.uid,
//                       currentUser.uid,
//                     ),
//                     builder: (context, snapshot) {
//                       final amIBlocked = snapshot.data ?? false;
//                       if (amIBlocked) {
//                         return const Padding(
//                           padding: EdgeInsets.all(12),
//                           child: Text(
//                             "You can’t send messages to this user.",
//                             style: TextStyle(color: Colors.red),
//                           ),
//                         );
//                       }
//                       return Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: Row(
//                           children: [
//                             Expanded(
//                               child: TextField(
//                                 controller: _controller,
//                                 decoration: const InputDecoration(
//                                   hintText: "Type a message",
//                                 ),
//                                 onChanged: _handleUserTyping,
//                               ),
//                             ),
//                             IconButton(
//                               icon: const Icon(
//                                 Icons.send,
//                                 color: AppTheme.primaryColor,
//                               ),
//                               onPressed: () async {
//                                 final text = _controller.text.trim();
//                                 if (text.isEmpty) return;

//                                 try {
//                                   await _chatService.sendMessage(
//                                     currentUserId,
//                                     widget.peerUser.uid,
//                                     text,
//                                     // senderName: currentUser.name,
//                                   );
//                                   _controller.clear();
//                                   _sendTypingStatus(false);
//                                   _scrollToBottom();
//                                 } catch (e) {
//                                   ScaffoldMessenger.of(context).showSnackBar(
//                                     SnackBar(content: Text(e.toString())),
//                                   );
//                                 }
//                               },
//                             ),
//                           ],
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               ),
//               // Notification Banner
//               if (notifService.notifications.isNotEmpty)
//                 InAppNotificationBannerList(
//                   notifications: notifService.notifications,
//                   onTap: (msg) async {
//                     notifService.removeNotification(msg);

//                     final senderDoc = await FirebaseFirestore.instance
//                         .collection('users')
//                         .doc(msg.senderId)
//                         .get();
//                     if (!senderDoc.exists) return;

//                     final senderUser = UserModel.fromMap(
//                       senderDoc.data() as Map<String, dynamic>,
//                       id: senderDoc.id,
//                     );

//                     Navigator.push(
//                       context,
//                       MaterialPageRoute(
//                         builder: (_) => ChatScreen(peerUser: senderUser),
//                       ),
//                     );
//                   },
//                   onDismiss: (msg) {
//                     notifService.removeNotification(msg);
//                   },
//                 ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

// class LifecycleEventHandler extends WidgetsBindingObserver {
//   final AsyncCallback resumeCallBack;
//   final AsyncCallback suspendingCallBack;

//   LifecycleEventHandler({
//     required this.resumeCallBack,
//     required this.suspendingCallBack,
//   });

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     switch (state) {
//       case AppLifecycleState.resumed:
//         resumeCallBack();
//         break;
//       case AppLifecycleState.paused:
//       case AppLifecycleState.inactive:
//       case AppLifecycleState.detached:
//       case AppLifecycleState.hidden:
//         suspendingCallBack();
//         break;
//     }
//   }
// }


