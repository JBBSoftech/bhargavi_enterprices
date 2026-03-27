import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:appifyours/screens/element_screen/delivery.dart';

// ==================== PRICE UTILS ====================

class PriceUtils {
  static String formatPrice(double price, {String currency = '\$'}) {
    return '$currency${price.toStringAsFixed(2)}';
  }

  static double parsePrice(String priceString) {
    if (priceString.isEmpty) return 0.0;
    String numericString = priceString.replaceAll(RegExp(r'[^\d.]'), '');
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

// ==================== CART MODELS ====================

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
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'discountPrice': discountPrice,
    'quantity': quantity,
    'image': image,
    'currencySymbol': currencySymbol,
  };
  
  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    id: json['id'],
    name: json['name'],
    price: (json['price'] as num).toDouble(),
    discountPrice: (json['discountPrice'] as num?)?.toDouble() ?? 0.0,
    quantity: json['quantity'],
    image: json['image'],
    currencySymbol: json['currencySymbol'] ?? '\$',
  );
}

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
      if (quantity > 0) {
        _items[index].quantity = quantity;
      } else {
        _items.removeAt(index);
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

  double get totalDiscount {
    return _items.fold(0.0, (sum, item) => 
      sum + ((item.price - item.effectivePrice) * item.quantity));
  }

  double get gstAmount {
    return calculateTax(subtotal - totalDiscount, _gstPercentage);
  }

  double get finalTotal {
    return (subtotal - totalDiscount) + gstAmount;
  }

  double calculateTax(double amount, double percentage) {
    return amount * (percentage / 100);
  }
}

// ==================== WISHLIST MODELS ====================

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

// ==================== ADDRESS MODELS ====================

class Address {
  String id;
  String fullName;
  String phone;
  String streetAddress;
  String city;
  String state;
  String postalCode;
  String country;
  bool isDefault;
  String addressType;

  Address({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.streetAddress,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    this.isDefault = false,
    this.addressType = 'home',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'phone': phone,
    'streetAddress': streetAddress,
    'city': city,
    'state': state,
    'postalCode': postalCode,
    'country': country,
    'isDefault': isDefault,
    'addressType': addressType,
  };

  factory Address.fromJson(Map<String, dynamic> json) => Address(
    id: json['id'],
    fullName: json['fullName'],
    phone: json['phone'],
    streetAddress: json['streetAddress'],
    city: json['city'],
    state: json['state'],
    postalCode: json['postalCode'],
    country: json['country'],
    isDefault: json['isDefault'] ?? false,
    addressType: json['addressType'] ?? 'home',
  );

  String get formattedAddress {
    return '$streetAddress, $city, $state $postalCode, $country';
  }
}

// ==================== PAYMENT METHOD ====================

class PaymentMethod {
  final String id;
  final String name;
  final String icon;
  final bool isEnabled;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.icon,
    this.isEnabled = true,
  });
}

// ==================== ORDER MODELS ====================

class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String? image;
  final double discountPrice;
  final String currencySymbol;

  OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.image,
    this.discountPrice = 0.0,
    this.currencySymbol = '\$',
  });

  double get effectivePrice => discountPrice > 0 ? discountPrice : price;
  double get totalPrice => effectivePrice * quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'price': price,
    'quantity': quantity,
    'image': image,
    'discountPrice': discountPrice,
    'currencySymbol': currencySymbol,
  };
}

// ==================== API CONFIGURATION ====================

class ApiConfig {
  static const String baseUrl = 'http://192.168.0.8:5000';
  static const String adminObjectId = '69bd41c5e3bc3eebb36ca763';
  static const String appId = 'APP_ID_HERE';
}

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
  }
}

class AdminManager {
  static String? _currentAdminId;

  static Future<String> getCurrentAdminId() async {
    if (_currentAdminId != null) return _currentAdminId!;
    _currentAdminId = ApiConfig.adminObjectId;
    return _currentAdminId!;
  }
}

// ==================== API SERVICE ====================

class ApiService {
  static const String baseUrl = 'http://192.168.0.8:5000';
  
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

// ==================== DELIVERY CHECKOUT PAGE ====================

class DeliveryCheckoutPage extends StatefulWidget {
  final CartManager cartManager;

  const DeliveryCheckoutPage({
    super.key,
    required this.cartManager,
  });

