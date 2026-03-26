import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';

class CoinStoreScreen extends StatefulWidget {
  final int currentUserId;
  const CoinStoreScreen({super.key, required this.currentUserId});

  @override
  State<CoinStoreScreen> createState() => _CoinStoreScreenState();
}

class _CoinStoreScreenState extends State<CoinStoreScreen> {
  bool _isLoading = false;

  final List<Map<String, dynamic>> _packages = [
    {'id': 'coins_500', 'coins': 500, 'amount': 99, 'displayAmount': '\$0.99', 'icon': Icons.monetization_on_outlined, 'color': Colors.amber},
    {'id': 'coins_1200', 'coins': 1200, 'amount': 199, 'displayAmount': '\$1.99', 'icon': Icons.monetization_on, 'color': Colors.orange},
    {'id': 'coins_2500', 'coins': 2500, 'amount': 399, 'displayAmount': '\$3.99', 'icon': Icons.savings, 'color': Colors.deepOrange},
    {'id': 'coins_7000', 'coins': 7000, 'amount': 999, 'displayAmount': '\$9.99', 'icon': Icons.diamond, 'color': Colors.purple},
  ];

  Future<void> _startPayment(Map<String, dynamic> package) async {
    setState(() => _isLoading = true);

    try {
      // 1. Create PaymentIntent on the backend
      final response = await ApiService().post('/api/payments/create-payment-intent/', {
        'amount': package['amount'],
        'coins': package['coins'],
      });

      if (response.statusCode != 200) {
        throw Exception("Failed to create payment intent");
      }

      final data = response.data;
      final clientSecret = data['clientSecret'];

      // 2. Initialize Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Chess Game Premium',
          style: ThemeMode.dark,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: primaryYellow,
              background: backgroundColor,
              componentBackground: foregroundColor,
              componentBorder: primaryYellow,
              componentText: Colors.white,
              primaryText: Colors.white,
              secondaryText: Colors.grey,
              placeholderText: Colors.grey,
            ),
          ),
        ),
      );

      // 3. Present Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. Success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment successful! Your coins will be added shortly."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (e is StripeException) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Payment Cancelled: ${e.error.localizedMessage}")),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e")),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text("Coin Store", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundColor, Color(0xFF16213E)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select a Package",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Get more coins to unlock premium features and bets.",
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: ListView.builder(
                  itemCount: _packages.length,
                  itemBuilder: (context, index) {
                    final p = _packages[index];
                    return _buildPackageItem(p);
                  },
                ),
              ),
              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: primaryYellow)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageItem(Map<String, dynamic> package) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: foregroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: package['color'].withOpacity(0.3), width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: package['color'].withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(package['icon'], color: package['color'], size: 30),
        ),
        title: Text(
          "${package['coins']} Coins",
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Instant delivery",
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: _isLoading ? null : () => _startPayment(package),
          style: ElevatedButton.styleFrom(
            backgroundColor: package['color'],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(package['displayAmount'], style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
