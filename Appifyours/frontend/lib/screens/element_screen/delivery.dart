import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ================================================================
// ⚙️  CONFIG — ONLY EDIT THIS SECTION
// ================================================================
class ShiprocketConfig {
  static const String email    = 'dhavakumar870@gmail.com';
  static const String password = '9!wgMrjyNugCUo04oYlu5aBYmKa#47hV';

  static const Map<String, String> pickupAddress = {
    'name': 'Bhargavi Enterprises',
    'address': '123 Main Street',
    'city': 'Mumbai',
    'state': 'Maharashtra',
    'pincode': '400001',
    'country': 'India',
    'phone': '9876543210',
  };
}

// ================================================================
// 📦  DATA MODELS
// ================================================================
class CourierOption {
  final String courierId;
  final String courierName;
  final double rate;
  final String etd;
  final int estimatedDays;
  final bool codAvailable;
  final bool rtoAvailable;
  final bool surfaceAvailable;
  final bool expressAvailable;

  CourierOption({
    required this.courierId,
    required this.courierName,
    required this.rate,
    required this.etd,
    required this.estimatedDays,
    this.codAvailable = true,
    this.rtoAvailable = true,
    this.surfaceAvailable = true,
    this.expressAvailable = true,
  });

  factory CourierOption.fromJson(Map<String, dynamic> json) {
    return CourierOption(
      courierId: json['courier_id']?.toString() ?? '',
      courierName: json['courier_name']?.toString() ?? '',
      rate: double.tryParse(json['rate']?.toString() ?? '0') ?? 0.0,
      etd: json['etd']?.toString() ?? '',
      estimatedDays: int.tryParse(json['estimated_delivery_days']?.toString() ?? '0') ?? 0,
      codAvailable: json['cod_available'] == true,
      rtoAvailable: json['rto_available'] == true,
      surfaceAvailable: json['surface_available'] == true,
      expressAvailable: json['express_available'] == true,
    );
  }
}

class TimeSlot {
  final String id;
  final String label;
  final String timeRange;
  TimeSlot({required this.id, required this.label, required this.timeRange});
}

class AddressData {
  final String fullName;
  final String phone;
  final String email;
  final String pincode;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String country;

  AddressData({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.pincode,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    this.country = 'India',
  });
}

class OrderResult {
  final bool success;
  final String? orderId;
  final String? shipmentId;
  final String? awbCode;
  final String? courierName;
  final String? message;
  final Map<String, dynamic>? data;

  OrderResult({
    required this.success,
    this.orderId,
    this.shipmentId,
    this.awbCode,
    this.courierName,
    this.message,
    this.data,
  });

  factory OrderResult.fromJson(Map<String, dynamic> json) {
    return OrderResult(
      success: json['success'] == true,
      orderId: json['order_id']?.toString(),
      shipmentId: json['shipment_id']?.toString(),
      awbCode: json['awb_code']?.toString(),
      courierName: json['courier_name']?.toString(),
      message: json['message']?.toString(),
      data: json['response'] ?? json,
    );
  }
}

class PincodeResult {
  final bool serviceable;
  final String message;
  final String city;
  final String state;
  final String country;
  final String pincode;

  PincodeResult({
    required this.serviceable,
    this.message = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.pincode = '',
  });

  factory PincodeResult.fromJson(Map<String, dynamic> json) {
    return PincodeResult(
      serviceable: json['serviceable'] == true,
      message: json['message']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      country: json['country_code']?.toString() ?? '',
      pincode: json['pincode']?.toString() ?? '',
    );
  }
}

// ================================================================
// 🚀  SHIPROCKET API SERVICE
// ================================================================
class ShiprocketService {
  String? _token;
  DateTime? _tokenExpiry;