  @override
  State<DeliveryCheckoutPage> createState() => _DeliveryCheckoutPageState();
}

class _DeliveryCheckoutPageState extends State<DeliveryCheckoutPage> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isProcessingOrder = false;

  // Address Form Controllers
  final _addressFormKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();

  String _selectedAddressType = 'home';
  bool _saveAddressAsDefault = false;

  List<Address> _savedAddresses = [];
  Address? _selectedAddress;
  bool _useNewAddress = true;

  PaymentMethod? _selectedPaymentMethod;
  final List<PaymentMethod> _paymentMethods = const [
    PaymentMethod(id: 'cod', name: 'Cash on Delivery', icon: '💰', isEnabled: true),
    PaymentMethod(id: 'card', name: 'Credit/Debit Card', icon: '💳', isEnabled: true),
    PaymentMethod(id: 'upi', name: 'UPI', icon: '📱', isEnabled: true),
    PaymentMethod(id: 'netbanking', name: 'Net Banking', icon: '🏦', isEnabled: true),
  ];

  String _selectedDeliveryOption = 'standard';
  final Map<String, Map<String, dynamic>> _deliveryOptions = {
    'standard': {'name': 'Standard Delivery', 'days': '3-5 business days', 'cost': 5.99},
    'express': {'name': 'Express Delivery', 'days': '1-2 business days', 'cost': 12.99},
    'overnight': {'name': 'Overnight Delivery', 'days': 'Next day', 'cost': 24.99},
  };

