import 'package:flutter/material.dart';
import 'package:ifenkem/models/ChatMessageModel.dart';
import '../main.dart';
import 'package:ifenkem/screens/Chat_Screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ifenkem/models/user_model.dart';

class InAppNotificationBannerList extends StatefulWidget {
  final List<ChatMessage> notifications;

  /// Optional callbacks
  final void Function(ChatMessage msg)? onTap;
  final void Function(ChatMessage msg)? onDismiss;

  /// Optional: if true, will automatically navigate on tap if onTap is not provided
  final bool autoNavigate;

  const InAppNotificationBannerList({
    Key? key,
    required this.notifications,
    this.onTap,
    this.onDismiss,
    this.autoNavigate = true,
  }) : super(key: key);

  @override
  _InAppNotificationBannerListState createState() =>
      _InAppNotificationBannerListState();
}

class _InAppNotificationBannerListState
    extends State<InAppNotificationBannerList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final Set<String> _shownMessageIds = {}; //  track messages shown in UI

  @override
  void didUpdateWidget(covariant InAppNotificationBannerList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Add new notifications dynamically, only if not shown before
    for (var msg in widget.notifications) {
      if (!_shownMessageIds.contains(msg.messageId)) {
        _shownMessageIds.add(msg.messageId ?? '');
        _listKey.currentState?.insertItem(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedList(
        key: _listKey,
        shrinkWrap: true,
        reverse: true, // newest on top
        initialItemCount: widget.notifications.length,
        itemBuilder: (context, index, animation) {
          final msg = widget.notifications[index];
          return _buildItem(msg, animation);
        },
      ),
    );
  }

  Widget _buildItem(ChatMessage msg, Animation<double> animation) {
    final displayName = msg.senderName ?? "?";

    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: GestureDetector(
          onTap: () async {
            if (widget.onTap != null) {
              widget.onTap!(msg);
            } else if (widget.autoNavigate) {
              try {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(msg.senderId)
                    .get();

                if (userDoc.exists) {
                  final user = UserModel.fromMap(
                    userDoc.data() as Map<String, dynamic>,
                    id: userDoc.id,
                  );

                  bool isCurrentChat = false;
                  navigatorKey.currentState?.popUntil((route) {
                    if (route.settings.name == 'ChatScreen_${user.uid}') {
                      isCurrentChat = true;
                    }
                    return true;
                  });

                  if (!isCurrentChat) {
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(peerUser: user),
                        settings: RouteSettings(name: 'ChatScreen_${user.uid}'),
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint("Error navigating from banner: $e");
              }
            }

            _removeItem(msg);
          },
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.pink.shade400,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.pink.shade200,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        msg.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    if (widget.onDismiss != null) {
                      widget.onDismiss!(msg);
                    }
                    _removeItem(msg);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _removeItem(ChatMessage msg) {
    final index = widget.notifications.indexOf(msg);
    if (index >= 0) {
      _listKey.currentState?.removeItem(
        index,
        (context, animation) => _buildItem(msg, animation),
        duration: const Duration(milliseconds: 300),
      );

      // Remove from notifications list and shown IDs
      setState(() {
        widget.notifications.remove(msg);
        if (msg.messageId != null) _shownMessageIds.remove(msg.messageId);
      });
    }
  }
}

// import 'package:flutter/material.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';
// import '../main.dart';
// import 'package:ifenkem/screens/Chat_Screen.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:ifenkem/models/user_model.dart';

// class InAppNotificationBannerList extends StatefulWidget {
//   final List<ChatMessage> notifications;

//   /// Optional callbacks
//   final void Function(ChatMessage msg)? onTap;
//   final void Function(ChatMessage msg)? onDismiss;

//   /// Optional: if true, will automatically navigate on tap if onTap is not provided
//   final bool autoNavigate;

//   const InAppNotificationBannerList({
//     Key? key,
//     required this.notifications,
//     this.onTap,
//     this.onDismiss,
//     this.autoNavigate = true,
//   }) : super(key: key);

//   @override
//   _InAppNotificationBannerListState createState() =>
//       _InAppNotificationBannerListState();
// }

// class _InAppNotificationBannerListState
//     extends State<InAppNotificationBannerList> {
//   final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

//   @override
//   void didUpdateWidget(covariant InAppNotificationBannerList oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     // Add new notifications dynamically
//     if (widget.notifications.length > oldWidget.notifications.length) {
//       _listKey.currentState?.insertItem(0);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Positioned(
//       top: 0,
//       left: 0,
//       right: 0,
//       child: AnimatedList(
//         key: _listKey,
//         shrinkWrap: true,
//         reverse: true, // newest on top
//         initialItemCount: widget.notifications.length,
//         itemBuilder: (context, index, animation) {
//           final msg = widget.notifications[index];
//           return _buildItem(msg, animation);
//         },
//       ),
//     );
//   }

//   Widget _buildItem(ChatMessage msg, Animation<double> animation) {
//     final displayName = msg.senderName ?? "?";

//     return SizeTransition(
//       sizeFactor: animation,
//       axisAlignment: -1,
//       child: FadeTransition(
//         opacity: animation,
//         child: GestureDetector(
//           onTap: () async {
//             if (widget.onTap != null) {
//               widget.onTap!(msg);
//             } else if (widget.autoNavigate) {
//               try {
//                 final userDoc = await FirebaseFirestore.instance
//                     .collection('users')
//                     .doc(msg.senderId)
//                     .get();

//                 if (userDoc.exists) {
//                   final user = UserModel.fromMap(
//                     userDoc.data() as Map<String, dynamic>,
//                     id: userDoc.id,
//                   );

//                   bool isCurrentChat = false;
//                   navigatorKey.currentState?.popUntil((route) {
//                     if (route.settings.name == 'ChatScreen_${user.uid}') {
//                       isCurrentChat = true;
//                     }
//                     return true;
//                   });

//                   if (!isCurrentChat) {
//                     navigatorKey.currentState?.push(
//                       MaterialPageRoute(
//                         builder: (_) => ChatScreen(peerUser: user),
//                         settings: RouteSettings(name: 'ChatScreen_${user.uid}'),
//                       ),
//                     );
//                   }
//                 }
//               } catch (e) {
//                 debugPrint("Error navigating from banner: $e");
//               }
//             }

//             _removeItem(msg);
//           },
//           child: Container(
//             margin: const EdgeInsets.all(10),
//             padding: const EdgeInsets.all(12),
//             decoration: BoxDecoration(
//               color: Colors.pink.shade400,
//               borderRadius: BorderRadius.circular(14),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black26,
//                   blurRadius: 6,
//                   offset: const Offset(0, 3),
//                 ),
//               ],
//             ),
//             child: Row(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 CircleAvatar(
//                   backgroundColor: Colors.pink.shade200,
//                   child: Text(
//                     displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 10),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         displayName,
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 15,
//                         ),
//                       ),
//                       const SizedBox(height: 3),
//                       Text(
//                         msg.text,
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontSize: 14,
//                         ),
//                         maxLines: 2,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ],
//                   ),
//                 ),
//                 IconButton(
//                   icon: const Icon(
//                     Icons.close,
//                     color: Colors.white70,
//                     size: 20,
//                   ),
//                   onPressed: () {
//                     if (widget.onDismiss != null) {
//                       widget.onDismiss!(msg);
//                     }
//                     _removeItem(msg);
//                   },
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   void _removeItem(ChatMessage msg) {
//     final index = widget.notifications.indexOf(msg);
//     if (index >= 0) {
//       _listKey.currentState?.removeItem(
//         index,
//         (context, animation) => _buildItem(msg, animation),
//         duration: const Duration(milliseconds: 300),
//       );

//       // Remove from notifications list
//       setState(() {
//         widget.notifications.remove(msg);
//       });
//     }
//   }
// }
