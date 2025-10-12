import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ifenkem/models/storymodel.dart';
import 'package:ifenkem/screens/Chat_Screen.dart';
import 'package:ifenkem/screens/StoryViewerScreen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:ifenkem/models/user_model.dart';
import 'package:ifenkem/screens/details_screen.dart';
import 'package:ifenkem/screens/login_screen.dart';
import 'package:ifenkem/screens/register_screen.dart';
import 'package:ifenkem/screens/profile_screen.dart';
import 'package:ifenkem/providers/auth_provider.dart';
import 'package:ifenkem/widgets/InAppNotificationBanner.dart';
import 'package:ifenkem/services/LocalNotificationService.dart';
import 'package:ifenkem/utils/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String searchLocation = '';
  double minAge = 20;
  double maxAge = 60;
  String genderFilter = 'All';

  UserModel? loggedInUser;
  bool _isLoadingUser = true;

  late BannerAd _bannerAd;
  bool _isBannerLoaded = false;

  ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);

  Future<void> _pickAndUploadStory() async {
    if (loggedInUser == null) return;

    final ImagePicker picker = ImagePicker();
    final List<XFile>? images = await picker.pickMultiImage(imageQuality: 80);

    if (images == null || images.isEmpty) return;

    if (images.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can upload a maximum of 5 images.")),
      );
      return;
    }

    List<String> downloadUrls = [];

    for (var img in images) {
      final ref = FirebaseStorage.instance.ref().child(
        'stories/${loggedInUser!.uid}/${DateTime.now().millisecondsSinceEpoch}',
      );
      await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();
      downloadUrls.add(url);
    }

    // Save story to Firestore
    final storyDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(loggedInUser!.uid)
        .collection('stories')
        .doc();

    await storyDoc.set({
      'userId': loggedInUser!.uid,
      'userName': loggedInUser!.name,
      'location': loggedInUser!.location,
      'gender': loggedInUser!.gender,
      'imageUrls': downloadUrls,
      'timestamp': Timestamp.now(),
      'viewers': [],
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Story uploaded successfully!")),
    );
  }

  // ----------------- INTERSTITIAL AD -----------------
  InterstitialAd? _interstitialAd;
  int _profileTapCount = 0;

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-4557899423246596/3141661201',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (err) {
          _interstitialAd = null;
          Future.delayed(const Duration(seconds: 10), _loadInterstitialAd);
        },
      ),
    );
  }

  void _showInterstitialAd(VoidCallback onAdClosed) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadInterstitialAd();
          onAdClosed();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _loadInterstitialAd();
          onAdClosed();
        },
      );
      _interstitialAd!.show();
      _interstitialAd = null;
    } else {
      onAdClosed();
    }
  }

  Widget _buildStoriesBar() {
    return SizedBox(
      height: 100,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('stories')
            .where(
              'timestamp',
              isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(hours: 24)),
              ),
            )
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data!.docs.map((doc) {
            return StoryModel.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: stories.length + 1, // +1 for “Add Story” button
            itemBuilder: (context, index) {
              if (index == 0) {
                // Upload story button
                return GestureDetector(
                  onTap: () async {
                    await _pickAndUploadStory();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Column(
                      children: const [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey,
                          child: Icon(Icons.add, color: Colors.white, size: 30),
                        ),
                        SizedBox(height: 4),
                        Text("Your Story", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }

              final story = stories[index - 1];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(story: story),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.grey[300],
                        // ✅ WRAP NetworkImage IN TRY/CATCH
                        child: Builder(
                          builder: (context) {
                            try {
                              if (story.imageUrls.isNotEmpty) {
                                return ClipOval(
                                  child: Image.network(
                                    story.imageUrls[0],
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      // ✅ Fallback if network fails
                                      return const Icon(
                                        Icons.broken_image,
                                        color: Colors.white,
                                      );
                                    },
                                  ),
                                );
                              } else {
                                // ✅ Fallback for empty imageUrls
                                return const Icon(
                                  Icons.image,
                                  color: Colors.white,
                                );
                              }
                            } catch (e) {
                              // ✅ Catch any other errors
                              return const Icon(
                                Icons.error,
                                color: Colors.white,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        story.userName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------

  //  Added: Request notification permission after user reaches HomeScreen
  Future<void> _requestNotificationPermission() async {
    // 1️⃣ Ask Firebase Messaging directly (important for Android 13+)
    await FirebaseMessaging.instance.requestPermission();

    // 2️⃣ Ask OS-level permission (covers extra edge cases on iOS/Android)
    final status = await Permission.notification.status;
    if (status.isGranted) return;

    if (status.isDenied || status.isRestricted) {
      final granted = await Permission.notification.request();

      if (granted.isPermanentlyDenied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable notifications from Settings to receive updates.',
            ),
          ),
        );
      }
    }
  }

  //  End added section

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLoggedInUser();

    // Load Interstitial only for non-premium users
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!(authProvider.currentUser?.isPremium ?? false)) {
      _loadInterstitialAd();
    }

    //  START LISTENING FOR NEW MESSAGES ON HOMESCREEN
    final localService = Provider.of<LocalNotificationService>(
      context,
      listen: false,
    );
    if (authProvider.currentUser != null) {
      localService.startListening(authProvider.currentUser!.uid);
    } else {
      authProvider.addListener(() {
        final user = authProvider.currentUser;
        if (user != null) {
          localService.startListening(user.uid);
        }
      });
    }
    //  END
    if (authProvider.currentUser != null) {
      _requestNotificationPermission(); // ask only after login
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (loggedInUser != null) {
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(loggedInUser!.uid);

      if (state == AppLifecycleState.resumed) {
        userDoc.update({'isOnline': true});
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.detached) {
        userDoc.update({'isOnline': false});
      }
    }
  }

  Future<void> _loadLoggedInUser() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.fetchUserData();
      loggedInUser = authProvider.currentUser;
      isPremiumNotifier.value = loggedInUser?.isPremium ?? false;

      if (loggedInUser != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(loggedInUser!.uid)
            .update({'isOnline': true});
      }

      _loadBannerAd();
    } catch (e) {
      print("Error loading logged in user: $e");
    } finally {
      setState(() => _isLoadingUser = false);
    }
  }

  void _loadBannerAd() {
    if (loggedInUser != null && loggedInUser!.isPremium) return;

    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-4557899423246596/1620749877',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (_, __) => setState(() => _isBannerLoaded = false),
      ),
    );
    _bannerAd.load();
  }

  Future<void> _logout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();

    setState(() {
      loggedInUser = null;
      isPremiumNotifier.value = false;
    });
  }

  Future<void> _refreshProfiles() async {
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_isLoadingUser && loggedInUser != null && !loggedInUser!.isPremium) {
      _bannerAd.dispose();
      _interstitialAd?.dispose();
    }
    isPremiumNotifier.dispose();
    super.dispose();
  }

  /// ✅ ADDED: Toggle like/unlike and notification creation
  Future<void> _toggleLike(UserModel targetUser) async {
    if (loggedInUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login to like profiles.")),
      );
      return;
    }

    final currentUid = loggedInUser!.uid;
    final targetUid = targetUser.uid;

    // Path: likes/{targetUid}/received/{fromUid}
    final likeDocRef = FirebaseFirestore.instance
        .collection('likes')
        .doc(targetUid)
        .collection('received')
        .doc(currentUid);

    final likeDoc = await likeDocRef.get();

    if (likeDoc.exists) {
      // unlike -> delete the doc
      await likeDocRef.delete();
      // optionally write an "unlike" notification record (we'll not send push here)
      final notifRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc(); // auto id
      await notifRef.set({
        'to': targetUid,
        'from': currentUid,
        'type': 'unlike',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You unliked this profile.")),
        );
      }
    } else {
      // like -> create doc
      await likeDocRef.set({
        'fromUid': currentUid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Create a notification document that can be picked up by your
      // LocalNotificationService, Cloud Function, or any listener to deliver FCM.
      final notifRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc(); // auto id
      await notifRef.set({
        'to': targetUid,
        'from': currentUid,
        'type': 'like',
        'message': '${loggedInUser?.name ?? 'Someone'} liked your profile',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        // include senderUserId so client can fetch details and navigate
        'senderId': currentUid,
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Profile liked.")));
      }
    }

    // trigger UI rebuild
    setState(() {});
  }

  /// ✅ ADDED: helper to check if loggedInUser liked a target user
  Future<bool> _isLikedByMe(String targetUid) async {
    if (loggedInUser == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('likes')
        .doc(targetUid)
        .collection('received')
        .doc(loggedInUser!.uid)
        .get();
    return doc.exists;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Consumer<LocalNotificationService>(
      builder: (context, notifService, _) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: const Text("IfeNkem"),
            backgroundColor: AppTheme.primaryColor,
            actions: [
              if (loggedInUser == null) ...[
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  child: const Text(
                    "Register",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          onProfileUpdated: () async {
                            await context.read<AuthProvider>().fetchUserData();
                            final updatedUser = context
                                .read<AuthProvider>()
                                .currentUser;
                            if (updatedUser != null) {
                              isPremiumNotifier.value = updatedUser.isPremium;
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "View Profile",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _logout,
                  child: const Text(
                    "Logout",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _refreshProfiles,
                child: Column(
                  children: [
                    _buildSearchBar(),
                    _buildGenderFilter(),
                    _buildStoriesBar(),

                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: isPremiumNotifier,
                        builder: (context, isPremium, _) {
                          return StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: AppTheme.primaryColor,
                                  ),
                                );
                              }
                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return const Center(
                                  child: Text(
                                    "No profiles found",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              final allProfiles = snapshot.data!.docs.map((
                                doc,
                              ) {
                                final data = doc.data() as Map<String, dynamic>;
                                return UserModel.fromMap(data);
                              }).toList();

                              final filteredProfiles = allProfiles.where((
                                user,
                              ) {
                                final isProfileComplete =
                                    user.name.isNotEmpty &&
                                    user.occupation.isNotEmpty &&
                                    user.educationLevel.isNotEmpty &&
                                    user.religion.isNotEmpty &&
                                    user.location.isNotEmpty &&
                                    user.description.isNotEmpty &&
                                    user.gender.isNotEmpty &&
                                    user.profileImageUrls.length == 5 &&
                                    user.age >= 20;

                                final matchesGender =
                                    (genderFilter == 'All' ||
                                    user.gender.toLowerCase() ==
                                        genderFilter.toLowerCase());

                                return isProfileComplete &&
                                    (searchLocation.isEmpty ||
                                        user.location.toLowerCase().contains(
                                          searchLocation.toLowerCase(),
                                        )) &&
                                    (user.age >= minAge &&
                                        user.age <= maxAge) &&
                                    matchesGender;
                              }).toList();

                              return GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: 320,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                itemCount: filteredProfiles.length,
                                itemBuilder: (context, index) {
                                  final user = filteredProfiles[index];
                                  return GestureDetector(
                                    onTap: () {
                                      final isPremium =
                                          loggedInUser?.isPremium ?? false;

                                      void navigateToDetails() {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DetailsScreen(user: user),
                                          ),
                                        );
                                      }

                                      if (!isPremium) {
                                        _profileTapCount++;
                                        if (_profileTapCount % 5 == 0) {
                                          _showInterstitialAd(
                                            navigateToDetails,
                                          );
                                        } else {
                                          navigateToDetails();
                                        }
                                      } else {
                                        navigateToDetails();
                                      }
                                    },
                                    child: Card(
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Stack(
                                              children: [
                                                user.profileImageUrls.isNotEmpty
                                                    ? ClipRRect(
                                                        borderRadius:
                                                            const BorderRadius.vertical(
                                                              top:
                                                                  Radius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                        child: Image.network(
                                                          user.profileImageUrls[0],
                                                          fit: BoxFit.contain,
                                                          width:
                                                              double.infinity,
                                                          height: 180,
                                                        ),
                                                      )
                                                    : Container(
                                                        color: AppTheme
                                                            .accentColor,
                                                      ),
                                                Positioned(
                                                  top: 8,
                                                  left: 8,
                                                  child: CircleAvatar(
                                                    radius: 8,
                                                    backgroundColor:
                                                        user.isOnline
                                                        ? Colors.green
                                                        : Colors.grey,
                                                  ),
                                                ),
                                                if (user.isPremium)
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme
                                                            .primaryColor,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        "Premium",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                /// ✅ ADDED: Like/Unlike button in top-right area (above View Details)
                                                Positioned(
                                                  top: 8,
                                                  right: user.isPremium
                                                      ? 70
                                                      : 8,
                                                  child: Builder(
                                                    builder: (ctx) {
                                                      // hide like button for self or when not logged-in
                                                      if (loggedInUser ==
                                                              null ||
                                                          loggedInUser!.uid ==
                                                              user.uid) {
                                                        return const SizedBox();
                                                      }

                                                      return FutureBuilder<
                                                        bool
                                                      >(
                                                        future: _isLikedByMe(
                                                          user.uid,
                                                        ),
                                                        builder: (context, snap) {
                                                          final liked =
                                                              snap.data ??
                                                              false;
                                                          return GestureDetector(
                                                            onTap: () async {
                                                              await _toggleLike(
                                                                user,
                                                              );
                                                            },
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .white
                                                                    .withOpacity(
                                                                      0.9,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                          0.05,
                                                                        ),
                                                                    blurRadius:
                                                                        6,
                                                                    offset:
                                                                        const Offset(
                                                                          0,
                                                                          2,
                                                                        ),
                                                                  ),
                                                                ],
                                                              ),
                                                              child: Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Icon(
                                                                    liked
                                                                        ? Icons
                                                                              .favorite
                                                                        : Icons
                                                                              .favorite_border,
                                                                    size: 18,
                                                                    color: liked
                                                                        ? Colors
                                                                              .red
                                                                        : AppTheme
                                                                              .primaryColor,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 6,
                                                                  ),
                                                                  Text(
                                                                    liked
                                                                        ? "Liked"
                                                                        : "Like",
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                              children: [
                                                Text(
                                                  user.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Text(
                                                  "${user.age} years old",
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    final isPremium =
                                                        loggedInUser
                                                            ?.isPremium ??
                                                        false;

                                                    void navigateToDetails() {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              DetailsScreen(
                                                                user: user,
                                                              ),
                                                        ),
                                                      );
                                                    }

                                                    if (!isPremium) {
                                                      _profileTapCount++;
                                                      if (_profileTapCount %
                                                              5 ==
                                                          0) {
                                                        _showInterstitialAd(
                                                          navigateToDetails,
                                                        );
                                                      } else {
                                                        navigateToDetails();
                                                      }
                                                    } else {
                                                      navigateToDetails();
                                                    }
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppTheme.primaryColor,
                                                    minimumSize: const Size(
                                                      double.infinity,
                                                      36,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    "View Details",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ------------------ In-App Notification Banner ------------------
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
          bottomNavigationBar:
              (_isBannerLoaded && !(loggedInUser?.isPremium ?? false))
              ? Container(
                  color: Colors.white,
                  height: _bannerAd.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd),
                )
              : null,
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search by Location",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
        ),
        onChanged: (val) => setState(() => searchLocation = val),
      ),
    );
  }

  Widget _buildGenderFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
      child: Row(
        children: [
          const Text("Filter by Gender: "),
          DropdownButton<String>(
            value: genderFilter,
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (val) => setState(() => genderFilter = val ?? 'All'),
          ),
        ],
      ),
    );
  }
}



// import 'dart:async';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:ifenkem/screens/Chat_Screen.dart';
// import 'package:provider/provider.dart';
// import 'package:ifenkem/models/user_model.dart';
// import 'package:ifenkem/screens/details_screen.dart';
// import 'package:ifenkem/screens/login_screen.dart';
// import 'package:ifenkem/screens/register_screen.dart';
// import 'package:ifenkem/screens/profile_screen.dart';
// import 'package:ifenkem/providers/auth_provider.dart';
// import 'package:ifenkem/widgets/InAppNotificationBanner.dart';
// import 'package:ifenkem/services/LocalNotificationService.dart';
// import 'package:ifenkem/utils/app_theme.dart';
// import 'package:permission_handler/permission_handler.dart';

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
//   String searchLocation = '';
//   double minAge = 20;
//   double maxAge = 60;
//   String genderFilter = 'All';

//   UserModel? loggedInUser;
//   bool _isLoadingUser = true;

//   late BannerAd _bannerAd;
//   bool _isBannerLoaded = false;

//   ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);

//   // ----------------- INTERSTITIAL AD -----------------
//   InterstitialAd? _interstitialAd;
//   int _profileTapCount = 0;

//   void _loadInterstitialAd() {
//     InterstitialAd.load(
//       adUnitId: 'ca-app-pub-4557899423246596/3141661201',
//       request: const AdRequest(),
//       adLoadCallback: InterstitialAdLoadCallback(
//         onAdLoaded: (ad) => _interstitialAd = ad,
//         onAdFailedToLoad: (err) {
//           _interstitialAd = null;
//           Future.delayed(const Duration(seconds: 10), _loadInterstitialAd);
//         },
//       ),
//     );
//   }

//   void _showInterstitialAd(VoidCallback onAdClosed) {
//     if (_interstitialAd != null) {
//       _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
//         onAdDismissedFullScreenContent: (ad) {
//           ad.dispose();
//           _loadInterstitialAd();
//           onAdClosed();
//         },
//         onAdFailedToShowFullScreenContent: (ad, err) {
//           ad.dispose();
//           _loadInterstitialAd();
//           onAdClosed();
//         },
//       );
//       _interstitialAd!.show();
//       _interstitialAd = null;
//     } else {
//       onAdClosed();
//     }
//   }
//   // ---------------------------------------------------

//   //  Added: Request notification permission after user reaches HomeScreen
//   Future<void> _requestNotificationPermission() async {
//     final status = await Permission.notification.status;
//     if (status.isGranted) return;

//     if (status.isDenied || status.isRestricted) {
//       final granted = await Permission.notification.request();

//       if (granted.isPermanentlyDenied && mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text(
//               'Please enable notifications from Settings to receive updates.',
//             ),
//           ),
//         );
//       }
//     }
//   }

//   //  End added section

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _loadLoggedInUser();

//     // Load Interstitial only for non-premium users
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     if (!(authProvider.currentUser?.isPremium ?? false)) {
//       _loadInterstitialAd();
//     }

//     //  START LISTENING FOR NEW MESSAGES ON HOMESCREEN
//     final localService = Provider.of<LocalNotificationService>(
//       context,
//       listen: false,
//     );
//     if (authProvider.currentUser != null) {
//       localService.startListening(authProvider.currentUser!.uid);
//     } else {
//       authProvider.addListener(() {
//         final user = authProvider.currentUser;
//         if (user != null) {
//           localService.startListening(user.uid);
//         }
//       });
//     }
//     //  END
//     if (authProvider.currentUser != null) {
//       _requestNotificationPermission(); // ask only after login
//     }
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (loggedInUser != null) {
//       final userDoc = FirebaseFirestore.instance
//           .collection('users')
//           .doc(loggedInUser!.uid);

//       if (state == AppLifecycleState.resumed) {
//         userDoc.update({'isOnline': true});
//       } else if (state == AppLifecycleState.paused ||
//           state == AppLifecycleState.inactive ||
//           state == AppLifecycleState.detached) {
//         userDoc.update({'isOnline': false});
//       }
//     }
//   }

//   Future<void> _loadLoggedInUser() async {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       await authProvider.fetchUserData();
//       loggedInUser = authProvider.currentUser;
//       isPremiumNotifier.value = loggedInUser?.isPremium ?? false;

//       if (loggedInUser != null) {
//         FirebaseFirestore.instance
//             .collection('users')
//             .doc(loggedInUser!.uid)
//             .update({'isOnline': true});
//       }

//       _loadBannerAd();
//     } catch (e) {
//       print("Error loading logged in user: $e");
//     } finally {
//       setState(() => _isLoadingUser = false);
//     }
//   }

//   void _loadBannerAd() {
//     if (loggedInUser != null && loggedInUser!.isPremium) return;

//     _bannerAd = BannerAd(
//       adUnitId: 'ca-app-pub-4557899423246596/1620749877',
//       size: AdSize.banner,
//       request: const AdRequest(),
//       listener: BannerAdListener(
//         onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
//         onAdFailedToLoad: (_, __) => setState(() => _isBannerLoaded = false),
//       ),
//     );
//     _bannerAd.load();
//   }

//   Future<void> _logout() async {
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     await authProvider.signOut();

//     setState(() {
//       loggedInUser = null;
//       isPremiumNotifier.value = false;
//     });
//   }

//   Future<void> _refreshProfiles() async {
//     setState(() {});
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     if (!_isLoadingUser && loggedInUser != null && !loggedInUser!.isPremium) {
//       _bannerAd.dispose();
//       _interstitialAd?.dispose();
//     }
//     isPremiumNotifier.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isLoadingUser) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }

//     return Consumer<LocalNotificationService>(
//       builder: (context, notifService, _) {
//         return Scaffold(
//           backgroundColor: AppTheme.backgroundColor,
//           appBar: AppBar(
//             title: const Text("IfeNkem"),
//             backgroundColor: AppTheme.primaryColor,
//             actions: [
//               if (loggedInUser == null) ...[
//                 TextButton(
//                   onPressed: () {
//                     Navigator.push(
//                       context,
//                       MaterialPageRoute(builder: (_) => const RegisterScreen()),
//                     );
//                   },
//                   child: const Text(
//                     "Register",
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 TextButton(
//                   onPressed: () {
//                     Navigator.push(
//                       context,
//                       MaterialPageRoute(builder: (_) => const LoginScreen()),
//                     );
//                   },
//                   child: const Text(
//                     "Login",
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//               ] else ...[
//                 TextButton(
//                   onPressed: () {
//                     Navigator.push(
//                       context,
//                       MaterialPageRoute(
//                         builder: (_) => ProfileScreen(
//                           onProfileUpdated: () async {
//                             await context.read<AuthProvider>().fetchUserData();
//                             final updatedUser = context
//                                 .read<AuthProvider>()
//                                 .currentUser;
//                             if (updatedUser != null) {
//                               isPremiumNotifier.value = updatedUser.isPremium;
//                               setState(() {});
//                             }
//                           },
//                         ),
//                       ),
//                     );
//                   },
//                   child: const Text(
//                     "View Profile",
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 TextButton(
//                   onPressed: _logout,
//                   child: const Text(
//                     "Logout",
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//           body: Stack(
//             children: [
//               RefreshIndicator(
//                 onRefresh: _refreshProfiles,
//                 child: Column(
//                   children: [
//                     _buildSearchBar(),
//                     _buildGenderFilter(),
//                     Expanded(
//                       child: ValueListenableBuilder<bool>(
//                         valueListenable: isPremiumNotifier,
//                         builder: (context, isPremium, _) {
//                           return StreamBuilder<QuerySnapshot>(
//                             stream: FirebaseFirestore.instance
//                                 .collection('users')
//                                 .snapshots(),
//                             builder: (context, snapshot) {
//                               if (snapshot.connectionState ==
//                                   ConnectionState.waiting) {
//                                 return const Center(
//                                   child: CircularProgressIndicator(
//                                     color: AppTheme.primaryColor,
//                                   ),
//                                 );
//                               }
//                               if (!snapshot.hasData ||
//                                   snapshot.data!.docs.isEmpty) {
//                                 return const Center(
//                                   child: Text(
//                                     "No profiles found",
//                                     style: TextStyle(color: Colors.grey),
//                                   ),
//                                 );
//                               }

//                               final allProfiles = snapshot.data!.docs.map((
//                                 doc,
//                               ) {
//                                 final data = doc.data() as Map<String, dynamic>;
//                                 return UserModel.fromMap(data);
//                               }).toList();

//                               final filteredProfiles = allProfiles.where((
//                                 user,
//                               ) {
//                                 final isProfileComplete =
//                                     user.name.isNotEmpty &&
//                                     user.occupation.isNotEmpty &&
//                                     user.educationLevel.isNotEmpty &&
//                                     user.religion.isNotEmpty &&
//                                     user.location.isNotEmpty &&
//                                     user.description.isNotEmpty &&
//                                     user.gender.isNotEmpty &&
//                                     user.profileImageUrls.length == 5 &&
//                                     user.age >= 20;

//                                 final matchesGender =
//                                     (genderFilter == 'All' ||
//                                     user.gender.toLowerCase() ==
//                                         genderFilter.toLowerCase());

//                                 return isProfileComplete &&
//                                     (searchLocation.isEmpty ||
//                                         user.location.toLowerCase().contains(
//                                           searchLocation.toLowerCase(),
//                                         )) &&
//                                     (user.age >= minAge &&
//                                         user.age <= maxAge) &&
//                                     matchesGender;
//                               }).toList();

//                               return GridView.builder(
//                                 padding: const EdgeInsets.all(12),
//                                 gridDelegate:
//                                     const SliverGridDelegateWithFixedCrossAxisCount(
//                                       crossAxisCount: 2,
//                                       mainAxisExtent: 320,
//                                       crossAxisSpacing: 12,
//                                       mainAxisSpacing: 12,
//                                     ),
//                                 itemCount: filteredProfiles.length,
//                                 itemBuilder: (context, index) {
//                                   final user = filteredProfiles[index];
//                                   return GestureDetector(
//                                     onTap: () {
//                                       final isPremium =
//                                           loggedInUser?.isPremium ?? false;

//                                       void navigateToDetails() {
//                                         Navigator.push(
//                                           context,
//                                           MaterialPageRoute(
//                                             builder: (_) =>
//                                                 DetailsScreen(user: user),
//                                           ),
//                                         );
//                                       }

//                                       if (!isPremium) {
//                                         _profileTapCount++;
//                                         if (_profileTapCount % 5 == 0) {
//                                           _showInterstitialAd(
//                                             navigateToDetails,
//                                           );
//                                         } else {
//                                           navigateToDetails();
//                                         }
//                                       } else {
//                                         navigateToDetails();
//                                       }
//                                     },
//                                     child: Card(
//                                       color: Colors.white,
//                                       shape: RoundedRectangleBorder(
//                                         borderRadius: BorderRadius.circular(12),
//                                       ),
//                                       elevation: 4,
//                                       child: Column(
//                                         children: [
//                                           Expanded(
//                                             child: Stack(
//                                               children: [
//                                                 user.profileImageUrls.isNotEmpty
//                                                     ? ClipRRect(
//                                                         borderRadius:
//                                                             const BorderRadius.vertical(
//                                                               top:
//                                                                   Radius.circular(
//                                                                     12,
//                                                                   ),
//                                                             ),
//                                                         child: Image.network(
//                                                           user.profileImageUrls[0],
//                                                           fit: BoxFit.contain,
//                                                           width:
//                                                               double.infinity,
//                                                           height: 180,
//                                                         ),
//                                                       )
//                                                     : Container(
//                                                         color: AppTheme
//                                                             .accentColor,
//                                                       ),
//                                                 Positioned(
//                                                   top: 8,
//                                                   left: 8,
//                                                   child: CircleAvatar(
//                                                     radius: 8,
//                                                     backgroundColor:
//                                                         user.isOnline
//                                                         ? Colors.green
//                                                         : Colors.grey,
//                                                   ),
//                                                 ),
//                                                 if (user.isPremium)
//                                                   Positioned(
//                                                     top: 8,
//                                                     right: 8,
//                                                     child: Container(
//                                                       padding:
//                                                           const EdgeInsets.symmetric(
//                                                             horizontal: 6,
//                                                             vertical: 2,
//                                                           ),
//                                                       decoration: BoxDecoration(
//                                                         color: AppTheme
//                                                             .primaryColor,
//                                                         borderRadius:
//                                                             BorderRadius.circular(
//                                                               8,
//                                                             ),
//                                                       ),
//                                                       child: const Text(
//                                                         "Premium",
//                                                         style: TextStyle(
//                                                           fontSize: 12,
//                                                           color: Colors.white,
//                                                         ),
//                                                       ),
//                                                     ),
//                                                   ),
//                                               ],
//                                             ),
//                                           ),
//                                           Padding(
//                                             padding: const EdgeInsets.all(8.0),
//                                             child: Column(
//                                               children: [
//                                                 Text(
//                                                   user.name,
//                                                   style: const TextStyle(
//                                                     fontWeight: FontWeight.bold,
//                                                     color: Colors.black,
//                                                   ),
//                                                 ),
//                                                 Text(
//                                                   "${user.age} years old",
//                                                   style: const TextStyle(
//                                                     color: Colors.grey,
//                                                   ),
//                                                 ),
//                                                 const SizedBox(height: 6),
//                                                 ElevatedButton(
//                                                   onPressed: () {
//                                                     final isPremium =
//                                                         loggedInUser
//                                                             ?.isPremium ??
//                                                         false;

//                                                     void navigateToDetails() {
//                                                       Navigator.push(
//                                                         context,
//                                                         MaterialPageRoute(
//                                                           builder: (_) =>
//                                                               DetailsScreen(
//                                                                 user: user,
//                                                               ),
//                                                         ),
//                                                       );
//                                                     }

//                                                     if (!isPremium) {
//                                                       _profileTapCount++;
//                                                       if (_profileTapCount %
//                                                               5 ==
//                                                           0) {
//                                                         _showInterstitialAd(
//                                                           navigateToDetails,
//                                                         );
//                                                       } else {
//                                                         navigateToDetails();
//                                                       }
//                                                     } else {
//                                                       navigateToDetails();
//                                                     }
//                                                   },
//                                                   style: ElevatedButton.styleFrom(
//                                                     backgroundColor:
//                                                         AppTheme.primaryColor,
//                                                     minimumSize: const Size(
//                                                       double.infinity,
//                                                       36,
//                                                     ),
//                                                     shape: RoundedRectangleBorder(
//                                                       borderRadius:
//                                                           BorderRadius.circular(
//                                                             8,
//                                                           ),
//                                                     ),
//                                                   ),
//                                                   child: const Text(
//                                                     "View Details",
//                                                     style: TextStyle(
//                                                       color: Colors.white,
//                                                     ),
//                                                   ),
//                                                 ),
//                                               ],
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   );
//                                 },
//                               );
//                             },
//                           );
//                         },
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               // ------------------ In-App Notification Banner ------------------
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
//           bottomNavigationBar:
//               (_isBannerLoaded && !(loggedInUser?.isPremium ?? false))
//               ? Container(
//                   color: Colors.white,
//                   height: _bannerAd.size.height.toDouble(),
//                   child: AdWidget(ad: _bannerAd),
//                 )
//               : null,
//         );
//       },
//     );
//   }

//   Widget _buildSearchBar() {
//     return Padding(
//       padding: const EdgeInsets.all(8.0),
//       child: TextField(
//         decoration: InputDecoration(
//           hintText: "Search by Location",
//           border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
//           filled: true,
//           fillColor: Colors.white,
//           prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
//         ),
//         onChanged: (val) => setState(() => searchLocation = val),
//       ),
//     );
//   }

//   Widget _buildGenderFilter() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
//       child: Row(
//         children: [
//           const Text("Filter by Gender: "),
//           DropdownButton<String>(
//             value: genderFilter,
//             items: const [
//               DropdownMenuItem(value: 'All', child: Text('All')),
//               DropdownMenuItem(value: 'Male', child: Text('Male')),
//               DropdownMenuItem(value: 'Female', child: Text('Female')),
//             ],
//             onChanged: (val) => setState(() => genderFilter = val ?? 'All'),
//           ),
//         ],
//       ),
//     );
//   }
// }