  String _orderNotes = '';
  double _gstPercentage = 18.0;

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _streetAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getStringList('saved_addresses');
      if (addressesJson != null) {
        setState(() {
          _savedAddresses = addressesJson
              .map((json) => Address.fromJson(jsonDecode(json)))
              .toList();
         Address? defaultAddress = _savedAddresses.isNotEmpty
    ? _savedAddresses.firstWhere(
        (addr) => addr.isDefault,
        orElse: () => _savedAddresses.first,
      )
      :null;
          if (defaultAddress != null) {
            _selectedAddress = defaultAddress;
          }
        });
      }
    } catch (e) {
      print('Error loading addresses: $e');
    }
  }

  Future<void> _saveAddress(Address address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getStringList('saved_addresses') ?? [];
      addressesJson.removeWhere((json) {
        final existing = Address.fromJson(jsonDecode(json));
        return existing.id == address.id;
      });
      addressesJson.add(jsonEncode(address.toJson()));
      await prefs.setStringList('saved_addresses', addressesJson);
      setState(() {
        _savedAddresses.add(address);
      });
    } catch (e) {
      print('Error saving address: $e');
    }
  }

  double get _shippingCost => _deliveryOptions[_selectedDeliveryOption]?['cost'] ?? 5.99;
  double get _subtotal => widget.cartManager.subtotal;
  double get _totalDiscount => widget.cartManager.totalDiscount;
  double get _taxAmount => (_subtotal - _totalDiscount) * (_gstPercentage / 100);
  double get _grandTotal => (_subtotal - _totalDiscount) + _taxAmount + _shippingCost;

  bool _isAddressValid() {
    if (_useNewAddress) {
      return _addressFormKey.currentState?.validate() ?? false;
    }
    return _selectedAddress != null;
  }

  void _nextStep() {
    if (_currentStep == 0 && !_isAddressValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in your address details')),
      );
      return;
    }
    if (_currentStep == 1 && _selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method')),
      );
      return;
    }
    setState(() {
      _currentStep++;
    });
  }

  void _previousStep() {
    setState(() {
      _currentStep--;
    });
  }

  Address _getAddress() {
    if (!_useNewAddress && _selectedAddress != null) {
      return _selectedAddress!;
    }
    return Address(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.trim(),
      streetAddress: _streetAddressController.text.trim(),
      city: _cityController.text.trim(),
      state: _stateController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      country: _countryController.text.trim(),
      isDefault: _saveAddressAsDefault,
      addressType: _selectedAddressType,
    );
  }

  Future<void> _placeOrder() async {
    setState(() {
      _isProcessingOrder = true;
    });

    try {
      final address = _getAddress();
      if (_saveAddressAsDefault && _useNewAddress) {
        await _saveAddress(address);
      }

      final orderItems = widget.cartManager.items.map((item) => OrderItem(
        productId: item.id,
        name: item.name,
        price: item.price,
        quantity: item.quantity,
        image: item.image,
        discountPrice: item.discountPrice,
        currencySymbol: item.currencySymbol,
      )).toList();

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'items': orderItems.map((e) => e.toJson()).toList(),
          'shippingAddress': address.toJson(),
          'paymentMethod': _selectedPaymentMethod!.id,
          'deliveryOption': _selectedDeliveryOption,
          'subtotal': _subtotal,
          'discount': _totalDiscount,
          'tax': _taxAmount,
          'shippingCost': _shippingCost,
          'total': _grandTotal,
          'orderNotes': _orderNotes,
          'currencySymbol': widget.cartManager.displayCurrencySymbol,
          'userId': userId,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          widget.cartManager.clear();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => OrderConfirmationPage(
                  orderId: result['orderId'],
                  orderNumber: result['orderNumber'],
                  total: _grandTotal,
                  currencySymbol: widget.cartManager.displayCurrencySymbol,
                  estimatedDelivery: _deliveryOptions[_selectedDeliveryOption]?['days'] ?? '3-5 business days',
                ),
              ),
            );
          }
        } else {
          throw Exception(result['message'] ?? 'Order placement failed');
        }
      } else {
        throw Exception('Failed to place order');
      }
    } catch (e) {
      setState(() {
        _isProcessingOrder = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: ${e.toString()}'),
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
        title: const Text('Checkout'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isProcessingOrder
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing your order...'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stepper(
                    currentStep: _currentStep,
                    onStepTapped: (step) {
                      if (step < _currentStep) {
                        setState(() {
                          _currentStep = step;
                        });
                      }
                    },
                    onStepContinue: _nextStep,
                    onStepCancel: _currentStep > 0 ? _previousStep : null,
                    controlsBuilder: (context, details) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: details.onStepContinue,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Text(_currentStep == 2 ? 'Place Order' : 'Continue'),
                              ),
                            ),
                            if (_currentStep > 0) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: details.onStepCancel,
                                  child: const Text('Back'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(
                        title: const Text('Delivery Address'),
                        content: _buildAddressStep(),
                        isActive: _currentStep >= 0,
                        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                      ),
                      Step(
                        title: const Text('Payment Method'),
                        content: _buildPaymentStep(),
                        isActive: _currentStep >= 1,
                        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                      ),
                      Step(
                        title: const Text('Review Order'),
                        content: _buildReviewStep(),
                        isActive: _currentStep >= 2,
                        state: StepState.indexed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAddressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_savedAddresses.isNotEmpty) ...[
          Row(
            children: [
              Radio<bool>(
                value: false,
                groupValue: _useNewAddress,
                onChanged: (value) {
                  setState(() {
                    _useNewAddress = !value!;
                  });
                },
              ),
              const Text('Use saved address'),
              const SizedBox(width: 20),
              Radio<bool>(
                value: true,
                groupValue: _useNewAddress,
                onChanged: (value) {
                  setState(() {
                    _useNewAddress = value!;
                  });
                },
              ),
              const Text('Enter new address'),
            ],
          ),
          const SizedBox(height: 16),
        ],
        
        if (!_useNewAddress && _savedAddresses.isNotEmpty)
          _buildSavedAddressesList()
        else
          _buildNewAddressForm(),
          
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Options',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ..._deliveryOptions.entries.map((entry) {
                  final isSelected = _selectedDeliveryOption == entry.key;
                  final option = entry.value;
                  return RadioListTile<String>(
                    title: Text(option['name']),
                    subtitle: Text('${option['days']} - ${PriceUtils.formatPrice(option['cost'], currency: widget.cartManager.displayCurrencySymbol)}'),
                    value: entry.key,
                    groupValue: _selectedDeliveryOption,
                    onChanged: (value) {
                      setState(() {
                        _selectedDeliveryOption = value!;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        TextField(
          maxLines: 3,
          onChanged: (value) {
            _orderNotes = value;
          },
          decoration: const InputDecoration(
            labelText: 'Order Notes (Optional)',
            hintText: 'Special instructions for delivery...',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedAddressesList() {
    return Column(
      children: [
        ..._savedAddresses.map((address) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: RadioListTile<Address>(
              title: Text(address.fullName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(address.formattedAddress),
                  const SizedBox(height: 4),
                  Text('Phone: ${address.phone}'),
                ],
              ),
              value: address,
              groupValue: _selectedAddress,
              onChanged: (value) {
                setState(() {
                  _selectedAddress = value;
                });
              },
              secondary: address.isDefault
                  ? Chip(
                      label: const Text('Default', style: TextStyle(fontSize: 10)),
                      backgroundColor: Colors.green.shade100,
                    )
                  : null,
            ),
          );
        }).toList(),
        
        TextButton(
          onPressed: () {
            setState(() {
              _useNewAddress = true;
            });
          },
          child: const Text('+ Add New Address'),
        ),
      ],
    );
  }

  Widget _buildNewAddressForm() {
    return Form(
      key: _addressFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
            validator: (value) => value?.isEmpty ?? true ? 'Please enter your full name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Please enter phone number';
              if (value!.length < 10) return 'Enter valid phone number';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _streetAddressController,
            decoration: const InputDecoration(
              labelText: 'Street Address',
              prefixIcon: Icon(Icons.home),
              border: OutlineInputBorder(),
            ),
            validator: (value) => value?.isEmpty ?? true ? 'Please enter street address' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter city' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _stateController,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter state' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _postalCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Postal Code',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter postal code' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _countryController,
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Please enter country' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedAddressType,
            decoration: const InputDecoration(
              labelText: 'Address Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'home', child: Text('Home')),
              DropdownMenuItem(value: 'work', child: Text('Work')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) {
              setState(() {
                _selectedAddressType = value!;
              });
            },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Save this address for future orders'),
            value: _saveAddressAsDefault,
            onChanged: (value) {
              setState(() {
                _saveAddressAsDefault = value!;
              });
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStep() {
    return Column(
      children: [
        ..._paymentMethods.map((method) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: RadioListTile<PaymentMethod>(
              title: Row(
                children: [
                  Text(method.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Text(method.name),
                ],
              ),
              value: method,
              groupValue: _selectedPaymentMethod,
              onChanged: method.isEnabled ? (value) {
                setState(() {
                  _selectedPaymentMethod = value;
                });
              } : null,
              subtitle: method.id == 'cod' 
                  ? const Text('Pay when you receive your order')
                  : null,
            ),
          );
        }).toList(),
        
        if (_selectedPaymentMethod?.id == 'card')
          _buildCardPaymentForm(),
        
        if (_selectedPaymentMethod?.id == 'upi')
          _buildUPIPaymentForm(),
      ],
    );
  }

  Widget _buildCardPaymentForm() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Card Number',
              prefixIcon: Icon(Icons.credit_card),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Expiry Date (MM/YY)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'CVV',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Cardholder Name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUPIPaymentForm() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'UPI ID (e.g., name@okhdfcbank)',
              prefixIcon: Icon(Icons.qr_code),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final address = _getAddress();
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Items',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  ...widget.cartManager.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey[200],
                            child: item.image != null
                                ? (item.image!.startsWith('data:image/')
                                    ? Image.memory(
                                        base64Decode(item.image!.split(',')[1]),
                                        fit: BoxFit.cover,
                                      )
                                    : Image.network(item.image!, fit: BoxFit.cover))
                                : const Icon(Icons.image),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text('Qty: ${item.quantity}'),
                              ],
                            ),
                          ),
                          Text(
                            PriceUtils.formatPrice(item.totalPrice, currency: item.currencySymbol),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal'),
                      Text(PriceUtils.formatPrice(_subtotal, currency: widget.cartManager.displayCurrencySymbol)),
                    ],
                  ),
                  if (_totalDiscount > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Discount'),
                        Text(
                          '-${PriceUtils.formatPrice(_totalDiscount, currency: widget.cartManager.displayCurrencySymbol)}',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GST ($_gstPercentage%)'),
                      Text(PriceUtils.formatPrice(_taxAmount, currency: widget.cartManager.displayCurrencySymbol)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Shipping (${_deliveryOptions[_selectedDeliveryOption]?['name']})'),
                      Text(PriceUtils.formatPrice(_shippingCost, currency: widget.cartManager.displayCurrencySymbol)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        PriceUtils.formatPrice(_grandTotal, currency: widget.cartManager.displayCurrencySymbol),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shipping Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(address.fullName),
                  Text(address.formattedAddress),
                  Text('Phone: ${address.phone}'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Method',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(_selectedPaymentMethod!.icon, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Text(_selectedPaymentMethod!.name),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (_orderNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Notes',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(_orderNotes),
                  ],
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Place Order',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ORDER CONFIRMATION PAGE ====================

class OrderConfirmationPage extends StatelessWidget {
  final String orderId;
  final String orderNumber;
  final double total;
  final String currencySymbol;
  final String estimatedDelivery;

  const OrderConfirmationPage({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.total,
    required this.currencySymbol,
    required this.estimatedDelivery,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 60,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Order Placed Successfully!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Order #$orderNumber',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount'),
                            Text(
                              PriceUtils.formatPrice(total, currency: currencySymbol),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.delivery_dining, size: 20, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text('Estimated Delivery: $estimatedDelivery'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.email, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            const Text('Order confirmation sent to your email'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const HomePage()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue Shopping',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Order tracking coming soon!')),
                    );
                  },
                  child: const Text('Track Your Order'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== SPLASH SCREEN ====================

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

// ==================== SIGN IN PAGE ====================

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

// ==================== CREATE ACCOUNT PAGE ====================

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

// ==================== CHATBOT PAGE ====================

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

// ==================== HOME PAGE ====================

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
    if (_cartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty!')),
      );
      return;
    }
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
          });
        }
      }
    } catch (e) {
      print('Error loading dynamic data: $e');
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

  Widget _buildProductCard(Map<String, dynamic> product, int index) {
    final String productId = 'product_$index';
    final String productName = product['productName'] ?? product['name'] ?? 'Product';
    final String rawPrice = (product['price'] ?? '99.99').toString();
    final double basePrice = PriceUtils.parsePrice(rawPrice);
    final String currencySymbol = _currencySymbolForProduct(product);
    final String? image = product['imageAsset'] ?? product['image'];
    final bool isInWishlist = _wishlistManager.isInWishlist(productId);
    
    final existingItem = _cartManager.items.firstWhere(
      (item) => item.id == productId,
      orElse: () => CartItem(id: productId, name: productName, price: basePrice, currencySymbol: currencySymbol, quantity: 0),
    );
    final int quantityInCart = existingItem.quantity;

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
                            const SnackBar(content: Text('Removed from wishlist'), duration: Duration(seconds: 1)),
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
                            const SnackBar(content: Text('Added to wishlist'), duration: Duration(seconds: 1)),
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
                  const SizedBox(height: 8),
                  if (quantityInCart > 0)
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (quantityInCart > 1) {
                                _cartManager.updateQuantity(productId, quantityInCart - 1);
                              } else {
                                _cartManager.removeItem(productId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Removed from cart'), duration: Duration(seconds: 1)),
                                );
                              }
                              setState(() {});
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                              ),
                              child: const Icon(Icons.remove, size: 16, color: Colors.black87),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                quantityInCart.toString(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (quantityInCart < 10) {
                                _cartManager.updateQuantity(productId, quantityInCart + 1);
                                setState(() {});
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Maximum 10 items allowed'),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                              ),
                              child: const Icon(Icons.add, size: 16, color: Colors.black87),
                            ),
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
                          final cartItem = CartItem(
                            id: productId,
                            name: productName,
                            price: basePrice,
                            image: image,
                            currencySymbol: currencySymbol,
                          );
                          _cartManager.addItem(cartItem);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to cart'), duration: Duration(seconds: 1)),
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
                          minimumSize: const Size(0, 32),
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
                                        const SnackBar(content: Text('Item removed from cart'), duration: Duration(seconds: 1)),
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
                                    if (item.quantity < 10) {
                                      _cartManager.updateQuantity(item.id, item.quantity + 1);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Only 10 products allowed'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 1),
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
                    'Proceed to Checkout',
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
                              const SnackBar(content: Text('Added to cart'), duration: Duration(seconds: 1)),
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
    return ListenableBuilder(
      listenable: Listenable.merge([_cartManager, _wishlistManager]),
      builder: (context, child) {
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
                isLabelVisible: _cartManager.items.isNotEmpty,
                child: const Icon(Icons.shopping_cart),
              ),
              label: 'Cart',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                label: Text('${_wishlistManager.items.length}'),
                isLabelVisible: _wishlistManager.items.isNotEmpty,
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
      },
    );
  }
}

// ==================== MAIN ====================

void main() => runApp(const MyApp());

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
      cardTheme: const CardTheme(
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
