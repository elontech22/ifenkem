// import 'dart:io';

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart';
import 'package:ifenkem/screens/PremiumScreen.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart' as myAuth;
import '../screens/home_screen.dart';
import '../utils/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ProfileScreen({super.key, this.onProfileUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  myAuth.AuthProvider? authProvider;
  UserModel? currentUser;
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _educationController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _religionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();

  List<XFile> _newPickedImages = [];
  final ImagePicker _picker = ImagePicker();

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  bool _isFormComplete = false;

  @override
  void initState() {
    super.initState();
    authProvider = context.read<myAuth.AuthProvider>();
    _loadCurrentUser();

    _setupFieldListeners();
  }

  void _setupFieldListeners() {
    for (var controller in [
      _nameController,
      _occupationController,
      _educationController,
      _ageController,
      _religionController,
      _locationController,
      _descriptionController,
      _genderController,
    ]) {
      controller.addListener(_checkFormCompletion);
    }
  }

  void _checkFormCompletion() {
    final allFilled =
        _nameController.text.isNotEmpty &&
        _occupationController.text.isNotEmpty &&
        _educationController.text.isNotEmpty &&
        _ageController.text.isNotEmpty &&
        _religionController.text.isNotEmpty &&
        _locationController.text.isNotEmpty &&
        _descriptionController.text.isNotEmpty &&
        _genderController.text.isNotEmpty;

    final hasFiveImages =
        (_newPickedImages.isNotEmpty && _newPickedImages.length == 5) ||
        (currentUser != null &&
            currentUser!.profileImageUrls.length == 5 &&
            _newPickedImages.isEmpty);

    setState(() {
      _isFormComplete = allFilled && hasFiveImages;
    });
  }

  Future<void> _loadCurrentUser() async {
    setState(() => _isLoading = true);
    await authProvider?.fetchUserData();
    currentUser = authProvider?.currentUser;

    if (currentUser != null) {
      _nameController.text = currentUser!.name;
      _occupationController.text = currentUser!.occupation;
      _educationController.text = currentUser!.educationLevel;
      _ageController.text = currentUser!.age.toString();
      _religionController.text = currentUser!.religion;
      _locationController.text = currentUser!.location;
      _descriptionController.text = currentUser!.description;
      _genderController.text = currentUser!.gender;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', currentUser!.email);

      if (!currentUser!.isPremium) _loadBannerAd();
    }

    _checkFormCompletion(); // ✅ NEW
    setState(() => _isLoading = false);
  }

  void _loadBannerAd() {
    if (currentUser != null && currentUser!.isPremium) return;

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

  Future<void> _pickImages() async {
    final List<XFile>? images = await _picker.pickMultiImage();
    if (images != null && images.length == 5) {
      setState(() {
        _newPickedImages = images;
      });
      _checkFormCompletion(); // ✅ NEW
    } else if (images != null && images.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must upload exactly 5 images")),
      );
    } else if (images != null && images.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can only upload 5 images")),
      );
    }
  }

  Future<List<String>> _uploadImages(String uid) async {
    List<String> urls = [];
    for (var image in _newPickedImages) {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child(uid)
          .child(uid + DateTime.now().toIso8601String());
      await ref.putFile(File(image.path));
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  bool _validateDescription(String desc) {
    final regex = RegExp(
      r'[\d]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    );
    return !regex.hasMatch(desc);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final totalImages = _newPickedImages.isNotEmpty
        ? _newPickedImages.length
        : currentUser!.profileImageUrls.length;

    if (totalImages != 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must upload exactly 5 profile images"),
        ),
      );
      return;
    }

    if (!_validateDescription(_descriptionController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Description cannot contain numbers or email"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<String> imageUrls = currentUser!.profileImageUrls;
      if (_newPickedImages.isNotEmpty) {
        final uploadedUrls = await _uploadImages(currentUser!.uid);
        imageUrls = uploadedUrls;
      }

      final updatedUser = currentUser!.copyWith(
        name: _nameController.text.trim(),
        occupation: _occupationController.text.trim(),
        educationLevel: _educationController.text.trim(),
        age: int.tryParse(_ageController.text.trim()) ?? currentUser!.age,
        religion: _religionController.text.trim(),
        location: _locationController.text.trim(),
        description: _descriptionController.text.trim(),
        gender: _genderController.text.trim(),
        profileImageUrls: imageUrls,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .update(updatedUser.toMap());

      await authProvider?.fetchUserData();
      setState(() => currentUser = authProvider?.currentUser);

      if (currentUser != null && currentUser!.isPremium) {
        _bannerAd?.dispose();
        _isBannerLoaded = false;
      }

      if (widget.onProfileUpdated != null) widget.onProfileUpdated!();

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.transparent,
            content: Lottie.asset(
              'assets/animations/registration_success.json',
              repeat: false,
              width: 150,
              height: 150,
            ),
          ),
        );

        await Future.delayed(const Duration(seconds: 2));
        if (context.mounted) Navigator.pop(context);

        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving profile: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    for (var controller in [
      _nameController,
      _occupationController,
      _educationController,
      _ageController,
      _religionController,
      _locationController,
      _descriptionController,
      _genderController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Profile"),
          backgroundColor: AppTheme.primaryColor,
        ),
        body: const Center(
          child: Text(
            "Failed to load profile.\nCheck your network or login again.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final displayedImages = _newPickedImages.isNotEmpty
        ? _newPickedImages.map((e) => e.path).toList()
        : currentUser!.profileImageUrls;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: AppTheme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: "Go to Home",
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _checkFormCompletion,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (displayedImages.isNotEmpty)
                CarouselSlider(
                  options: CarouselOptions(
                    height: 200,
                    enlargeCenterPage: true,
                  ),
                  items: displayedImages.map((img) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: img.startsWith("http")
                          ? Image.network(
                              img,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 200,
                            )
                          : Image.file(
                              File(img),
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 200,
                            ),
                    );
                  }).toList(),
                )
              else
                Container(
                  height: 200,
                  color: AppTheme.accentColor,
                  child: const Center(child: Text("No Images")),
                ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.buttonColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _pickImages,
                child: const Text("Add/Replace Profile Images"),
              ),
              const SizedBox(height: 6),
              Text(
                "Selected Images: ${displayedImages.length}/5",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _buildTextField("Name", _nameController),
              _buildTextField("Occupation", _occupationController),
              _buildTextField("Education", _educationController),
              _buildTextField(
                "Age",
                _ageController,
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.isEmpty) return "Age is required";
                  final age = int.tryParse(val);
                  if (age == null) return "Enter a valid number";
                  if (age < 20) return "Age must be 20 or above";
                  return null;
                },
              ),
              _buildTextField("Religion", _religionController),
              _buildTextField("Location", _locationController),
              _buildTextField(
                "Description",
                _descriptionController,
                maxLines: 3,
                maxLength: 50,
                validator: (val) {
                  if (val == null || val.isEmpty)
                    return "Description is required";
                  if (val.length > 50) {
                    return "Description cannot exceed 50 characters";
                  }
                  return null;
                },
              ),
              _buildTextField("Gender", _genderController),
              const SizedBox(height: 10),
              if (currentUser!.isPremium)
                Row(
                  children: const [
                    Icon(Icons.star, color: Colors.amber),
                    SizedBox(width: 4),
                    Text(
                      "Premium",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              if (!currentUser!.isPremium)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.buttonColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PremiumScreen()),
                    );
                    await authProvider?.fetchUserData();
                    setState(() {
                      currentUser = authProvider?.currentUser;

                      if (currentUser != null && currentUser!.isPremium) {
                        _bannerAd?.dispose();
                        _isBannerLoaded = false;
                      }
                    });
                  },
                  child: const Text("Upgrade to Premium"),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFormComplete
                      ? AppTheme.buttonColor
                      : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isFormComplete ? _saveProfile : null,
                child: const Text("Save Changes"),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: (!currentUser!.isPremium && _isBannerLoaded)
          ? Container(
              color: Colors.white,
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : null,
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
        ),
        validator:
            validator ??
            (val) {
              if (val == null || val.trim().isEmpty) {
                return "$label is required";
              }
              return null;
            },
      ),
    );
  }
}

// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:carousel_slider/carousel_slider.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:lottie/lottie.dart';
// import 'package:ifenkem/screens/PremiumScreen.dart';

// import '../models/user_model.dart';
// import '../providers/auth_provider.dart' as myAuth;
// import '../screens/home_screen.dart';
// import '../utils/app_theme.dart';

// class ProfileScreen extends StatefulWidget {
//   final VoidCallback? onProfileUpdated;

//   const ProfileScreen({super.key, this.onProfileUpdated});

//   @override
//   State<ProfileScreen> createState() => _ProfileScreenState();
// }

// class _ProfileScreenState extends State<ProfileScreen> {
//   myAuth.AuthProvider? authProvider;
//   UserModel? currentUser;
//   bool _isLoading = true;

//   final _formKey = GlobalKey<FormState>();

//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _occupationController = TextEditingController();
//   final TextEditingController _educationController = TextEditingController();
//   final TextEditingController _ageController = TextEditingController();
//   final TextEditingController _religionController = TextEditingController();
//   final TextEditingController _locationController = TextEditingController();
//   final TextEditingController _descriptionController = TextEditingController();
//   final TextEditingController _genderController = TextEditingController();

//   List<XFile> _newPickedImages = [];
//   final ImagePicker _picker = ImagePicker();

//   BannerAd? _bannerAd;
//   bool _isBannerLoaded = false;

