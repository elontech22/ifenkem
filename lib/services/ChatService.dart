import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ifenkem/models/ChatMessageModel.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Update user online/offline status with lastActive
  Future<void> updateUserStatus(String userId, bool isOnline) async {
    await _firestore.collection('users').doc(userId).update({
      'isOnline': isOnline,
      'lastActive': isOnline
          ? FieldValue.serverTimestamp() // mark online
          : FieldValue.serverTimestamp(), // ✅ mark offline with accurate local timestamp
    });
  }

  ///  Update last seen immediately (used when going offline)
  Future<void> updateLastSeen(String userId) async {
    final now = Timestamp.fromDate(DateTime.now());
    await _firestore.collection('users').doc(userId).update({
      'isOnline': false,
      'lastActive': now, // immediate accurate timestamp
    });
  }

  /// Generate unique chatId for two users (order doesn't matter)
  String getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Listen to messages between two users
  Stream<List<ChatMessage>> getMessages(String uid1, String uid2) {
    final chatId = getChatId(uid1, uid2);
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessage.fromMap(doc.data(), id: doc.id))
              .toList(),
        );
  }

  /// Listen for new messages anywhere in the app (for notifications)
  Stream<ChatMessage?> onNewMessage(String currentUserId) {
    return _firestore
        .collectionGroup('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .snapshots()
        .map((snapshot) {
          final newMessages = snapshot.docs
              .map((doc) => ChatMessage.fromMap(doc.data(), id: doc.id))
              .toList();

          // Filter unread messages that are NOT from self
          final unreadMessages = newMessages
              .where(
                (msg) => msg.read == false && msg.senderId != currentUserId,
              )
              .toList();

          if (unreadMessages.isNotEmpty) {
            return unreadMessages.first; // Return latest unread message
          }
          return null; // No new messages
        });
  }

  /// Send a new message (now auto-fetches senderName from Firestore)
  Future<void> sendMessage(
    String senderId,
    String receiverId,
    String text,
  ) async {
    final senderBlockedReceiver = await isUserBlocked(receiverId, senderId);
    final receiverBlockedSender = await isUserBlocked(senderId, receiverId);

    if (senderBlockedReceiver) {
      throw Exception("You have blocked this user. Unblock to send message.");
    }

    if (receiverBlockedSender) {
      throw Exception("This user has blocked you. Cannot send message.");
    }

    final chatId = getChatId(senderId, receiverId);

    // Fetch senderName directly from Firestore users collection
    final senderDoc = await _firestore.collection('users').doc(senderId).get();
    final senderData = senderDoc.data() ?? {};
    final senderName =
        senderData['name'] ??
        senderData['username'] ??
        senderData['displayName'] ??
        "Unknown";

    final message = ChatMessage(
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      timestamp: Timestamp.now(),
      delivered: false,
      read: false,
      senderName: senderName,
    );

    final messagesRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages');

    final docRef = await messagesRef.add(message.toMap());

    // Update chat doc for last message info
    await _firestore.collection('chats').doc(chatId).set({
      'participants': [senderId, receiverId],
      'lastMessage': text,
      'lastTimestamp': Timestamp.now(),
    }, SetOptions(merge: true));

    await markAsDelivered(chatId, docRef.id);
  }

  /// Mark a message as delivered
  Future<void> markAsDelivered(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'delivered': true});
  }

  /// Mark a message as read
  Future<void> markAsRead(
    String chatId,
    String messageId,
    String readerId,
  ) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'read': true});
  }

  /// Block a user
  Future<void> blockUser(String currentUserId, String peerId) async {
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blocked')
        .doc(peerId)
        .set({'blockedAt': Timestamp.now()});
  }

  /// Unblock a user
  Future<void> unblockUser(String currentUserId, String peerId) async {
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blocked')
        .doc(peerId)
        .delete();
  }

  /// Check if peer is blocked (stream version)
  Stream<bool> isBlockedStream(String currentUserId, String peerId) {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blocked')
        .doc(peerId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Check if user is blocked by another
  Future<bool> isUserBlocked(String userId, String byUserId) async {
    final doc = await _firestore
        .collection('users')
        .doc(byUserId)
        .collection('blocked')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// Report a user
  Future<void> reportUser(
    String reporterId,
    String reportedId,
    String reason,
  ) async {
    await _firestore.collection('reports').add({
      'reporterId': reporterId,
      'reportedId': reportedId,
      'reason': reason,
      'timestamp': Timestamp.now(),
    });
  }
}


// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:ifenkem/models/ChatMessageModel.dart';

// class ChatService {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;

//   /// Generate unique chatId for two users (order doesn't matter)
//   String getChatId(String uid1, String uid2) {
//     final sorted = [uid1, uid2]..sort();
//     return '${sorted[0]}_${sorted[1]}';
//   }

//   /// Listen to messages between two users
//   Stream<List<ChatMessage>> getMessages(String uid1, String uid2) {
//     final chatId = getChatId(uid1, uid2);
//     return _firestore
//         .collection('chats')
//         .doc(chatId)
//         .collection('messages')
//         .orderBy('timestamp', descending: true)
//         .snapshots()
//         .map(
//           (snapshot) => snapshot.docs
//               .map((doc) => ChatMessage.fromMap(doc.data(), id: doc.id))
//               .toList(),
//         );
//   }

//   /// Listen for new messages anywhere in the app (for notifications)
//   Stream<ChatMessage?> onNewMessage(String currentUserId) {
//     return _firestore
//         .collectionGroup('messages')
//         .where('receiverId', isEqualTo: currentUserId)
//         .snapshots()
//         .map((snapshot) {
//           final newMessages = snapshot.docs
//               .map((doc) => ChatMessage.fromMap(doc.data(), id: doc.id))
//               .toList();

//           // Filter unread messages that are NOT from self
//           final unreadMessages = newMessages
//               .where(
//                 (msg) => msg.read == false && msg.senderId != currentUserId,
//               )
//               .toList();

//           if (unreadMessages.isNotEmpty) {
//             return unreadMessages.first; // Return latest unread message
//           }
//           return null; // No new messages
//         });
//   }

//   /// Send a new message (now auto-fetches senderName from Firestore)
//   Future<void> sendMessage(
//     String senderId,
//     String receiverId,
//     String text,
//   ) async {
//     final senderBlockedReceiver = await isUserBlocked(receiverId, senderId);
//     final receiverBlockedSender = await isUserBlocked(senderId, receiverId);

//     if (senderBlockedReceiver) {
//       throw Exception("You have blocked this user. Unblock to send message.");
//     }

//     if (receiverBlockedSender) {
//       throw Exception("This user has blocked you. Cannot send message.");
//     }

//     final chatId = getChatId(senderId, receiverId);

//     // 🔑 Fetch senderName directly from Firestore users collection
//     final senderDoc = await _firestore.collection('users').doc(senderId).get();
//     final senderData = senderDoc.data() ?? {};
//     final senderName =
//         senderData['name'] ??
//         senderData['username'] ??
//         senderData['displayName'] ??
//         "Unknown";

//     final message = ChatMessage(
//       senderId: senderId,
//       receiverId: receiverId,
//       text: text,
//       timestamp: Timestamp.now(),
//       delivered: false,
//       read: false,
//       senderName: senderName, // ✅ always set
//     );

//     final messagesRef = _firestore
//         .collection('chats')
//         .doc(chatId)
//         .collection('messages');

//     final docRef = await messagesRef.add(message.toMap());

//     // Update chat doc for last message info
//     await _firestore.collection('chats').doc(chatId).set({
//       'participants': [senderId, receiverId],
//       'lastMessage': text,
//       'lastTimestamp': Timestamp.now(),
//     }, SetOptions(merge: true));

//     // Optionally, mark as delivered immediately for in-app
//     await markAsDelivered(chatId, docRef.id);
//   }

//   /// Mark a message as delivered
//   Future<void> markAsDelivered(String chatId, String messageId) async {
//     await _firestore
//         .collection('chats')
//         .doc(chatId)
//         .collection('messages')
//         .doc(messageId)
//         .update({'delivered': true});
//   }

//   /// Mark a message as read
//   Future<void> markAsRead(
//     String chatId,
//     String messageId,
//     String readerId,
//   ) async {
//     await _firestore
//         .collection('chats')
//         .doc(chatId)
//         .collection('messages')
//         .doc(messageId)
//         .update({'read': true});
//   }

//   /// Block a user
//   Future<void> blockUser(String currentUserId, String peerId) async {
//     await _firestore
//         .collection('users')
//         .doc(currentUserId)
//         .collection('blocked')
//         .doc(peerId)
//         .set({'blockedAt': Timestamp.now()});
//   }

//   /// Unblock a user
//   Future<void> unblockUser(String currentUserId, String peerId) async {
//     await _firestore
//         .collection('users')
//         .doc(currentUserId)
//         .collection('blocked')
//         .doc(peerId)
//         .delete();
//   }

//   /// Check if peer is blocked (stream version)
//   Stream<bool> isBlockedStream(String currentUserId, String peerId) {
//     return _firestore
//         .collection('users')
//         .doc(currentUserId)
//         .collection('blocked')
//         .doc(peerId)
//         .snapshots()
//         .map((doc) => doc.exists);
//   }

//   /// Check if user is blocked by another
//   Future<bool> isUserBlocked(String userId, String byUserId) async {
//     final doc = await _firestore
//         .collection('users')
//         .doc(byUserId)
//         .collection('blocked')
//         .doc(userId)
//         .get();
//     return doc.exists;
//   }

//   /// Report a user
//   Future<void> reportUser(
//     String reporterId,
//     String reportedId,
//     String reason,
//   ) async {
//     await _firestore.collection('reports').add({
//       'reporterId': reporterId,
//       'reportedId': reportedId,
//       'reason': reason,
//       'timestamp': Timestamp.now(),
//     });
//   }
// }








