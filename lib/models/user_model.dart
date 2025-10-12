import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  String uid;
  String name;
  String username;
  String email;
  String occupation;
  String educationLevel;
  int age;
  String religion;
  String location;
  String gender;
  List<String> profileImageUrls;
  String description;
  bool isPremium;
  bool isOnline;
  bool canChat;

  DateTime? premiumStart;
  DateTime? premiumEnd;
  DateTime? lastActive;

  String? fcmToken;

  UserModel({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    required this.occupation,
    required this.educationLevel,
    required this.age,
    required this.religion,
    required this.location,
    this.gender = "Not Specified",
    required this.profileImageUrls,
    this.description = "",
    this.isPremium = false,
    this.isOnline = false,
    this.canChat = false,
    this.premiumStart,
    this.premiumEnd,
    this.lastActive,
    this.fcmToken,
  });

  /// ✅ Add this getter so `user.id` works anywhere
  String get id => uid;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'username': username,
      'email': email,
      'occupation': occupation,
      'educationLevel': educationLevel,
      'age': age,
      'religion': religion,
      'location': location,
      'gender': gender,
      'profileImageUrls': profileImageUrls,
      'description': description,
      'isPremium': isPremium,
      'isOnline': isOnline,
      'canChat': canChat,
      if (premiumStart != null)
        'premiumStart': Timestamp.fromDate(premiumStart!),
      if (premiumEnd != null) 'premiumEnd': Timestamp.fromDate(premiumEnd!),
      if (lastActive != null) 'lastActive': Timestamp.fromDate(lastActive!),
      if (fcmToken != null) 'fcmToken': fcmToken, // ✅ Save token to Firestore
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime? parseTimestamp(dynamic ts) {
      if (ts == null) return null;
      if (ts is Timestamp) return ts.toDate();
      if (ts is String) return DateTime.tryParse(ts);
      return null;
    }

    return UserModel(
      uid: id ?? map['uid'] ?? '',
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      occupation: map['occupation'] ?? '',
      educationLevel: map['educationLevel'] ?? '',
      age: map['age'] ?? 0,
      religion: map['religion'] ?? '',
      location: map['location'] ?? '',
      gender: map['gender'] ?? "Not Specified",
      profileImageUrls: map['profileImageUrls'] != null
          ? List<String>.from(map['profileImageUrls'])
          : [],
      description: map['description'] ?? "",
      isPremium: map['isPremium'] ?? false,
      isOnline: map['isOnline'] ?? false,
      canChat: map['canChat'] ?? false,
      premiumStart: parseTimestamp(map['premiumStart']),
      premiumEnd: parseTimestamp(map['premiumEnd']),
      lastActive: parseTimestamp(map['lastActive']),
      fcmToken: map['fcmToken'], // ✅ Read token from Firestore
    );
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? username,
    String? email,
    String? occupation,
    String? educationLevel,
    int? age,
    String? religion,
    String? location,
    String? gender,
    List<String>? profileImageUrls,
    String? description,
    bool? isPremium,
    bool? isOnline,
    bool? canChat,
    DateTime? premiumStart,
    DateTime? premiumEnd,
    DateTime? lastActive,
    String? fcmToken, // ✅ Add copyWith support
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      occupation: occupation ?? this.occupation,
      educationLevel: educationLevel ?? this.educationLevel,
      age: age ?? this.age,
      religion: religion ?? this.religion,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      profileImageUrls: profileImageUrls ?? this.profileImageUrls,
      description: description ?? this.description,
      isPremium: isPremium ?? this.isPremium,
      isOnline: isOnline ?? this.isOnline,
      canChat: canChat ?? this.canChat,
      premiumStart: premiumStart ?? this.premiumStart,
      premiumEnd: premiumEnd ?? this.premiumEnd,
      lastActive: lastActive ?? this.lastActive,
      fcmToken: fcmToken ?? this.fcmToken, // ✅ Preserve or update token
    );
  }
}


// import 'package:cloud_firestore/cloud_firestore.dart';

// class UserModel {
//   String uid;
//   String name;
//   String username;
//   String email;
//   String occupation;
//   String educationLevel;
//   int age;
//   String religion;
//   String location;
//   String gender;
//   List<String> profileImageUrls;
//   String description;
//   bool isPremium;
//   bool isOnline;
//   bool canChat;

