import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatMessage {
  final String senderId;
  final String receiverId;
  final String text;
  final Timestamp timestamp;
  final bool delivered; // true when receiver has received the message
  final bool read; // true when receiver has read the message
  final String? messageId; // optional, useful for updates
  String? senderName; //  FIXED: Added senderName to display in notifications

  ChatMessage({
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    this.delivered = false,
    this.read = false,
    this.messageId,
    this.senderName, //  FIXED
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'delivered': delivered,
      'read': read,
      'messageId': messageId,
      'senderName': senderName, //  FIXED
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, {String? id}) {
    return ChatMessage(
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      timestamp: map['timestamp'] ?? Timestamp.now(),
      delivered: map['delivered'] ?? false,
      read: map['read'] ?? false,
      messageId: id ?? map['messageId'],
      senderName: map['senderName'], //  FIXED
    );
  }

  /// Convert timestamp to
  String getFormattedTime() {
    final dateTime = timestamp.toDate();
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      // Today → show time only
      return DateFormat('h:mm a').format(dateTime);
    } else if (messageDate == yesterday) {
      // Yesterday → show "Yesterday, time"
      return "Yesterday, ${DateFormat('h:mm a').format(dateTime)}";
    } else {
      // Older → show full date and time
      return DateFormat('dd/MM/yyyy, h:mm a').format(dateTime);
    }
  }
}



// import 'package:cloud_firestore/cloud_firestore.dart';

// class ChatMessage {
//   final String senderId;
//   final String receiverId;
//   final String text;
//   final Timestamp timestamp;
//   final bool delivered; // true when receiver has received the message
//   final bool read; // true when receiver has read the message
//   final String? messageId; // optional, useful for updates

//   ChatMessage({
//     required this.senderId,
//     required this.receiverId,
//     required this.text,
//     required this.timestamp,
//     this.delivered = false,
//     this.read = false,
//     this.messageId,
//   });

//   Map<String, dynamic> toMap() {
//     return {
//       'senderId': senderId,
//       'receiverId': receiverId,
//       'text': text,
//       'timestamp': timestamp,
//       'delivered': delivered,
//       'read': read,
//       'messageId': messageId,
//     };
//   }

//   factory ChatMessage.fromMap(Map<String, dynamic> map, {String? id}) {
//     return ChatMessage(
//       senderId: map['senderId'] ?? '',
//       receiverId: map['receiverId'] ?? '',
//       text: map['text'] ?? '',
//       timestamp: map['timestamp'] ?? Timestamp.now(),
//       delivered: map['delivered'] ?? false,
//       read: map['read'] ?? false,
//       messageId: id ?? map['messageId'],
//     );
//   }
// }