//   @override
//   void initState() {
//     super.initState();
//     authProvider = context.read<myAuth.AuthProvider>();
//     _loadCurrentUser();
//   }

//   Future<void> _loadCurrentUser() async {
//     setState(() => _isLoading = true);
//     await authProvider?.fetchUserData();
//     currentUser = authProvider?.currentUser;

//     if (currentUser != null) {
//       _nameController.text = currentUser!.name;
//       _occupationController.text = currentUser!.occupation;
//       _educationController.text = currentUser!.educationLevel;
//       _ageController.text = currentUser!.age.toString();
//       _religionController.text = currentUser!.religion;
//       _locationController.text = currentUser!.location;
//       _descriptionController.text = currentUser!.description;
//       _genderController.text = currentUser!.gender;

//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('userEmail', currentUser!.email);

//       if (!currentUser!.isPremium) _loadBannerAd();
//     }

//     setState(() => _isLoading = false);
//   }

//   void _loadBannerAd() {
//     if (currentUser != null && currentUser!.isPremium) return;

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

//   Future<void> _pickImages() async {
//     final List<XFile>? images = await _picker.pickMultiImage();
//     if (images != null && images.length == 5) {
//       setState(() => _newPickedImages = images);
//     } else if (images != null && images.length < 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("You must upload exactly 5 images")),
//       );
//     } else if (images != null && images.length > 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("You can only upload 5 images")),
//       );
//     }
//   }

//   Future<List<String>> _uploadImages(String uid) async {
//     List<String> urls = [];
//     for (var image in _newPickedImages) {
//       final ref = FirebaseStorage.instance
//           .ref()
//           .child('profile_images')
//           .child(uid)
//           .child(uid + DateTime.now().toIso8601String());
//       await ref.putFile(File(image.path));
//       final url = await ref.getDownloadURL();
//       urls.add(url);
//     }
//     return urls;
//   }

//   bool _validateDescription(String desc) {
//     final regex = RegExp(
//       r'[\d]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
//     );
//     return !regex.hasMatch(desc);
//   }

//   Future<void> _saveProfile() async {
//     if (!_formKey.currentState!.validate()) return;

//     final totalImages = _newPickedImages.isNotEmpty
//         ? _newPickedImages.length
//         : currentUser!.profileImageUrls.length;