//   DateTime? premiumStart;
//   DateTime? premiumEnd;
//   DateTime? lastActive;

//   UserModel({
//     required this.uid,
//     required this.name,
//     required this.username,
//     required this.email,
//     required this.occupation,
//     required this.educationLevel,
//     required this.age,
//     required this.religion,
//     required this.location,
//     this.gender = "Not Specified",
//     required this.profileImageUrls,
//     this.description = "",
//     this.isPremium = false,
//     this.isOnline = false,
//     this.canChat = false,
//     this.premiumStart,
//     this.premiumEnd,
//     this.lastActive,
//   });

//   /// ✅ Add this getter so `user.id` works anywhere
//   String get id => uid;

//   Map<String, dynamic> toMap() {
//     return {
//       'uid': uid,
//       'name': name,
//       'username': username,
//       'email': email,
//       'occupation': occupation,
//       'educationLevel': educationLevel,
//       'age': age,
//       'religion': religion,
//       'location': location,
//       'gender': gender,
//       'profileImageUrls': profileImageUrls,
//       'description': description,
//       'isPremium': isPremium,
//       'isOnline': isOnline,
//       'canChat': canChat,
//       if (premiumStart != null)
//         'premiumStart': Timestamp.fromDate(premiumStart!),
//       if (premiumEnd != null) 'premiumEnd': Timestamp.fromDate(premiumEnd!),
//       if (lastActive != null) 'lastActive': Timestamp.fromDate(lastActive!),
//     };
//   }

//   factory UserModel.fromMap(Map<String, dynamic> map, {String? id}) {
//     DateTime? parseTimestamp(dynamic ts) {
//       if (ts == null) return null;
//       if (ts is Timestamp) return ts.toDate();
//       if (ts is String) return DateTime.tryParse(ts);
//       return null;
//     }

//     return UserModel(
//       uid: id ?? map['uid'] ?? '',
//       name: map['name'] ?? '',
//       username: map['username'] ?? '',
//       email: map['email'] ?? '',
//       occupation: map['occupation'] ?? '',
//       educationLevel: map['educationLevel'] ?? '',
//       age: map['age'] ?? 0,
//       religion: map['religion'] ?? '',
//       location: map['location'] ?? '',
//       gender: map['gender'] ?? "Not Specified",
//       profileImageUrls: map['profileImageUrls'] != null
//           ? List<String>.from(map['profileImageUrls'])
//           : [],
//       description: map['description'] ?? "",
//       isPremium: map['isPremium'] ?? false,
//       isOnline: map['isOnline'] ?? false,
//       canChat: map['canChat'] ?? false,
//       premiumStart: parseTimestamp(map['premiumStart']),
//       premiumEnd: parseTimestamp(map['premiumEnd']),
//       lastActive: parseTimestamp(map['lastActive']),
//     );
//   }

//   UserModel copyWith({
//     String? uid,
//     String? name,
//     String? username,
//     String? email,
//     String? occupation,
//     String? educationLevel,
//     int? age,
//     String? religion,
//     String? location,
//     String? gender,
//     List<String>? profileImageUrls,
//     String? description,
//     bool? isPremium,
//     bool? isOnline,
//     bool? canChat,
//     DateTime? premiumStart,
//     DateTime? premiumEnd,
//     DateTime? lastActive,
//   }) {
//     return UserModel(
//       uid: uid ?? this.uid,
//       name: name ?? this.name,
//       username: username ?? this.username,
//       email: email ?? this.email,
//       occupation: occupation ?? this.occupation,
//       educationLevel: educationLevel ?? this.educationLevel,
//       age: age ?? this.age,
//       religion: religion ?? this.religion,
//       location: location ?? this.location,
//       gender: gender ?? this.gender,
//       profileImageUrls: profileImageUrls ?? this.profileImageUrls,
//       description: description ?? this.description,
//       isPremium: isPremium ?? this.isPremium,
//       isOnline: isOnline ?? this.isOnline,
//       canChat: canChat ?? this.canChat,
//       premiumStart: premiumStart ?? this.premiumStart,
//       premiumEnd: premiumEnd ?? this.premiumEnd,
//       lastActive: lastActive ?? this.lastActive,
//     );
//   }
// }



