import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ifenkem/models/storymodel.dart';
import 'package:ifenkem/models/user_model.dart';
import 'package:ifenkem/screens/PremiumScreen.dart';
import 'package:provider/provider.dart';
import 'package:story_view/story_view.dart';

import '../providers/auth_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/login_screen.dart';
import '../utils/app_theme.dart';

class StoryViewerScreen extends StatefulWidget {
  final StoryModel story;

  const StoryViewerScreen({super.key, required this.story});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  final StoryController _storyController = StoryController();

  @override
  void initState() {
    super.initState();
    _markStoryAsViewed();
  }

  @override
  void dispose() {
    _storyController.dispose();
    super.dispose();
  }

  Future<void> _markStoryAsViewed() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final viewer = authProvider.currentUser;
    if (viewer == null) return;

    final storyRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.story.userId)
        .collection('stories')
        .doc(widget.story.id);

    try {
      await storyRef.update({
        'viewers': FieldValue.arrayUnion([viewer.uid]),
      });
    } catch (e) {
      print("Error marking story as viewed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final viewer = authProvider.currentUser;
    final isPremium = viewer?.isPremium ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        title: const Text("Story"),
      ),
      body: Stack(
        children: [
          // 🟢 Story Viewer
          StoryView(
            storyItems: widget.story.imageUrls.map((url) {
              return StoryItem.pageImage(
                url: url,
                controller: _storyController,
                imageFit: BoxFit.cover,
              );
            }).toList(),
            controller: _storyController,
            onComplete: () {
              Navigator.pop(context);
            },
          ),

          // 🟢 Chat / Upgrade Button
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.chat),
              label: const Text("Chat / Upgrade"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.buttonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final authProvider = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                );
                final viewer = authProvider.currentUser;

                if (viewer == null) {
                  // Not logged in
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text("Authentication Required"),
                      content: const Text("Please log in to chat or upgrade."),
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

                if (!viewer.isPremium) {
                  // Not premium
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

                // Fetch story owner's full UserModel
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.story.userId)
                    .get();

                if (!userDoc.exists) return;

                final storyOwner = UserModel.fromMap(
                  userDoc.data() as Map<String, dynamic>,
                  id: userDoc.id,
                );

                // Navigate to chat screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(peerUser: storyOwner),
                  ),
                );
              },
            ),
          ),

          // 🟢 Blur Overlay for non-premium users
          if (!isPremium)
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
                          "Unlock this story",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Upgrade to Premium to view full story",
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PremiumScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pinkAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
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
    );
  }
}