//     if (totalImages != 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("You must upload exactly 5 profile images"),
//         ),
//       );
//       return;
//     }

//     if (!_validateDescription(_descriptionController.text)) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Description cannot contain numbers or email"),
//         ),
//       );
//       return;
//     }

//     setState(() => _isLoading = true);

//     try {
//       List<String> imageUrls = currentUser!.profileImageUrls;
//       if (_newPickedImages.isNotEmpty) {
//         final uploadedUrls = await _uploadImages(currentUser!.uid);
//         imageUrls = uploadedUrls;
//       }

//       final updatedUser = currentUser!.copyWith(
//         name: _nameController.text.trim(),
//         occupation: _occupationController.text.trim(),
//         educationLevel: _educationController.text.trim(),
//         age: int.tryParse(_ageController.text.trim()) ?? currentUser!.age,
//         religion: _religionController.text.trim(),
//         location: _locationController.text.trim(),
//         description: _descriptionController.text.trim(),
//         gender: _genderController.text.trim(),
//         profileImageUrls: imageUrls,
//       );

//       await FirebaseFirestore.instance
//           .collection('users')
//           .doc(currentUser!.uid)
//           .update(updatedUser.toMap());

//       await authProvider?.fetchUserData();
//       setState(() => currentUser = authProvider?.currentUser);

//       if (currentUser != null && currentUser!.isPremium) {
//         _bannerAd?.dispose();
//         _isBannerLoaded = false;
//       }

//       if (widget.onProfileUpdated != null) widget.onProfileUpdated!();

//       if (context.mounted) {
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             backgroundColor: Colors.transparent,
//             content: Lottie.asset(
//               'assets/animations/registration_success.json',
//               repeat: false,
//               width: 150,
//               height: 150,
//             ),
//           ),
//         );

//         await Future.delayed(const Duration(seconds: 2));
//         if (context.mounted) Navigator.pop(context);

//         if (context.mounted) {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (_) => const HomeScreen()),
//           );
//         }
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text("Error saving profile: $e")));
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }

//   @override
//   void dispose() {
//     _bannerAd?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return Scaffold(
//         body: Center(
//           child: CircularProgressIndicator(color: AppTheme.primaryColor),
//         ),
//       );
//     }

//     if (currentUser == null) {
//       return Scaffold(
//         appBar: AppBar(
//           title: const Text("Profile"),
//           backgroundColor: AppTheme.primaryColor,
//         ),
//         body: const Center(
//           child: Text(
//             "Failed to load profile.\nCheck your network or login again.",
//             textAlign: TextAlign.center,
//             style: TextStyle(fontSize: 16),
//           ),
//         ),
//       );
//     }