  Future<bool> _login() async {
    if (_token != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse('https://apiv2.shiprocket.io/v1/external/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': ShiprocketConfig.email,
          'password': ShiprocketConfig.password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['token'] != null) {
          _token = data['token'];
          _tokenExpiry = DateTime.now().add(const Duration(hours: 23));
          return true;
        }
      }
    } catch (e) {
      debugPrint('Shiprocket login error: $e');
    }
    return false;
  }

  Future<PincodeResult> checkPincode(String pincode) async {
    if (!await _login()) return PincodeResult(serviceable: false, message: 'Authentication failed');

    try {
      final response = await http.get(
        Uri.parse('https://apiv2.shiprocket.io/v1/external/courier/serviceability/?pickup_postcode=${ShiprocketConfig.pickupAddress['pincode']}&delivery_postcode=$pincode&weight=0.5&cod=0'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          final first = (data['data'] as List).first;
          return PincodeResult.fromJson(first);
        }
      }
    } catch (e) {
      debugPrint('Pincode check error: $e');
    }
    return PincodeResult(serviceable: false, message: 'Unable to verify pincode');
  }

  Future<List<CourierOption>> getCourierRates({required String pincode, required double orderValue}) async {
    if (!await _login()) return [];

    try {
      final response = await http.get(
        Uri.parse('https://apiv2.shiprocket.io/v1/external/courier/serviceability/?pickup_postcode=${ShiprocketConfig.pickupAddress['pincode']}&delivery_postcode=$pincode&weight=0.5&cod=0&order_value=$orderValue'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          final List<CourierOption> couriers = [];
          for (var item in data['data']) {
            if (item['available'] == true) {
              couriers.add(CourierOption.fromJson(item));
            }
          }
          return couriers;
        }
      }
    } catch (e) {
      debugPrint('Courier rates error: $e');
    }
    return [];
  }

  Future<OrderResult> createOrder({
    required AddressData address,
    required List<Map<String, dynamic>> orderItems,
    required double totalAmount,
    required String paymentMethod,
    required String courierId,
  }) async {
    if (!await _login()) return OrderResult(success: false, message: 'Authentication failed');

    try {
      final orderData = {
        'order_id': 'ORD${DateTime.now().millisecondsSinceEpoch}',
        'order_date': DateTime.now().toIso8601String(),
        'pickup_location': ShiprocketConfig.pickupAddress['name'],
        'channel_id': '',
        'comment': '',
        'billing_customer_name': address.fullName,
        'billing_last_name': '',
        'billing_address': '${address.addressLine1}, ${address.addressLine2}',
        'billing_address_2': '',
        'billing_city': address.city,
        'billing_pincode': address.pincode,
        'billing_state': address.state,
        'billing_country': address.country,
        'billing_email': address.email,
        'billing_phone': address.phone,
        'shipping_is_billing': true,
        'shipping_customer_name': '',
        'shipping_last_name': '',
        'shipping_address': '',
        'shipping_address_2': '',
        'shipping_city': '',
        'shipping_pincode': '',
        'shipping_state': '',
        'shipping_country': '',
        'shipping_email': '',
        'shipping_phone': '',
        'order_items': orderItems,
        'payment_method': paymentMethod,
        'shipping_charges': 0,
        'giftwrap_charges': 0,
        'transaction_charges': 0,
        'total_discount': 0,
        'sub_total': totalAmount,
        'length': 10,
        'breadth': 10,
        'height': 10,
        'weight': 0.5,
      };

      final response = await http.post(
        Uri.parse('https://apiv2.shiprocket.io/v1/external/orders/create/adhoc'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode(orderData),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true && data['order_id'] != null) {
          return await _generateAWB(data['order_id'].toString(), courierId);
        }
        return OrderResult(success: false, message: data['message'] ?? 'Order creation failed');
      }
    } catch (e) {
      debugPrint('Create order error: $e');
    }
    return OrderResult(success: false, message: 'Failed to create order');
  }

  Future<OrderResult> _generateAWB(String orderId, String courierId) async {
    if (!await _login()) return OrderResult(success: false, message: 'Authentication failed');

    try {
      final response = await http.post(
        Uri.parse('https://apiv2.shiprocket.io/v1/external/courier/assign/awb'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'shipment_id': orderId,
          'courier_id': courierId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true && data['response'] != null) {
          final awbData = data['response']['data'];
          return OrderResult(
            success: true,
            orderId: orderId,
            shipmentId: awbData['shipment_id']?.toString(),
            awbCode: awbData['awb_code']?.toString(),
            courierName: awbData['courier_name']?.toString(),
            data: awbData,
          );
        }
      }
    } catch (e) {
      debugPrint('AWB generation error: $e');
    }
    return OrderResult(success: false, message: 'Failed to generate AWB');
  }
}

// ================================================================
// 🛒  CART MODELS
// ================================================================
class CartItem {
  final String id;
  final String name;
  final double price;
  final double effectivePrice;
  final int quantity;
  final String? currencySymbol;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    required this.effectivePrice,
    this.quantity = 1,
    this.currencySymbol,
  });
}

