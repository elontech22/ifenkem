import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ifenkem/models/storymodel.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

class StoryUploadScreen extends StatefulWidget {
  const StoryUploadScreen({super.key});

  @override
  State<StoryUploadScreen> createState() => _StoryUploadScreenState();
}

class _StoryUploadScreenState extends State<StoryUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = [];

  Future<void> _pickImages() async {
    final List<XFile>? images = await _picker.pickMultiImage();
    if (images != null) {
      if (images.length + _selectedImages.length > 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can upload up to 5 images only.")),
        );
        return;
      }
      setState(() => _selectedImages.addAll(images));
    }
  }

  Future<void> _uploadStory() async {
    if (_selectedImages.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    // Upload images to Firebase Storage and get URLs
    // ✅ For simplicity, assuming image URLs are already uploaded
    List<String> imageUrls = _selectedImages.map((img) => img.path).toList();

    final storyId = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('stories')
        .doc()
        .id;

    final story = StoryModel(
      id: storyId,
      userId: currentUser.uid,
      userName: currentUser.name,
      location: currentUser.location,
      gender: currentUser.gender,
      imageUrls: imageUrls,
      timestamp: Timestamp.now(),
    );

    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('stories')
        .doc(storyId)
        .set(story.toMap());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Story uploaded successfully!")),
    );

    setState(() => _selectedImages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Story")),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _selectedImages.length + 1,
              itemBuilder: (context, index) {
                if (index == _selectedImages.length) {
                  return GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      color: Colors.grey[300],
                      child: const Center(child: Icon(Icons.add)),
                    ),
                  );
                }

                return Image.file(
                  File(_selectedImages[index].path),
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton(
              onPressed: _uploadStory,
              child: const Text("Upload Story"),
            ),
          ),
        ],
      ),
    );
  }
}