//     final displayedImages = _newPickedImages.isNotEmpty
//         ? _newPickedImages.map((e) => e.path).toList()
//         : currentUser!.profileImageUrls;

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Profile"),
//         backgroundColor: AppTheme.primaryColor,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.home),
//             tooltip: "Go to Home",
//             onPressed: () {
//               Navigator.pushReplacement(
//                 context,
//                 MaterialPageRoute(builder: (_) => const HomeScreen()),
//               );
//             },
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               if (displayedImages.isNotEmpty)
//                 CarouselSlider(
//                   options: CarouselOptions(
//                     height: 200,
//                     enlargeCenterPage: true,
//                   ),
//                   items: displayedImages.map((img) {
//                     return ClipRRect(
//                       borderRadius: BorderRadius.circular(12),
//                       child: img.startsWith("http")
//                           ? Image.network(
//                               img,
//                               fit: BoxFit.contain,
//                               width: double.infinity,
//                               height: 200,
//                             )
//                           : Image.file(
//                               File(img),
//                               fit: BoxFit.contain,
//                               width: double.infinity,
//                               height: 200,
//                             ),
//                     );
//                   }).toList(),
//                 )
//               else
//                 Container(
//                   height: 200,
//                   color: AppTheme.accentColor,
//                   child: const Center(child: Text("No Images")),
//                 ),
//               const SizedBox(height: 10),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppTheme.buttonColor,
//                   foregroundColor: Colors.white,
//                 ),
//                 onPressed: _pickImages,
//                 child: const Text("Add/Replace Profile Images"),
//               ),
//               const SizedBox(height: 6),
//               Text(
//                 "Selected Images: ${displayedImages.length}/5",
//                 style: const TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 10),
//               _buildTextField("Name", _nameController),
//               _buildTextField("Occupation", _occupationController),
//               _buildTextField("Education", _educationController),
//               _buildTextField(
//                 "Age",
//                 _ageController,
//                 keyboardType: TextInputType.number,
//                 validator: (val) {
//                   if (val == null || val.isEmpty) return "Age is required";
//                   final age = int.tryParse(val);
//                   if (age == null) return "Enter a valid number";
//                   if (age < 20) return "Age must be 20 or above";
//                   return null;
//                 },
//               ),
//               _buildTextField("Religion", _religionController),
//               _buildTextField("Location", _locationController),
//               _buildTextField(
//                 "Description",
//                 _descriptionController,
//                 maxLines: 3,
//                 maxLength: 50,
//                 validator: (val) {
//                   if (val == null || val.isEmpty)
//                     return "Description is required";
//                   if (val.length > 50) {
//                     return "Description cannot exceed 50 characters";
//                   }
//                   return null;
//                 },
//               ),
//               _buildTextField("Gender", _genderController),
//               const SizedBox(height: 10),
//               if (currentUser!.isPremium)
//                 Row(
//                   children: const [
//                     Icon(Icons.star, color: Colors.amber),
//                     SizedBox(width: 4),
//                     Text(
//                       "Premium",
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                   ],
//                 ),
//               if (!currentUser!.isPremium)
//                 ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: AppTheme.buttonColor,
//                     foregroundColor: Colors.white,
//                   ),
//                   onPressed: () async {
//                     await Navigator.push(
//                       context,
//                       MaterialPageRoute(builder: (_) => PremiumScreen()),
//                     );
//                     await authProvider?.fetchUserData();
//                     setState(() {
//                       currentUser = authProvider?.currentUser;

//                       if (currentUser != null && currentUser!.isPremium) {
//                         _bannerAd?.dispose();
//                         _isBannerLoaded = false;
//                       }
//                     });
//                   },
//                   child: const Text("Upgrade to Premium"),
//                 ),
//               const SizedBox(height: 20),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppTheme.buttonColor,
//                   foregroundColor: Colors.white,
//                 ),
//                 onPressed: _saveProfile,
//                 child: const Text("Save Changes"),
//               ),
//             ],
//           ),
//         ),
//       ),

//       bottomNavigationBar: (!currentUser!.isPremium && _isBannerLoaded)
//           ? Container(
//               color: Colors.white,
//               height: _bannerAd!.size.height.toDouble(),
//               child: AdWidget(ad: _bannerAd!),
//             )
//           : null,
//     );
//   }

//   Widget _buildTextField(
//     String label,
//     TextEditingController controller, {
//     bool obscure = false,
//     int maxLines = 1,
//     TextInputType? keyboardType,
//     int? maxLength,
//     String? Function(String?)? validator,
//   }) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: TextFormField(
//         controller: controller,
//         obscureText: obscure,
//         maxLines: maxLines,
//         maxLength: maxLength,
//         keyboardType: keyboardType,
//         decoration: InputDecoration(
//           labelText: label,
//           border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
//           filled: true,
//           fillColor: Colors.white,
//         ),
//         validator:
//             validator ??
//             (val) {
//               if (val == null || val.trim().isEmpty) {
//                 return "$label is required";
//               }
//               return null;
//             },
//       ),
//     );
//   }
// }

// import 'dart:io';
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:carousel_slider/carousel_slider.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import 'package:lottie/lottie.dart';
// import 'package:ifenkem/screens/PremiumScreen.dart';

