import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/app_theme.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool _available = false;
  bool _purchasePending = false;
  List<ProductDetails> _products = [];
  final String _premiumId = 'ifenkem_premium';

  @override
  void initState() {
    super.initState();
    _initializeIAP();
  }

  Future<void> _initializeIAP() async {
    _available = await _iap.isAvailable();
    if (!_available) return;

    final purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _listenToPurchaseUpdated,
      onDone: () => _subscription.cancel(),
      onError: (err) => print("Purchase Stream error: $err"),
    );

    await _getProducts();
  }

  Future<void> _getProducts() async {
    final response = await _iap.queryProductDetails({_premiumId});
    if (response.notFoundIDs.isNotEmpty) {
      print("Product not found: ${response.notFoundIDs}");
    }
    setState(() => _products = response.productDetails);
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchases) {
    for (var purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _deliverPremium();
      } else if (purchase.status == PurchaseStatus.error) {
        setState(() => _purchasePending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Purchase error: ${purchase.error?.message}")),
        );
      }
    }
  }

  Future<void> _deliverPremium() async {
    setState(() => _purchasePending = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.updatePremiumStatus();
      await authProvider.fetchUserData();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Premium activated!")));

      Navigator.pop(context); // Back to HomeScreen
    } catch (e) {
      print("Error updating premium status: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error unlocking premium: $e")));
    } finally {
      setState(() => _purchasePending = false);
    }
  }

  Future<void> _buyPremium() async {
    if (_products.isEmpty) return;

    final purchaseParam = PurchaseParam(productDetails: _products.first);
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final premiumActive =
        user.isPremium &&
        user.premiumEnd != null &&
        DateTime.now().isBefore(user.premiumEnd!);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Upgrade to Premium"),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: premiumActive
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, size: 120, color: Colors.amber),
                    const SizedBox(height: 20),
                    Text(
                      "Premium Active 🎉",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "You are a Premium user until:\n${user.premiumEnd}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.star_border,
                      size: 120,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Unlock Premium Features",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Feature List Card
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: const [
                            FeatureItem(
                              icon: Icons.chat,
                              text: "Chat with other users",
                            ),

                            FeatureItem(
                              icon: Icons.block_flipped,
                              text: "Browse without ads",
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Buy Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _purchasePending ? null : _buyPremium,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _purchasePending
                              ? "Processing..."
                              : "Buy Premium Now",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const FeatureItem({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