class CartManager extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  String get displayCurrencySymbol => '₹';

  double get subtotal => _items.fold(0.0, (sum, item) => sum + (item.effectivePrice * item.quantity));
  double get totalDiscount => _items.fold(0.0, (sum, item) => sum + ((item.price - item.effectivePrice) * item.quantity));
  double get gstAmount => subtotal * 0.18;
  double get finalTotal => subtotal + gstAmount;

  void addItem(CartItem item) {
    _items.add(item);
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

// ================================================================
// 🏠  HOME PAGE PLACEHOLDER
// ================================================================
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: const Center(child: Text('Home Page')),
  );
}

// ================================================================
// 🎯  MAIN WIDGET
// ================================================================
class DeliveryCheckoutPage extends StatefulWidget {
  final CartManager cartManager;

  const DeliveryCheckoutPage({super.key, required this.cartManager});

  @override
  State<DeliveryCheckoutPage> createState() => _DCPState();
}

class _DCPState extends State<DeliveryCheckoutPage> {
  int _step = 0;

  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pinCtrl   = TextEditingController();
  final _a1Ctrl    = TextEditingController();
  final _a2Ctrl    = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _stCtrl    = TextEditingController();

  bool    _checkingPin = false, _pinOk = false;
  String? _pinError;

  List<CourierOption> _couriers   = [];
  CourierOption?      _selCourier;
  bool                _loadingC   = false;

  final _slots = [
    TimeSlot(id: 's1', label: '🌅 Morning',   timeRange: '9:00 AM – 12:00 PM'),
    TimeSlot(id: 's2', label: '☀️ Afternoon',  timeRange: '12:00 PM – 3:00 PM'),
    TimeSlot(id: 's3', label: '🌆 Evening',    timeRange: '3:00 PM – 6:00 PM'),
    TimeSlot(id: 's4', label: '🌙 Night',      timeRange: '6:00 PM – 9:00 PM'),
  ];
  TimeSlot? _selSlot;
  DateTime  _selDate = DateTime.now().add(const Duration(days: 1));
  String    _pay     = 'prepaid';
  bool      _placing = false;

  final _svc = ShiprocketService();

  String get _currency {
    try {
      final sym = widget.cartManager.displayCurrencySymbol;
      if (sym.isNotEmpty) return sym;
    } catch (_) {}
    return '₹';
  }

  double get _subtotal {
    try { return widget.cartManager.subtotal; } catch (_) { return _cartTotal; }
  }

  double get _gstAmount {
    try { return widget.cartManager.gstAmount; } catch (_) { return 0.0; }
  }

  double get _discountAmount {
    try { return widget.cartManager.totalDiscount; } catch (_) { return 0.0; }
  }

  double get _cartTotal {
    try { return widget.cartManager.finalTotal; } catch (_) { return 0.0; }
  }

  double get _shipping => _selCourier?.rate ?? 0.0;
  double get _grand    => _cartTotal + _shipping;
  List<CartItem> get _items => widget.cartManager.items;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _emailCtrl, _pinCtrl, _a1Ctrl, _a2Ctrl, _cityCtrl, _stCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPinChanged(String pin) {
    _checkPin(pin);
  }

  Future<void> _checkPin(String pin) async {
    if (pin.length != 6) {
      setState(() { _pinOk = false; _pinError = null; _couriers = []; _selCourier = null; });
      return;
    }
    setState(() { _checkingPin = true; _pinError = null; _pinOk = false; });
    final r = await _svc.checkPincode(pin);
    if (!mounted) return;
    if (r.serviceable) {
      if (r.city.isNotEmpty)  _cityCtrl.text = r.city;
      if (r.state.isNotEmpty) _stCtrl.text   = r.state;
      setState(() { _pinOk = true; _checkingPin = false; });
    } else {
      setState(() { _pinOk = false; _pinError = r.message.isNotEmpty ? r.message : 'Delivery not available'; _checkingPin = false; });
    }
  }

  Future<void> _loadCouriers() async {
    setState(() { _loadingC = true; });
    final list = await _svc.getCourierRates(
      pincode: _pinCtrl.text.trim(), orderValue: _cartTotal);
    if (!mounted) return;
    setState(() {
      _couriers   = list;
      _selCourier = list.isNotEmpty ? list.first : null;
      _loadingC   = false;
    });
  }

