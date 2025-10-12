import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; //  FCM import
import '../models/user_model.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  bool get isLoggedIn => _auth.currentUser != null;

  Stream<UserModel?> get userStream {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        final user = UserModel.fromMap(doc.data()!);
        _currentUser = user;
        return user;
      }
      return null;
    });
  }

  /// ✅ Update FCM token for user and save to UserModel locally
  Future<void> _updateFcmToken(String uid) async {
    final token = await FirebaseMessaging.instance.getToken(); //  fetch token
    if (token != null) {
      await _firestore.collection('users').doc(uid).update({
        'fcmToken': token, // ✅ store token in Firestore
      });
      debugPrint("🟢 FCM token updated for user $uid: $token"); //  log

      // ✅ Update local UserModel
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(fcmToken: token);
        notifyListeners();
      }
    }
  }

  /// Register user
  Future<void> registerUser({
    required String name,
    required String username,
    required String email,
    required String password,
    required int age,
    String gender = "Not Specified",
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;

    final newUser = UserModel(
      uid: uid,
      name: name,
      username: username,
      email: email,
      occupation: "",
      educationLevel: "",
      age: age,
      religion: "",
      location: "",
      gender: gender,
      profileImageUrls: [],
      description: "",
      isPremium: false,
      isOnline: true,
      canChat: false,
    );

    await _firestore.collection('users').doc(uid).set(newUser.toMap());

    _currentUser = newUser;
    notifyListeners();

    await _updateFcmToken(uid); // ✅ Update FCM token after registration
  }

  /// Login user (with email OR username)
  Future<void> loginUser({
    required String identifier, // can be email OR username
    required String password,
  }) async {
    String emailToUse = identifier;

    if (!identifier.contains('@')) {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: identifier)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw Exception("No user found with that username");
      }

      emailToUse = query.docs.first['email'];
    }

    await _auth.signInWithEmailAndPassword(
      email: emailToUse,
      password: password,
    );

    await fetchUserData();

    if (_currentUser != null) {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'isOnline': true,
      });
      _currentUser = _currentUser!.copyWith(isOnline: true);
      notifyListeners();

      await _updateFcmToken(
        _currentUser!.uid,
      ); // ✅ Update FCM token after login
    }
  }

  /// Fetch once
  Future<void> fetchUserData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      _currentUser = UserModel.fromMap(doc.data()!);
      notifyListeners();
    }
  }

  /// Update to Premium
  Future<void> updatePremiumStatus() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final oneMonthLater = now.add(const Duration(days: 30));

    await _firestore.collection('users').doc(uid).update({
      'isPremium': true,
      'canChat': true,
      'premiumStart': Timestamp.fromDate(now),
      'premiumEnd': Timestamp.fromDate(oneMonthLater),
    });

    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        isPremium: true,
        canChat: true,
        premiumStart: now,
        premiumEnd: oneMonthLater,
      );
      notifyListeners();
    }
  }

  /// Sign out
  Future<void> signOut() async {
    if (_currentUser != null) {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'isOnline': false,
      });
    }

    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  /// ✅ Listen for token refresh and auto-update Firestore & local UserModel
  void listenForFcmTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('users').doc(uid).update({
          'fcmToken': token, //  store updated token
        });
        debugPrint("🟢 FCM token refreshed and updated: $token");

        //  Update local model
        if (_currentUser != null) {
          _currentUser = _currentUser!.copyWith(fcmToken: token);
          notifyListeners();
        }
      }
    });
  }
}



// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../models/user_model.dart';

// class AuthProvider with ChangeNotifier {
//   final FirebaseAuth _auth = FirebaseAuth.instance;
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;

//   UserModel? _currentUser;
//   UserModel? get currentUser => _currentUser;

//   bool get isLoggedIn => _auth.currentUser != null;

//   Stream<UserModel?> get userStream {
//     final uid = _auth.currentUser?.uid;
//     if (uid == null) return const Stream.empty();
//     return _firestore.collection('users').doc(uid).snapshots().map((doc) {
//       if (doc.exists) {
//         final user = UserModel.fromMap(doc.data()!);
//         _currentUser = user;
//         return user;
//       }
//       return null;
//     });
//   }

//   /// Register user
//   Future<void> registerUser({
//     required String name,
//     required String username,
//     required String email,
//     required String password,
//     required int age,
//     String gender = "Not Specified",
//   }) async {
//     final credential = await _auth.createUserWithEmailAndPassword(
//       email: email,
//       password: password,
//     );

//     final uid = credential.user!.uid;

//     final newUser = UserModel(
//       uid: uid,
//       name: name,
//       username: username,
//       email: email,
//       occupation: "",
//       educationLevel: "",
//       age: age,
//       religion: "",
//       location: "",
//       gender: gender,
//       profileImageUrls: [],
//       description: "",
//       isPremium: false,
//       isOnline: true,
//       canChat: false,
//     );

//     await _firestore.collection('users').doc(uid).set(newUser.toMap());

//     _currentUser = newUser;
//     notifyListeners();
//   }

//   /// Login user (with email OR username)
//   Future<void> loginUser({
//     required String identifier, // can be email OR username
//     required String password,
//   }) async {
//     String emailToUse = identifier;

//     if (!identifier.contains('@')) {
//       final query = await _firestore
//           .collection('users')
//           .where('username', isEqualTo: identifier)
//           .limit(1)
//           .get();

//       if (query.docs.isEmpty) {
//         throw Exception("No user found with that username");
//       }

//       emailToUse = query.docs.first['email'];
//     }

//     await _auth.signInWithEmailAndPassword(
//       email: emailToUse,
//       password: password,
//     );

//     await fetchUserData();

//     if (_currentUser != null) {
//       await _firestore.collection('users').doc(_currentUser!.uid).update({
//         'isOnline': true,
//       });
//       _currentUser = _currentUser!.copyWith(isOnline: true);
//       notifyListeners();
//     }
//   }

//   /// Fetch once
//   Future<void> fetchUserData() async {
//     final uid = _auth.currentUser?.uid;
//     if (uid == null) return;

//     final doc = await _firestore.collection('users').doc(uid).get();
//     if (doc.exists) {
//       _currentUser = UserModel.fromMap(doc.data()!);
//       notifyListeners();
//     }
//   }

//   /// Update to Premium
//   Future<void> updatePremiumStatus() async {
//     final uid = _auth.currentUser?.uid;
//     if (uid == null) return;

//     final now = DateTime.now();
//     final oneMonthLater = now.add(const Duration(days: 30));

//     await _firestore.collection('users').doc(uid).update({
//       'isPremium': true,
//       'canChat': true,
//       'premiumStart': Timestamp.fromDate(now),
//       'premiumEnd': Timestamp.fromDate(oneMonthLater),
//     });

//     if (_currentUser != null) {
//       _currentUser = _currentUser!.copyWith(
//         isPremium: true,
//         canChat: true,
//         premiumStart: now,
//         premiumEnd: oneMonthLater,
//       );
//       notifyListeners();
//     }
//   }

//   /// Sign out
//   Future<void> signOut() async {
//     if (_currentUser != null) {
//       await _firestore.collection('users').doc(_currentUser!.uid).update({
//         'isOnline': false,
//       });
//     }

//     await _auth.signOut();
//     _currentUser = null;
//     notifyListeners();
//   }
// }

