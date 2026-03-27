import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:appifyours/screens/element_screen/delivery.dart';

// API Service
class ApiService {
  static String get baseUrl => dotenv.env['API_BASE'] ?? 'https://appifyours.com';
  
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token == null) return {};
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['user'] ?? {};
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
    }
    return {};
  }
}

// Auth Helper
class AuthHelper {
  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    return role == 'admin';
  }
}

final AuthHelper authHelper = AuthHelper();

// PriceUtils class
class PriceUtils {
  static String formatPrice(double price, {String currency = '\$'}) {
    return '$currency${price.toStringAsFixed(2)}';
  }

  static double parsePrice(String priceString) {
    if (priceString.isEmpty) return 0.0;
    String numericString = priceString.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(numericString) ?? 0.0;
  }

  static String detectCurrency(String priceString) {
    if (priceString.contains('₹')) return '₹';
    if (priceString.contains('\$')) return '\$';
    if (priceString.contains('€')) return '€';
    if (priceString.contains('£')) return '£';
    if (priceString.contains('¥')) return '¥';
    if (priceString.contains('₩')) return '₩';
    if (priceString.contains('₽')) return '₽';
    if (priceString.contains('₦')) return '₦';
    if (priceString.contains('₨')) return '₨';
    return '\$';
  }

  static String currencySymbolFromCode(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
      case 'AUD':
      case 'CAD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      case 'INR':
        return '₹';
      case 'KRW':
        return '₩';
      case 'RUB':
        return '₽';
      case 'NGN':
        return '₦';
      case 'PKR':
        return '₨';
      default:
        return '\$';
    }
  }

  static double calculateDiscountPrice(double originalPrice, double discountPercentage) {
    return originalPrice * (1 - discountPercentage / 100);
  }

  static double calculateTotal(List<double> prices) {
    return prices.fold(0.0, (sum, price) => sum + price);
  }

  static double calculateTax(double subtotal, double taxRate) {
    return subtotal * (taxRate / 100);
  }

  static double applyShipping(double total, double shippingFee, {double freeShippingThreshold = 100.0}) {
    return total >= freeShippingThreshold ? total : total + shippingFee;
  }
}

// Cart item model
class CartItem {
  final String id;
  final String name;
  final double price;
  final double discountPrice;
  int quantity;
  final String? image;
  final String currencySymbol;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.discountPrice = 0.0,
    this.quantity = 1,
    this.image,
    this.currencySymbol = '\$',
  });

  double get effectivePrice => discountPrice > 0 ? discountPrice : price;
  double get totalPrice => effectivePrice * quantity;
}

// Cart manager
class CartManager extends ChangeNotifier {
  final List<CartItem> _items = [];
  double _gstPercentage = 18.0;

  List<CartItem> get items => List.unmodifiable(_items);
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  String get displayCurrencySymbol {
    if (_items.isEmpty) return '\$';
    
    final Map<String, int> currencyCounts = {};
    for (var item in _items) {
      final symbol = item.currencySymbol;
      currencyCounts[symbol] = (currencyCounts[symbol] ?? 0) + 1;
    }
    
    String mostCommonCurrency = '\$';
    int maxCount = 0;
    currencyCounts.forEach((symbol, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonCurrency = symbol;
      }
    });
    
    return mostCommonCurrency;
  }

  void updateGSTPercentage(double percentage) {
    _gstPercentage = percentage;
    notifyListeners();
  }

  double get gstPercentage => _gstPercentage;

  void addItem(CartItem item) {
    final existingIndex = _items.indexWhere((i) => i.id == item.id);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void updateQuantity(String id, int quantity) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  double get subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double get totalWithTax {
    final tax = PriceUtils.calculateTax(subtotal, 8.0);
    return subtotal + tax;
  }

  double get totalDiscount {
    return _items.fold(0.0, (sum, item) => 
      sum + ((item.price - item.effectivePrice) * item.quantity));
  }

  double get gstAmount {
    return PriceUtils.calculateTax(subtotal, _gstPercentage);
  }

  double get finalTotal {
    return subtotal + gstAmount;
  }
}

// Wishlist item model
class WishlistItem {
  final String id;
  final String name;
  final double price;
  final double discountPrice;
  final String? image;
  final String currencySymbol;

  WishlistItem({
    required this.id,
    required this.name,
    required this.price,
    this.discountPrice = 0.0,
    this.image,
    this.currencySymbol = '\$',
  });