// import '../models/user_model.dart';
// import '../providers/auth_provider.dart' as myAuth;
// import '../screens/home_screen.dart';
// import '../utils/app_theme.dart';

// class ProfileScreen extends StatefulWidget {
//   final VoidCallback? onProfileUpdated;

//   const ProfileScreen({super.key, this.onProfileUpdated});

//   @override
//   State<ProfileScreen> createState() => _ProfileScreenState();
// }

// class _ProfileScreenState extends State<ProfileScreen> {
//   myAuth.AuthProvider? authProvider;
//   UserModel? currentUser;
//   bool _isLoading = true;

//   final _formKey = GlobalKey<FormState>();

//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _occupationController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
//   final TextEditingController _educationController = TextEditingController();
//   final TextEditingController _ageController = TextEditingController();
//   final TextEditingController _religionController = TextEditingController();
//   final TextEditingController _locationController = TextEditingController();
//   final TextEditingController _descriptionController = TextEditingController();
//   final TextEditingController _genderController = TextEditingController();

//   List<XFile> _newPickedImages = [];
//   final ImagePicker _picker = ImagePicker();

//   // ✅ Only BannerAd remains
//   BannerAd? _bannerAd;
//   bool _isBannerLoaded = false;

//   @override
//   void initState() {
//     super.initState();
//     authProvider = context.read<myAuth.AuthProvider>();
//     _loadCurrentUser();
//   }

//   Future<void> _loadCurrentUser() async {
//     setState(() => _isLoading = true);
//     await authProvider?.fetchUserData();
//     currentUser = authProvider?.currentUser;

//     if (currentUser != null) {
//       _nameController.text = currentUser!.name;
//       _occupationController.text = currentUser!.occupation;
//       _phoneController.text = currentUser!.phoneNumber;
//       _educationController.text = currentUser!.educationLevel;
//       _ageController.text = currentUser!.age.toString();
//       _religionController.text = currentUser!.religion;
//       _locationController.text = currentUser!.location;
//       _descriptionController.text = currentUser!.description;
//       _genderController.text = currentUser!.gender;

//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('userEmail', currentUser!.email);

//       if (!currentUser!.isPremium) _loadBannerAd();
//     }

//     setState(() => _isLoading = false);
//   }

//   void _loadBannerAd() {
//     if (currentUser != null && currentUser!.isPremium) return;

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

//   Future<void> _pickImages() async {
//     final List<XFile>? images = await _picker.pickMultiImage();
//     if (images != null && images.length == 5) {
//       setState(() => _newPickedImages = images);
//     } else if (images != null && images.length < 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("You must upload exactly 5 images")),
//       );
//     } else if (images != null && images.length > 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("You can only upload 5 images")),
//       );
//     }
//   }

//   Future<List<String>> _uploadImages(String uid) async {
//     List<String> urls = [];
//     for (var image in _newPickedImages) {
//       final ref = FirebaseStorage.instance
//           .ref()
//           .child('profile_images')
//           .child(uid)
//           .child(uid + DateTime.now().toIso8601String());
//       await ref.putFile(File(image.path));
//       final url = await ref.getDownloadURL();
//       urls.add(url);
//     }
//     return urls;
//   }

//   bool _validateDescription(String desc) {
//     final regex = RegExp(
//       r'[\d]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
//     );
//     return !regex.hasMatch(desc);
//   }

//   Future<void> _saveProfile() async {
//     if (!_formKey.currentState!.validate()) return;

//     // ✅ Require exactly 5 images
//     final totalImages = _newPickedImages.isNotEmpty
//         ? _newPickedImages.length
//         : currentUser!.profileImageUrls.length;

//     if (totalImages != 5) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("You must upload exactly 5 profile images"),
//         ),
//       );
//       return;
//     }

//     if (!_validateDescription(_descriptionController.text)) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Description cannot contain numbers or email"),
//         ),
//       );
//       return;
//     }

//     setState(() => _isLoading = true);

