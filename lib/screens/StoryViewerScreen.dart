import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
import 'package:intl/intl.dart';

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

  // 🟢 Mark story as viewed and store viewer UID
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

  // 🟢 Delete all stories of the current user
  Future<void> _deleteAllStories() async {
    try {
      final storiesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.story.userId)
          .collection('stories');

      final storiesSnapshot = await storiesRef.get();

      for (var doc in storiesSnapshot.docs) {
        final data = doc.data();
        if (data['imageUrls'] != null) {
          for (String url in List<String>.from(data['imageUrls'])) {
            try {
              final ref = FirebaseStorage.instance.refFromURL(url);
              await ref.delete();
            } catch (e) {
              print("Error deleting image from storage: $e");
            }
          }
        }
        await doc.reference.delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All your stories were deleted!")),
      );

      Navigator.pop(context, true); // 🟢 Return true to refresh story bar
    } catch (e) {
      print("Error deleting all stories: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to delete all stories.")),
      );
    }
  }

  Future<void> _deleteSingleStory(int currentIndex) async {
    try {
      final storyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.story.userId)
          .collection('stories')
          .doc(widget.story.id);

      List<String> updatedUrls = List<String>.from(widget.story.imageUrls);

      // Delete only the current story image from Storage
      final urlToDelete = updatedUrls[currentIndex];
      try {
        final ref = FirebaseStorage.instance.refFromURL(urlToDelete);
        await ref.delete();
      } catch (e) {
        print("Error deleting image from storage: $e");
      }

      // Remove the image from Firestore array
      updatedUrls.removeAt(currentIndex);

      // If no images left, delete the whole story document
      if (updatedUrls.isEmpty) {
        await storyRef.delete();
      } else {
        await storyRef.update({'imageUrls': updatedUrls});
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Image deleted successfully!")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      print("Error deleting story image: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to delete image.")));
    }
  }

  // 🟢 Format timestamp like WhatsApp
  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final postTime = timestamp.toDate();
    final difference = now.difference(postTime);

    if (difference.inDays == 0) {
      return "Today ${DateFormat.jm().format(postTime)}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${DateFormat.jm().format(postTime)}";
    } else {
      return DateFormat('dd MMM yyyy, hh:mm a').format(postTime);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.story.userName),
            // 🟢 Display timestamp
            Text(
              _formatTimestamp(widget.story.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // 🟢 Show delete menu only for story owner
          if (widget.story.userId == viewer?.uid)
            PopupMenuButton<String>(
              icon: const Icon(Icons.delete, color: Colors.red),
              onSelected: (value) async {
                if (value == 'single') {
                  await _deleteSingleStory(
                    _storyController.playbackNotifier.value.index,
                  );
                } else if (value == 'all') {
                  await _deleteAllStories();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'single',
                  child: Text('Delete this story'),
                ),
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Delete all my stories'),
                ),
              ],
            ),
        ],
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

          // 🟢 Chat / Upgrade Button (only for other users)
          if (widget.story.userId != viewer?.uid)
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
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Authentication Required"),
                        content: const Text(
                          "Please log in to chat or upgrade.",
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

                  if (!viewer.isPremium) {
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

                  final userDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.story.userId)
                      .get();

                  if (!userDoc.exists) return;

                  final storyOwner = UserModel.fromMap(
                    userDoc.data() as Map<String, dynamic>,
                    id: userDoc.id,
                  );

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