  bool _validateAddr() {
    if (_nameCtrl.text.trim().isEmpty)         { _snack('Enter your full name');           return false; }
    if (_phoneCtrl.text.trim().length != 10)   { _snack('Enter valid 10-digit phone');     return false; }
    if (_emailCtrl.text.isNotEmpty && !_emailCtrl.text.contains('@')) { _snack('Enter valid email'); return false; }
    if (_pinCtrl.text.trim().length != 6)      { _snack('Enter valid 6-digit pincode');    return false; }
    if (!_pinOk)                               { _snack('Delivery not available at this pincode'); return false; }
    if (_a1Ctrl.text.trim().isEmpty)           { _snack('Enter address line 1');           return false; }
    if (_cityCtrl.text.trim().isEmpty)         { _snack('Enter city');                     return false; }
    if (_stCtrl.text.trim().isEmpty)           { _snack('Enter state');                    return false; }
    return true;
  }

  Future<void> _placeOrder() async {
    if (!_validateAddr()) return;
    setState(() { _placing = true; });

    final addr = AddressData(
      fullName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      pincode: _pinCtrl.text.trim(),
      addressLine1: _a1Ctrl.text.trim(),
      addressLine2: _a2Ctrl.text.trim(),
      city: _cityCtrl.text.trim(),
      state: _stCtrl.text.trim(),
      country: 'India',
    );

    final orderItems = _items.map((i) => {
      'name': i.name,
      'sku': 'SKU${i.id}',
      'units': i.quantity,
      'selling_price': i.effectivePrice,
      'discount': '',
      'tax': '',
      'hsn': '',
    }).toList();

    final result = await _svc.createOrder(
      address: addr,
      orderItems: orderItems,
      totalAmount: _grand,
      paymentMethod: _pay,
      courierId: _selCourier!.courierId,
    );

    if (!mounted) return;
    setState(() { _placing = false; });

    if (result.success) {
      try { widget.cartManager.clearCart(); } catch (_) {}
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OrderSuccessPage(
          result:        result,
          address:       addr,
          courier:       _selCourier!,
          slot:          _selSlot!,
          grandTotal:    _grand,
          paymentMethod: _pay,
          service:       _svc,
        )),
      );
    } else {
      _snack('Order failed: ${result.message}');
      debugPrint('❌ Order failed: ${result.message}');
    }
  }

  void _snack(String m, {Color color = Colors.red}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: color, duration: const Duration(seconds: 5)));

  Future<void> _onNext() async {
    if (_step == 0) {
      if (!_validateAddr()) return;
      await _loadCouriers();
      setState(() { _step = 1; });
    } else if (_step == 1) {
      if (_selSlot    == null) { _snack('Select a time slot'); return; }
      if (_selCourier == null) { _snack('Select a courier');   return; }
      setState(() { _step = 2; });
    } else {
      await _placeOrder();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0.5,
      centerTitle: true,
    ),
    body: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              if (i.isEven) {
                final idx = i ~/ 2;
                final done = idx < _step;
                final active = idx == _step;
                return Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? Colors.green : (active ? Colors.blue : Colors.grey.shade300),
                    border: active ? Border.all(color: Colors.blue, width: 2) : null,
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text('${idx + 1}', style: TextStyle(color: active ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)),
                  ),
                );
              } else {
                return Container(
                  width: 40,
                  height: 2,
                  color: i ~/ 2 < _step ? Colors.green.shade200 : Colors.grey.shade200,
                );
              }
            }),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(bottom: 16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
              Text('Address',  style: TextStyle(fontSize: 12)),
              Text('Shipping', style: TextStyle(fontSize: 12)),
              Text('Payment',  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: _step == 0 ? _addrStep()
               : _step == 1 ? _slotStep()
               : _payStep(),
        ),
      ],
    ),
    bottomNavigationBar: _bottomNav(),
  );

  Widget _addrStep() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        _card('📍 Delivery Address', Column(
          children: [
            _tf(_nameCtrl,  'Full Name *',               Icons.person,        TextInputType.name),
            const SizedBox(height: 12),
            _tf(_phoneCtrl, 'Phone Number *',             Icons.phone,         TextInputType.phone, max: 10),
            const SizedBox(height: 12),
            _tf(_emailCtrl, 'Email (optional)',            Icons.email,         TextInputType.emailAddress),
            const SizedBox(height: 12),
            _tf(_pinCtrl,   'PIN Code *',                  Icons.location_on,   TextInputType.number, max: 6,
              onChanged: _onPinChanged,
              suffixIcon: _checkingPin
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : (_pinOk ? const Icon(Icons.check_circle, color: Colors.green) : null),
              errorText: _pinError,
            ),
            if (_pinOk) ...[
              const SizedBox(height: 12),
              _tf(_a1Ctrl, 'Address Line 1 *',         Icons.home,          TextInputType.streetAddress),
              const SizedBox(height: 12),
              _tf(_a2Ctrl, 'Address Line 2 (Optional)', Icons.apartment,     TextInputType.streetAddress),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _tf(_cityCtrl, 'City *',  Icons.location_city, TextInputType.text)),
                  const SizedBox(width: 12),
                  Expanded(child: _tf(_stCtrl,   'State *', Icons.map,           TextInputType.text)),
                ],
              ),
            ],
          ],
        )),
        const SizedBox(height: 16),
      ],
    ),
  );

  Widget _slotStep() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        _card('📅 Select Delivery Date', Column(
          children: [
            for (int i = 1; i < 7; i++)
              _dateTile(DateTime.now().add(Duration(days: i))),
          ],
        )),
        const SizedBox(height: 16),
        _card('⏰ Select Time Slot', Column(
          children: _slots.map((s) => _slotTile(s)).toList(),
        )),
        const SizedBox(height: 16),
        _card('🚚 Shipping Options', _loadingC
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            : _couriers.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No couriers available for this location')))
                : Column(children: _couriers.map((c) => _courierTile(c)).toList()),
        ),
        const SizedBox(height: 16),
        _card('🧾 Order Summary', _orderSummary()),
      ],
    ),
  );

  Widget _payStep() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        _card('💳 Payment Method', Column(
          children: [
            _payTile('prepaid', '💳 Pay Online',          'Credit/Debit Card, UPI, Wallets'),
            _payTile('cod',     '💰 Cash on Delivery',    'Pay when order arrives'),
          ],
        )),
        const SizedBox(height: 16),
        _card('📦 Order Summary',    _orderDetails()),
        const SizedBox(height: 16),
        _card('📍 Delivery Address', _addrSummary()),
      ],
    ),
  );

  Widget _card(String title, Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _tf(
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType type, {
    int? max,
    void Function(String)? onChanged,
    Widget? suffixIcon,
    String? errorText,
  }) => TextField(
    controller: ctrl,
    keyboardType: type,
    maxLength: max,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      suffixIcon: suffixIcon,
      errorText: errorText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3182CE)),
      ),
    ),
  );

  Widget _dateTile(DateTime dt) {
    final sel = _selDate.day == dt.day && _selDate.month == dt.month;
    return InkWell(
      onTap: () => setState(() => _selDate = dt),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: sel ? const Color(0xFF3182CE) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: sel ? const Color(0xFFEBF8FF) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${dt.day} ${_monthName(dt.month)}',
                 style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            if (sel) const Icon(Icons.check_circle, color: Color(0xFF3182CE)),
          ],
        ),
      ),
    );
  }

  Widget _slotTile(TimeSlot s) {
    final sel = _selSlot?.id == s.id;
    return InkWell(
      onTap: () => setState(() => _selSlot = s),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: sel ? const Color(0xFF3182CE) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: sel ? const Color(0xFFEBF8FF) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                Text(s.timeRange, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            Radio<String>(
              value: s.id,
              groupValue: _selSlot?.id,
              onChanged: (_) => setState(() => _selSlot = s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courierTile(CourierOption c) {
    final sel = _selCourier?.courierId == c.courierId;
    return InkWell(
      onTap: () => setState(() => _selCourier = c),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: sel ? const Color(0xFF3182CE) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: sel ? const Color(0xFFEBF8FF) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.courierName, style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  Text('₹${c.rate.toStringAsFixed(2)} • ${c.etd}',
                       style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Radio<String>(
              value: c.courierId,
              groupValue: _selCourier?.courierId,
              onChanged: (_) => setState(() => _selCourier = c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payTile(String val, String title, String subtitle) {
    final sel = _pay == val;
    final enabled = val == 'prepaid' || (_selCourier?.codAvailable == true);
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? () => setState(() => _pay = val) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(color: sel ? const Color(0xFF3182CE) : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: sel ? const Color(0xFFEBF8FF) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Radio<String>(
                value: val,
                groupValue: _pay,
                onChanged: enabled ? (_) => setState(() => _pay = val) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderSummary() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brow('Item Total', '₹${_cartTotal.toStringAsFixed(2)}'),
      _brow('Shipping (${_selCourier?.courierName ?? ''})', '₹${_shipping.toStringAsFixed(2)}'),
      const Divider(),
      _brow('Grand Total', '₹${_grand.toStringAsFixed(2)}', bold: true),
      if (_selCourier != null) _brow('Est. Delivery', '${_selCourier!.estimatedDays} days', valueColor: Colors.green),
      if (_selSlot    != null) _brow('Time Slot', '${_selSlot!.label} • ${_selSlot!.timeRange}', valueColor: Colors.blue),
    ],
  );

  Widget _orderDetails() => Column(
    children: [
      ..._items.map((i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(i.name, style: const TextStyle(fontSize: 14))),
            Text('$_currency${(i.effectivePrice * i.quantity).toStringAsFixed(2)}'),
          ],
        ),
      )),
      const Divider(),
      _brow('Subtotal', '$_currency${_subtotal.toStringAsFixed(2)}'),
      if (_discountAmount > 0) _brow('Discount', '-$_currency${_discountAmount.toStringAsFixed(2)}', valueColor: Colors.green),
      if (_gstAmount > 0)      _brow('GST',      '$_currency${_gstAmount.toStringAsFixed(2)}'),
      if (_shipping > 0)       _brow('Shipping',  '$_currency${_shipping.toStringAsFixed(2)}'),
      const Divider(),
      _brow('Grand Total', '$_currency${_grand.toStringAsFixed(2)}', bold: true),
    ],
  );

  Widget _addrSummary() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_nameCtrl.text, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('${_a1Ctrl.text}, ${_cityCtrl.text}, ${_stCtrl.text} – ${_pinCtrl.text}',
           style: TextStyle(color: Colors.grey.shade600)),
      Text(_phoneCtrl.text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    ],
  );

  Widget _bottomNav() => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_step > 0) ...[
            TextButton.icon(
              onPressed: () => setState(() => _step--),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton(
            onPressed: _placing ? null : _onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3182CE),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _placing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Placing Order...'),
                    ],
                  )
                : Text(
                    _step == 2 ? '  Place Order  →' : '  Continue  →',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    ),
  );

  String _monthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }

  Widget _brow(String label, String value, {bool bold = false, Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        Text(value, style: TextStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: valueColor ?? Colors.black,
        )),
      ],
    ),
  );
}

// ================================================================
// ✅  ORDER SUCCESS PAGE
// ================================================================
class OrderSuccessPage extends StatelessWidget {
  final OrderResult result;
  final AddressData address;
  final CourierOption courier;
  final TimeSlot slot;
  final double grandTotal;
  final String paymentMethod;
  final ShiprocketService service;

  const OrderSuccessPage({
    super.key,
    required this.result,
    required this.address,
    required this.courier,
    required this.slot,
    required this.grandTotal,
    required this.paymentMethod,
    required this.service,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF0FFF4),
    appBar: AppBar(
      title: const Text('Order Placed!'),
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 80),
                const SizedBox(height: 16),
                const Text('Order Placed Successfully!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF22543D))),
                const SizedBox(height: 8),
                Text('Order ID: ${result.orderId ?? 'N/A'}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                if (result.awbCode != null) ...[
                  const SizedBox(height: 4),
                  Text('AWB Number: ${result.awbCode}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _infoCard('📦 Order Details', [
            _infoRow('Order ID',          result.orderId ?? 'N/A'),
            if (result.awbCode != null) _infoRow('AWB Number', result.awbCode!),
            _infoRow('Courier',           courier.courierName),
            _infoRow('Est. Delivery',     '${courier.estimatedDays} days'),
            _infoRow('Time Slot',         '${slot.label} • ${slot.timeRange}'),
            _infoRow('Payment',           paymentMethod == 'prepaid' ? 'Paid Online' : 'Cash on Delivery'),
            _infoRow('Total Amount',      '₹${grandTotal.toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 16),
          _infoCard('📍 Delivery Address', [
            _infoRow('Name',    address.fullName),
            _infoRow('Address', '${address.addressLine1}, ${address.addressLine2}'),
            _infoRow('City',    '${address.city}, ${address.state} - ${address.pincode}'),
            _infoRow('Phone',   address.phone),
          ]),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
              (route) => false,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Continue Shopping', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );

  Widget _infoCard(String title, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    ),
  );
}