  double get effectivePrice => discountPrice > 0 ? discountPrice : price;
}

// Wishlist manager
class WishlistManager extends ChangeNotifier {
  final List<WishlistItem> _items = [];

  List<WishlistItem> get items => List.unmodifiable(_items);

  void addItem(WishlistItem item) {
    if (!_items.any((i) => i.id == item.id)) {
      _items.add(item);
      notifyListeners();
    }
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  bool isInWishlist(String id) {
    return _items.any((item) => item.id == id);
  }
}

// API Configuration
class ApiConfig {
  static String get baseUrl => dotenv.env['API_BASE'] ?? 'https://appifyours.com';
  static const String adminObjectId = '69bd41c5e3bc3eebb36ca763';
  static String get appId => dotenv.env['APP_ID'] ?? 'appifyours_default';
}

// Session Manager
class SessionManager {
  static String? currentUserId;
  static String? authToken;
  static String appName = 'AppifyYours';

  static Future<void> bindAuth({
    required String userId,
    required String token,
  }) async {
    currentUserId = userId;
    authToken = token;
    print('✅ User logged in: $userId');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
  }
}

// Admin Manager
class AdminManager {
  static String? _currentAdminId;

  static Future<String> getCurrentAdminId() async {
    if (_currentAdminId != null) return _currentAdminId!;
    _currentAdminId = ApiConfig.adminObjectId;
    print('✅ Admin ID locked: $_currentAdminId');
    return _currentAdminId!;
  }
}

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Generated E-commerce App',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.blue,
      appBarTheme: const AppBarTheme(
        elevation: 4,
        shadowColor: Colors.black38,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    ),
    home: const SplashScreen(),
    debugShowCheckedModeBanner: false,
  );
}

// Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _appName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _fetchAppNameAndNavigate();
  }

  Future<void> _fetchAppNameAndNavigate() async {
    try {
      final adminId = await AdminManager.getCurrentAdminId();
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/splash?adminId=$adminId&appId=${ApiConfig.appId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          final loadedName = (data['appName'] ?? data['shopName'] ?? 'AppifyYours').toString();
          SessionManager.appName = loadedName;
          setState(() {
            _appName = SessionManager.appName;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _appName = SessionManager.appName;
          });
        }
      }
    } catch (e) {
      print('Error fetching app name: $e');
      if (mounted) {
        setState(() {
          _appName = SessionManager.appName;
        });
      }
    }

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignInPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade400, Colors.blue.shade800],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(
                Icons.shopping_bag,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                _appName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: Colors.white),
              const Spacer(),
              const Text(
                'Powered by AppifyYours',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// Sign In Page
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final adminId = await AdminManager.getCurrentAdminId();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'adminId': adminId,
          'appId': ApiConfig.appId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final token = data['token']?.toString();
          final user = data['user'];
          final userId = (user is Map)
              ? (user['_id']?.toString() ?? user['id']?.toString())
              : null;

          if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
            await SessionManager.bindAuth(userId: userId, token: token);
          }

          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        } else {
          throw Exception(data['error'] ?? 'Sign in failed');
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Invalid credentials');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.shopping_bag,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to continue',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Sign In', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateAccountPage(),
                    ),
                  );
                },
                child: const Text('Create Your Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Create Account Page
class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validateEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$').hasMatch(email);
  }

  bool _validatePhone(String phone) {
    return RegExp(r'^[0-9]{10}$').hasMatch(phone);
  }

  bool _validatePassword(String password) {
    return password.length >= 6;
  }

  Future<void> _createAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (!_validateEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email')),
      );
      return;
    }

    if (!_validatePhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit phone number')),
      );
      return;
    }

    if (!_validatePassword(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final adminId = await AdminManager.getCurrentAdminId();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'password': password,
          'phone': phone,
          'adminId': adminId,
          'shopName': SessionManager.appName,
        }),
      );

      final result = json.decode(response.body);

      setState(() => _isLoading = false);

      if (result['success'] == true) {
        final token = result['token']?.toString();
        final user = result['user'];
        final userId = (user is Map)
            ? (user['_id']?.toString() ?? user['id']?.toString())
            : null;

        if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
          await SessionManager.bindAuth(userId: userId, token: token);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        final data = result['data'];
        String message = 'Failed to create account';
        if (data is Map<String, dynamic> && data['message'] != null) {
          message = data['message'].toString();
        }
        throw Exception(message);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Join Us Today',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your account to get started',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'First Name',
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Last Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
                hintText: '10 digit number',
              ),
              keyboardType: TextInputType.phone,
              maxLength: 10,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email ID',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _createAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Account', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// Delivery Checkout Page (simplified)