//     try {
//       List<String> imageUrls = currentUser!.profileImageUrls;
//       if (_newPickedImages.isNotEmpty) {
//         final uploadedUrls = await _uploadImages(currentUser!.uid);
//         imageUrls = uploadedUrls;
//       }

//       final updatedUser = currentUser!.copyWith(
//         name: _nameController.text.trim(),
//         occupation: _occupationController.text.trim(),
//         phoneNumber: _phoneController.text.trim(),
//         educationLevel: _educationController.text.trim(),
//         age: int.tryParse(_ageController.text.trim()) ?? currentUser!.age,
//         religion: _religionController.text.trim(),
//         location: _locationController.text.trim(),
//         description: _descriptionController.text.trim(),
//         gender: _genderController.text.trim(),
//         profileImageUrls: imageUrls,
//       );

//       await FirebaseFirestore.instance
//           .collection('users')
//           .doc(currentUser!.uid)
//           .update(updatedUser.toMap());

//       await authProvider?.fetchUserData();
//       setState(() => currentUser = authProvider?.currentUser);

//       if (currentUser != null && currentUser!.isPremium) {
//         _bannerAd?.dispose();
//         _isBannerLoaded = false;
//       }

//       if (widget.onProfileUpdated != null) widget.onProfileUpdated!();

//       if (context.mounted) {
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             backgroundColor: Colors.transparent,
//             content: Lottie.asset(
//               'assets/animations/registration_success.json',
//               repeat: false,
//               width: 150,
//               height: 150,
//             ),
//           ),
//         );

//         await Future.delayed(const Duration(seconds: 2));
//         if (context.mounted) Navigator.pop(context);
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text("Error saving profile: $e")));
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }

//   @override
//   void dispose() {
//     _bannerAd?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return Scaffold(
//         body: Center(
//           child: CircularProgressIndicator(color: AppTheme.primaryColor),
//         ),
//       );
//     }

//     if (currentUser == null) {
//       return Scaffold(
//         appBar: AppBar(
//           title: const Text("Profile"),
//           backgroundColor: AppTheme.primaryColor,
//         ),
//         body: const Center(
//           child: Text(
//             "Failed to load profile.\nCheck your network or login again.",
//             textAlign: TextAlign.center,
//             style: TextStyle(fontSize: 16),
//           ),
//         ),
//       );
//     }

