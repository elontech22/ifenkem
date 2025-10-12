import 'dart:ui'; // 🟢 for blur effect
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:ifenkem/screens/PremiumScreen.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/login_screen.dart';
import '../utils/app_theme.dart';

class DetailsScreen extends StatefulWidget {
  final UserModel user;
  final bool fromLikeNotification; // 🟢 Added: check if opened from like

  const DetailsScreen({
    super.key,
    required this.user,
    this.fromLikeNotification = false, // 🟢 Default false
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!(authProvider.currentUser?.isPremium ?? false)) {
      _loadBannerAd();
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-4557899423246596/1620749877',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (_, __) => setState(() => _isBannerLoaded = false),
      ),
    );
    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final viewer = authProvider.currentUser;
    final isPremium = viewer?.isPremium ?? false;

    //  If user opened from like notification and is not premium, enable blur
    final shouldBlur = widget.fromLikeNotification && !isPremium;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user.name),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Profile Carousel
                      CarouselSlider(
                        options: CarouselOptions(
                          height: 300,
                          enlargeCenterPage: true,
                        ),
                        items: widget.user.profileImageUrls.map((url) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 200,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey,
                                  child: const Icon(
                                    Icons.person,
                                    size: 100,
                                    color: Colors.white,
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // User Info
                      ListTile(
                        title: const Text("Name"),
                        subtitle: Text(widget.user.name),
                      ),
                      ListTile(
                        title: const Text("Age"),
                        subtitle: Text("${widget.user.age}"),
                      ),
                      ListTile(
                        title: const Text("Occupation"),
                        subtitle: Text(widget.user.occupation),
                      ),
                      ListTile(
                        title: const Text("Religion"),
                        subtitle: Text(widget.user.religion),
                      ),
                      ListTile(
                        title: const Text("Location"),
                        subtitle: Text(widget.user.location),
                      ),
                      ListTile(
                        title: const Text("Education"),
                        subtitle: Text(widget.user.educationLevel),
                      ),
                      ListTile(
                        title: const Text("About"),
                        subtitle: Text(widget.user.description),
                      ),
                      const SizedBox(height: 20),

                      // Chat / Upgrade Button
                      ElevatedButton.icon(
                        onPressed: () {
                          if (viewer == null) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Authentication Required"),
                                content: const Text(
                                  "Please log in to chat or upgrade to Premium.",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const LoginScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text("Login"),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          if (!(viewer.isPremium)) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Premium Required"),
                                content: const Text(
                                  "You must be a premium user to chat.",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const PremiumScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text("Upgrade to Premium"),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(peerUser: widget.user),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text("Chat / Upgrade"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.buttonColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 🟢 BLUR OVERLAY for non-premium users who opened from like notification
          if (shouldBlur)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, size: 80, color: Colors.white),
                        const SizedBox(height: 20),
                        const Text(
                          "Unlock this profile",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Upgrade to Premium to view full details",
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pinkAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PremiumScreen(),
                              ),
                            );
                          },
                          child: const Text("Upgrade Now"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: (!isPremium && _isBannerLoaded)
          ? Container(
              color: Colors.white,
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : null,
    );
  }
}



// import 'package:carousel_slider/carousel_slider.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:provider/provider.dart';
// import 'package:ifenkem/screens/PremiumScreen.dart';
// import '../models/user_model.dart';
// import '../providers/auth_provider.dart';
// import '../screens/chat_screen.dart';
// import '../screens/login_screen.dart';
// import '../utils/app_theme.dart';

// class DetailsScreen extends StatefulWidget {
//   final UserModel user;

//   const DetailsScreen({super.key, required this.user});

//   @override
//   State<DetailsScreen> createState() => _DetailsScreenState();
// }

// class _DetailsScreenState extends State<DetailsScreen> {
//   BannerAd? _bannerAd;
//   bool _isBannerLoaded = false;

//   @override
//   void initState() {
//     super.initState();
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);

//     // Load banner ad only if user is NOT premium
//     if (!(authProvider.currentUser?.isPremium ?? false)) {
//       _loadBannerAd();
//     }
//   }

//   void _loadBannerAd() {
//     _bannerAd = BannerAd(
//       adUnitId: 'ca-app-pub-4557899423246596/1620749877',
//       size: AdSize.banner,
//       request: const AdRequest(),
//       listener: BannerAdListener(
//         onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
//         onAdFailedToLoad: (_, __) => setState(() => _isBannerLoaded = false),
//       ),
//     );
//     _bannerAd!.load();
//   }

//   @override
//   void dispose() {
//     _bannerAd?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
//     final viewer = authProvider.currentUser;

//     final isPremium = viewer?.isPremium ?? false;

//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.user.name),
//         backgroundColor: AppTheme.primaryColor,
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: SingleChildScrollView(
//               child: Column(
//                 children: [
//                   // Profile Carousel
//                   CarouselSlider(
//                     options: CarouselOptions(
//                       height: 300,
//                       enlargeCenterPage: true,
//                     ),
//                     items: widget.user.profileImageUrls.map((url) {
//                       return ClipRRect(
//                         borderRadius: BorderRadius.circular(12),
//                         child: Image.network(
//                           url,
//                           fit: BoxFit.contain,
//                           width: double.infinity,
//                           height: 200,
//                           loadingBuilder: (context, child, loadingProgress) {
//                             if (loadingProgress == null) return child;
//                             return const Center(
//                               child: CircularProgressIndicator(),
//                             );
//                           },
//                           errorBuilder: (context, error, stackTrace) {
//                             return Container(
//                               color: Colors.grey,
//                               child: const Icon(
//                                 Icons.person,
//                                 size: 100,
//                                 color: Colors.white,
//                               ),
//                             );
//                           },
//                         ),
//                       );
//                     }).toList(),
//                   ),
//                   const SizedBox(height: 12),

//                   // User Info
//                   ListTile(
//                     title: const Text("Name"),
//                     subtitle: Text(widget.user.name),
//                   ),
//                   ListTile(
//                     title: const Text("Age"),
//                     subtitle: Text("${widget.user.age}"),
//                   ),
//                   ListTile(
//                     title: const Text("Occupation"),
//                     subtitle: Text(widget.user.occupation),
//                   ),
//                   ListTile(
//                     title: const Text("Religion"),
//                     subtitle: Text(widget.user.religion),
//                   ),
//                   ListTile(
//                     title: const Text("Location"),
//                     subtitle: Text(widget.user.location),
//                   ),
//                   ListTile(
//                     title: const Text("Education"),
//                     subtitle: Text(widget.user.educationLevel),
//                   ),
//                   ListTile(
//                     title: const Text("About"),
//                     subtitle: Text(widget.user.description),
//                   ),
//                   const SizedBox(height: 20),

//                   // Chat / Upgrade Button
//                   ElevatedButton.icon(
//                     onPressed: () {
//                       if (viewer == null) {
//                         showDialog(
//                           context: context,
//                           builder: (_) => AlertDialog(
//                             title: const Text("Authentication Required"),
//                             content: const Text(
//                               "Please log in to chat or upgrade to Premium.",
//                             ),
//                             actions: [
//                               TextButton(
//                                 onPressed: () => Navigator.pop(context),
//                                 child: const Text("Cancel"),
//                               ),
//                               TextButton(
//                                 onPressed: () {
//                                   Navigator.pop(context);
//                                   Navigator.push(
//                                     context,
//                                     MaterialPageRoute(
//                                       builder: (_) => const LoginScreen(),
//                                     ),
//                                   );
//                                 },
//                                 child: const Text("Login"),
//                               ),
//                             ],
//                           ),
//                         );
//                         return;
//                       }

//                       if (!(viewer.isPremium)) {
//                         showDialog(
//                           context: context,
//                           builder: (_) => AlertDialog(
//                             title: const Text("Premium Required"),
//                             content: const Text(
//                               "You must be a premium user to chat.",
//                             ),
//                             actions: [
//                               TextButton(
//                                 onPressed: () => Navigator.pop(context),
//                                 child: const Text("Cancel"),
//                               ),
//                               TextButton(
//                                 onPressed: () {
//                                   Navigator.pop(context);
//                                   Navigator.push(
//                                     context,
//                                     MaterialPageRoute(
//                                       builder: (_) => const PremiumScreen(),
//                                     ),
//                                   );
//                                 },
//                                 child: const Text("Upgrade to Premium"),
//                               ),
//                             ],
//                           ),
//                         );
//                         return;
//                       }

//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => ChatScreen(peerUser: widget.user),
//                         ),
//                       );
//                     },
//                     icon: const Icon(Icons.chat),
//                     label: const Text("Chat / Upgrade"),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: AppTheme.buttonColor,
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 20,
//                         vertical: 12,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//       // Safe Ad Placement
//       bottomNavigationBar: (!isPremium && _isBannerLoaded)
//           ? Container(
//               color: Colors.white,
//               height: _bannerAd!.size.height.toDouble(),
//               child: AdWidget(ad: _bannerAd!),
//             )
//           : null,
//     );
//   }
// }