class DeliveryCheckoutPage extends StatelessWidget {
  final CartManager cartManager;
  
  const DeliveryCheckoutPage({super.key, required this.cartManager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 100,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            const Text(
              'Order Placed Successfully!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Total: ${PriceUtils.formatPrice(cartManager.finalTotal)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                cartManager.clear();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (route) => false,
                );
              },
              child: const Text('Continue Shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

// ChatBot Page (simplified)
class ChatBotPage extends StatelessWidget {
  final String shopName;
  final String appName;
  
  const ChatBotPage({super.key, required this.shopName, required this.appName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Support - $shopName'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.support_agent,
              size: 100,
              color: Colors.blue,
            ),
            SizedBox(height: 24),
            Text(
              'Chat support coming soon!',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 16),
            Text(
              'For assistance, please email: support@example.com',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// Home Page
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _productGridKey = GlobalKey();
  int _currentPageIndex = 0;
  final CartManager _cartManager = CartManager();
  final WishlistManager _wishlistManager = WishlistManager();
  String _searchQuery = '';
  List<Map<String, dynamic>> _dynamicProductCards = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  Map<String, dynamic> _dynamicStoreInfo = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadDynamicData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToProductGrid() {
    final context = _productGridKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleBuyNow() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryCheckoutPage(cartManager: _cartManager),
      ),
    );
  }

  Future<void> _loadDynamicData() async {
    setState(() => _isLoading = true);
    await _loadDynamicAppConfig();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDynamicAppConfig() async {
    try {
      final adminId = await AdminManager.getCurrentAdminId();
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/get-form?adminId=$adminId&appId=${ApiConfig.appId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final pages = (data['pages'] is List) ? List.from(data['pages']) : <dynamic>[];
          List<Map<String, dynamic>> extractedProducts = [];
          
          if (pages.isNotEmpty && pages.first is Map) {
            final widgets = (pages.first as Map)['widgets'];
            if (widgets is List) {
              for (final w in widgets) {
                final name = (w['name'] ?? '').toString();
                if (name == 'ProductGridWidget' || name == 'Catalog View Card') {
                  final props = w['properties'];
                  if (props is Map && props['productCards'] is List) {
                    extractedProducts.addAll(List<Map<String, dynamic>>.from(props['productCards']));
                  }
                }
              }
            }
          }
          
          final storeInfo = (data['storeInfo'] is Map) ? Map<String, dynamic>.from(data['storeInfo']) : <String, dynamic>{};

          setState(() {
            _dynamicProductCards = extractedProducts;
            _filterProducts(_searchQuery);
            _dynamicStoreInfo = storeInfo;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading dynamic data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onPageChanged(int index) => setState(() => _currentPageIndex = index);

  void _onItemTapped(int index) {
    setState(() {
      _currentPageIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = List.from(_dynamicProductCards);
      } else {
        _filteredProducts = _dynamicProductCards.where((product) {
          final productName = (product['productName'] ?? '').toString().toLowerCase();
          return productName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  String _currencySymbolForProduct(Map<String, dynamic> product) {
    final String rawPrice = (product['price'] ?? '').toString();
    final String detected = PriceUtils.detectCurrency(rawPrice);
    if (detected != '\$') return detected;
    
    final String symbol = (product['currencySymbol'] ?? '').toString();
    if (symbol.isNotEmpty) return symbol;
    
    final String code = (product['currencyCode'] ?? '').toString();
    if (code.isNotEmpty) return PriceUtils.currencySymbolFromCode(code);
    
    return '\$';
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.blue;
    String localFormattedColor = hexColor.toUpperCase().replaceAll('#', '');
    if (localFormattedColor.length == 6) {
      localFormattedColor = 'FF' + localFormattedColor;
    }
    try {
      return Color(int.parse('0x$localFormattedColor'));
    } catch (e) {
      return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _currentPageIndex,
      children: [
        _buildHomePage(),
        _buildCartPage(),
        _buildWishlistPage(),
        _buildProfilePage(),
      ],
    ),
    bottomNavigationBar: _buildBottomNavigationBar(),
    floatingActionButton: _currentPageIndex == 0
        ? FloatingActionButton(
            onPressed: () {
              final shop = (_dynamicStoreInfo['storeName'] ?? 'My Store').toString();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatBotPage(shopName: shop, appName: shop),
                ),
              );
            },
            child: const Icon(Icons.support_agent_outlined),
          )
        : null,
    floatingActionButtonLocation: _currentPageIndex == 0
        ? FloatingActionButtonLocation.startFloat
        : null,
  );

  Widget _buildHomePage() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDynamicData,
      child: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeroBanner(),
              _buildSearchBar(),
              _buildProductGrid(),
              _buildStoreInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    final storeName = _dynamicStoreInfo['storeName'] ?? 'My Store';
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, Colors.blue.shade800],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Welcome to $storeName',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Shop the latest products',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _scrollToProductGrid,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Shop Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: _filterProducts,
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    final products = _searchQuery.isEmpty ? _dynamicProductCards : _filteredProducts;

    if (products.isEmpty) {
      return Container(
        key: _productGridKey,
        padding: const EdgeInsets.all(32),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No products available'),
            ],
          ),
        ),
      );
    }

    return Container(
      key: _productGridKey,
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.7,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _buildProductCard(product, index);
        },
      ),
    );
  }

  // FIXED: _buildProductCard method
  Widget _buildProductCard(Map<String, dynamic> product, int index) {
    final String productId = 'product_$index';
    final String productName = product['productName'] ?? product['name'] ?? 'Product';
    final String rawPrice = (product['price'] ?? '99.99').toString();
    final double basePrice = PriceUtils.parsePrice(rawPrice);
    final String currencySymbol = _currencySymbolForProduct(product);
    final String? image = product['imageAsset'] ?? product['image'];
    final bool isInWishlist = _wishlistManager.isInWishlist(productId);
    
    // FIX APPLIED HERE: quantity: 0 in orElse
    final cartItem = _cartManager.items.firstWhere(
      (item) => item.id == productId,
      orElse: () => CartItem(
        id: productId, 
        name: productName, 
        price: basePrice, 
        currencySymbol: currencySymbol,
        quantity: 0, // This ensures the button shows if item is not in cart
      ),
    );
    
    final int quantityInCart = cartItem.quantity;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: image != null && image.isNotEmpty
                        ? (image.startsWith('data:image/')
                            ? Image.memory(
                                base64Decode(image.split(',')[1]),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 40),
                              )
                            : Image.network(
                                image,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 40),
                              ))
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image, size: 40, color: Colors.grey),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () {
                        if (isInWishlist) {
                          _wishlistManager.removeItem(productId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Removed from wishlist')),
                          );
                        } else {
                          final wishlistItem = WishlistItem(
                            id: productId,
                            name: productName,
                            price: basePrice,
                            image: image,
                            currencySymbol: currencySymbol,
                          );
                          _wishlistManager.addItem(wishlistItem);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to wishlist')),
                          );
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        isInWishlist ? Icons.favorite : Icons.favorite_border,
                        color: Colors.red,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    PriceUtils.formatPrice(basePrice, currency: currencySymbol),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (quantityInCart > 0)
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              if (quantityInCart > 1) {
                                _cartManager.updateQuantity(productId, quantityInCart - 1);
                              } else {
                                _cartManager.removeItem(productId);
                              }
                              setState(() {});
                            },
                            icon: const Icon(Icons.remove, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                quantityInCart.toString(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (quantityInCart < 10) {
                                _cartManager.updateQuantity(productId, quantityInCart + 1);
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.add, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          final newItem = CartItem(
                            id: productId,
                            name: productName,
                            price: basePrice,
                            image: image,
                            currencySymbol: currencySymbol,
                          );
                          _cartManager.addItem(newItem);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to cart')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Add to Cart',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreInfo() {
    final storeName = _dynamicStoreInfo['storeName'] ?? 'My Store';
    final address = _dynamicStoreInfo['address'] ?? '123 Main St';
    final email = _dynamicStoreInfo['email'] ?? 'support@example.com';
    final phone = _dynamicStoreInfo['phone'] ?? '(123) 456-7890';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      child: Card(
        elevation: 2,
        color: const Color(0xFFE3F2FD),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.store, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      storeName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(address, style: const TextStyle(fontSize: 12))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.email, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(email, style: const TextStyle(fontSize: 12))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(phone, style: const TextStyle(fontSize: 12))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping Cart'),
        automaticallyImplyLeading: false,
      ),
      body: ListenableBuilder(
        listenable: _cartManager,
        builder: (context, child) {
          if (_cartManager.items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Your cart is empty', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _cartManager.items.length,
                  itemBuilder: (context, index) {
                    final item = _cartManager.items[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[300],
                              child: item.image != null && item.image!.isNotEmpty
                                  ? (item.image!.startsWith('data:image/')
                                      ? Image.memory(
                                          base64Decode(item.image!.split(',')[1]),
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                        )
                                      : Image.network(
                                          item.image!,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                        ))
                                  : const Icon(Icons.image),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    PriceUtils.formatPrice(item.effectivePrice, currency: item.currencySymbol),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (item.quantity > 1) {
                                      _cartManager.updateQuantity(item.id, item.quantity - 1);
                                    } else {
                                      _cartManager.removeItem(item.id);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Item removed from cart')),
                                      );
                                    }
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.remove, size: 16, color: Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.quantity.toString(),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    if (_cartManager.totalQuantity < 10) {
                                      _cartManager.updateQuantity(item.id, item.quantity + 1);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Only 10 products allowed'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.add, size: 16, color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bill Summary',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          Text(
                            PriceUtils.formatPrice(_cartManager.subtotal, currency: _cartManager.displayCurrencySymbol),
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (_cartManager.totalDiscount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Discount', style: TextStyle(fontSize: 14, color: Colors.grey)),
                            Text(
                              '-' + PriceUtils.formatPrice(_cartManager.totalDiscount, currency: _cartManager.displayCurrencySymbol),
                              style: const TextStyle(fontSize: 14, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('GST (18%)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          Text(
                            PriceUtils.formatPrice(_cartManager.gstAmount, currency: _cartManager.displayCurrencySymbol),
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            PriceUtils.formatPrice(_cartManager.finalTotal, currency: _cartManager.displayCurrencySymbol),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.all(16),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleBuyNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Buy Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWishlistPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
        automaticallyImplyLeading: false,
      ),
      body: _wishlistManager.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Your wishlist is empty', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _wishlistManager.items.length,
              itemBuilder: (context, index) {
                final item = _wishlistManager.items[index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[300],
                      child: item.image != null && item.image!.isNotEmpty
                          ? (item.image!.startsWith('data:image/')
                              ? Image.memory(
                                  base64Decode(item.image!.split(',')[1]),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                )
                              : Image.network(
                                  item.image!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                ))
                          : const Icon(Icons.image),
                    ),
                    title: Text(item.name),
                    subtitle: Text(PriceUtils.formatPrice(item.effectivePrice, currency: item.currencySymbol)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            final cartItem = CartItem(
                              id: item.id,
                              name: item.name,
                              price: item.price,
                              discountPrice: item.discountPrice,
                              image: item.image,
                              currencySymbol: item.currencySymbol,
                            );
                            _cartManager.addItem(cartItem);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to cart')),
                            );
                          },
                          icon: const Icon(Icons.shopping_cart),
                        ),
                        IconButton(
                          onPressed: () {
                            _wishlistManager.removeItem(item.id);
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfilePage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<Map<String, dynamic>>(
                    future: ApiService().getUserProfile(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      }
                      if (snapshot.hasError) {
                        return const Text(
                          'User',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                        );
                      }
                      final userData = snapshot.data ?? {};
                      final firstName = userData['firstName'] ?? '';
                      final lastName = userData['lastName'] ?? '';
                      final displayName = (firstName.isNotEmpty && lastName.isNotEmpty) 
                          ? '$firstName $lastName'
                          : (firstName.isNotEmpty ? firstName : (lastName.isNotEmpty ? lastName : 'User'));
                      return Text(
                        displayName,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(250, 50),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignInPage(),
                        ),
                        (route) => false,
                      );
                    },
                    child: const Text(
                      'Log Out',
                      style: TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentPageIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('${_cartManager.items.length}'),
            isLabelVisible: _cartManager.items.length > 0,
            child: const Icon(Icons.shopping_cart),
          ),
          label: 'Cart',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('${_wishlistManager.items.length}'),
            isLabelVisible: _wishlistManager.items.length > 0,
            child: const Icon(Icons.favorite),
          ),
          label: 'Wishlist',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