//     final displayedImages = _newPickedImages.isNotEmpty
//         ? _newPickedImages.map((e) => e.path).toList()
//         : currentUser!.profileImageUrls;

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Profile"),
//         backgroundColor: AppTheme.primaryColor,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.home),
//             tooltip: "Go to Home",
//             onPressed: () {
//               Navigator.pushReplacement(
//                 context,
//                 MaterialPageRoute(builder: (_) => const HomeScreen()),
//               );
//             },
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               if (displayedImages.isNotEmpty)
//                 CarouselSlider(
//                   options: CarouselOptions(
//                     height: 200,
//                     enlargeCenterPage: true,
//                   ),
//                   items: displayedImages.map((img) {
//                     return ClipRRect(
//                       borderRadius: BorderRadius.circular(12),
//                       child: img.startsWith("http")
//                           ? Image.network(
//                               img,
//                               fit: BoxFit.contain,
//                               width: double.infinity,
//                               height: 200,
//                             )
//                           : Image.file(
//                               File(img),
//                               fit: BoxFit.contain,
//                               width: double.infinity,
//                               height: 200,
//                             ),
//                     );
//                   }).toList(),
//                 )
//               else
//                 Container(
//                   height: 200,
//                   color: AppTheme.accentColor,
//                   child: const Center(child: Text("No Images")),
//                 ),
//               const SizedBox(height: 10),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppTheme.buttonColor,
//                   foregroundColor: Colors.white,
//                 ),
//                 onPressed: _pickImages,
//                 child: const Text("Add/Replace Profile Images"),
//               ),
//               const SizedBox(height: 6),
//               Text(
//                 "Selected Images: ${displayedImages.length}/5",
//                 style: const TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 10),
//               _buildTextField("Name", _nameController),
//               _buildTextField("Occupation", _occupationController),
//               _buildTextField("Phone Number", _phoneController),
//               _buildTextField("Education", _educationController),
//               _buildTextField(
//                 "Age",
//                 _ageController,
//                 keyboardType: TextInputType.number,
//                 validator: (val) {
//                   if (val == null || val.isEmpty) return "Age is required";
//                   final age = int.tryParse(val);
//                   if (age == null) return "Enter a valid number";
//                   if (age < 18) return "Users below 18 not allowed";
//                   if (age < 20) return "Age must be 20 or above";
//                   return null;
//                 },
//               ),
//               _buildTextField("Religion", _religionController),
//               _buildTextField("Location", _locationController),
//               _buildTextField(
//                 "Description",
//                 _descriptionController,
//                 maxLines: 3,
//                 maxLength: 50,
//                 validator: (val) {
//                   if (val == null || val.isEmpty)
//                     return "Description is required";
//                   if (val.length > 50) {
//                     return "Description cannot exceed 50 characters";
//                   }
//                   return null;
//                 },
//               ),
//               _buildTextField("Gender", _genderController),
//               const SizedBox(height: 10),
//               if (currentUser!.isPremium)
//                 SwitchListTile(
//                   title: const Text(
//                     "Show phone number to other premium users in your details page",
//                   ),
//                   value: currentUser!.showPhoneToPremium,
//                   onChanged: (val) =>
//                       setState(() => currentUser!.showPhoneToPremium = val),
//                 ),
//               const SizedBox(height: 10),
//               if (currentUser!.isPremium)
//                 Row(
//                   children: const [
//                     Icon(Icons.star, color: Colors.amber),
//                     SizedBox(width: 4),
//                     Text(
//                       "Premium",
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                   ],
//                 ),
//               if (!currentUser!.isPremium)
//                 ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: AppTheme.buttonColor,
//                     foregroundColor: Colors.white,
//                   ),
//                   onPressed: () async {
//                     await Navigator.push(
//                       context,
//                       MaterialPageRoute(builder: (_) => PremiumScreen()),
//                     );
//                     await authProvider?.fetchUserData();
//                     setState(() {
//                       currentUser = authProvider?.currentUser;

//                       if (currentUser != null && currentUser!.isPremium) {
//                         _bannerAd?.dispose();
//                         _isBannerLoaded = false;
//                       }
//                     });
//                   },
//                   child: const Text("Upgrade to Premium"),
//                 ),
//               const SizedBox(height: 20),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppTheme.buttonColor,
//                   foregroundColor: Colors.white,
//                 ),
//                 onPressed: _saveProfile,
//                 child: const Text("Save Changes"),
//               ),
//             ],
//           ),
//         ),
//       ),

//       // ✅ BannerAd moved here
//       bottomNavigationBar: (!currentUser!.isPremium && _isBannerLoaded)
//           ? Container(
//               color: Colors.white,
//               height: _bannerAd!.size.height.toDouble(),
//               child: AdWidget(ad: _bannerAd!),
//             )
//           : null,
//     );
//   }

//   Widget _buildTextField(
//     String label,
//     TextEditingController controller, {
//     bool obscure = false,
//     int maxLines = 1,
//     TextInputType? keyboardType,
//     int? maxLength,
//     String? Function(String?)? validator,
//   }) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: TextFormField(
//         controller: controller,
//         obscureText: obscure,
//         maxLines: maxLines,
//         maxLength: maxLength,
//         keyboardType: keyboardType,
//         decoration: InputDecoration(
//           labelText: label,
//           border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
//           filled: true,
//           fillColor: Colors.white,
//         ),
//         validator:
//             validator ??
//             (val) {
//               if (val == null || val.trim().isEmpty) {
//                 return "$label is required";
//               }
//               return null;
//             },
//       ),
//     );
//   }
// }
