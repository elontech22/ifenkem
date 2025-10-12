import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  final String id;
  final String userId;
  final String userName;
  final String location;
  final String gender;
  final List<String> imageUrls;
  final Timestamp timestamp;
  final List<String> viewers; // ✅ Add this field

  StoryModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.location,
    required this.gender,
    required this.imageUrls,
    required this.timestamp,
    this.viewers = const [], // initialize empty list
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'location': location,
      'gender': gender,
      'imageUrls': imageUrls,
      'timestamp': timestamp,
      'viewers': viewers, // add viewers to Firestore
    };
  }

  factory StoryModel.fromMap(Map<String, dynamic> map, String id) {
    return StoryModel(
      id: id,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      location: map['location'] ?? '',
      gender: map['gender'] ?? '',
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      timestamp: map['timestamp'] ?? Timestamp.now(),
      viewers: map['viewers'] != null ? List<String>.from(map['viewers']) : [],
    );
  }
}
