import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class OnboardingSlides extends StatefulWidget {
  const OnboardingSlides({super.key});

  @override
  State<OnboardingSlides> createState() => _OnboardingSlidesState();
}

class _OnboardingSlidesState extends State<OnboardingSlides> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  final List<Map<String, String>> slides = [
    {
      'lottie': 'assets/animations/discover.json',
      'text': 'Browse profiles of people looking for meaningful connections.',
    },
    {
      'lottie': 'assets/animations/chat.json',
      'text': 'Send messages and start conversations with people you like.',
    },
    {
      'lottie': 'assets/animations/s.json',
      'text': 'Check out stories to know more about people before connecting.',
    },
    {
      'lottie': 'assets/animations/l.json',
      'text': 'Show interest in someone by liking their profile.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPage < slides.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: slides.length,
      itemBuilder: (context, index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              slides[index]['lottie']!,
              width: 250,
              height: 250,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                slides[index]['text']!,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
