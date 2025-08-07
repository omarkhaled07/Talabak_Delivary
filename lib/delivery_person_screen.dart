import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryPersonScreen extends StatefulWidget {
  const DeliveryPersonScreen({super.key});

  @override
  State<DeliveryPersonScreen> createState() => _DeliveryPersonScreenState();
}

class _DeliveryPersonScreenState extends State<DeliveryPersonScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _deliveryStatus = 'offline'; // 'offline', 'online', 'busy'
  bool _isLoading = true;
  bool _isDeliveryPerson = false;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _assignedOrders = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // تحديث البيانات عند استلام إشعار جديد
      _refreshData();

      // عرض إشعار للمستخدم
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(message.notification?.title ?? 'New Order'),
          content: Text(message.notification?.body ?? 'You have a new delivery order'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _loadInitialData() async {
    await _verifyUserRoleAndLoadData();
  }

  Future<void> _refreshData() async {
    await _verifyUserRoleAndLoadData();
  }

  Future<void> _verifyUserRoleAndLoadData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userRole = userDoc.data()?['role'];

        if (userRole == 'delivery') {
          setState(() {
            _isDeliveryPerson = true;
            _userData = userDoc.data()!;
            _deliveryStatus = userDoc.data()?['deliveryStatus'] ?? 'offline';
          });
          await _loadAssignedOrders(user.uid);
        }
      }
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAssignedOrders(String deliveryId) async {
    try {
      final ordersSnapshot = await _firestore
          .collection('orders')
          .where('assignedToId', isEqualTo: deliveryId)
          .where('status', whereIn: ['assigned', 'in_progress'])
          .orderBy('updatedAt', descending: true)
          .get();

      setState(() {
        _assignedOrders = ordersSnapshot.docs
            .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            ...data,
            'id': doc.id,
            'orderType': _determineOrderType(data),
          };
        })
            .toList();
      });
    } catch (e) {
      print('Error loading orders: $e');
    }
  }

  String _determineOrderType(Map<String, dynamic> orderData) {
    if (orderData['restaurantInfo'] != null || orderData['items'] != null) {
      return 'restaurant';
    } else if (orderData['pharmacyId'] != null) {
      return 'pharmacy';
    } else if (orderData['type'] == 'delivery' || orderData['orderType'] == 'delivery') {
      return 'delivery';
    }
    return 'unknown';
  }

  Widget _getOrderTypeIcon(String orderType) {
    switch (orderType) {
      case 'restaurant':
        return const Icon(Icons.restaurant, color: Colors.orange);
      case 'pharmacy':
        return const Icon(Icons.local_pharmacy, color: Colors.green);
      case 'delivery':
        return const Icon(Icons.delivery_dining, color: Colors.blue);
      default:
        return const Icon(Icons.shopping_bag, color: Colors.grey);
    }
  }

  String _getOrderTypeName(String orderType) {
    switch (orderType) {
      case 'restaurant': return 'طلب مطعم';
      case 'pharmacy': return 'طلب صيدلية';
      case 'delivery': return 'طلب توصيل';
      default: return 'طلب غير معروف';
    }
  }

  Future<void> _updateDeliveryStatus(String newStatus) async {
    try {
      final user = _auth.currentUser;
      if (user == null || !_isDeliveryPerson) return;

      await _firestore.collection('users').doc(user.uid).update({
        'deliveryStatus': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _deliveryStatus = newStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'online'
                ? 'أنت الآن متاح لتلقي الطلبات'
                : newStatus == 'busy'
                ? 'أنت الآن مشغول بتوصيل طلب'
                : 'أنت الآن غير متصل',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحديث الحالة: ${e.toString()}',
              textDirection: TextDirection.rtl),
        ),
      );
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      if (!_isDeliveryPerson) return;

      await _firestore.collection('orders').doc(orderId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (newStatus == 'completed') {
        await _updateDeliveryStatus('online');
      }

      await _loadAssignedOrders(_auth.currentUser!.uid);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'in_progress'
                ? 'تم بدء توصيل الطلب'
                : 'تم تسليم الطلب بنجاح',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحديث حالة الطلب: ${e.toString()}',
              textDirection: TextDirection.rtl),
        ),
      );
    }
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              value ?? 'غير متوفر',
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final isInProgress = status == 'in_progress';
    final orderType = order['orderType'] ?? 'unknown';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: _getOrderTypeIcon(orderType),
        title: Text('طلب #${order['id'].substring(0, 6)}',
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('النوع: ${_getOrderTypeName(orderType)}',
                textDirection: TextDirection.rtl),
            Text('الحالة: ${_getStatusText(status)}',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: _getStatusColor(status),
                    fontWeight: FontWeight.bold)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (orderType == 'restaurant')
                  _buildRestaurantOrderDetails(order),
                if (orderType == 'pharmacy')
                  _buildPharmacyOrderDetails(order),
                if (orderType == 'delivery')
                  _buildDeliveryOrderDetails(order),

                _buildDetailRow('وقت الإنشاء:', _formatTimestamp(order['orderTime'])),
                if (order['updatedAt'] != null)
                  _buildDetailRow('آخر تحديث:', _formatTimestamp(order['updatedAt'])),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (!isInProgress)
                      ElevatedButton(
                        onPressed: () {
                          _updateOrderStatus(order['id'], 'in_progress');
                          _updateDeliveryStatus('busy');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('بدء التوصيل',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ElevatedButton(
                      onPressed: () => _updateOrderStatus(order['id'], 'completed'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('تم التسليم',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && !_isDeliveryPerson) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('لوحة الموزع',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xff112b16),
        ),
        body: Center(
          child: Column(
            children: [
              const Text('هذه الصفحة متاحة فقط للموزعين',
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 100,),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
                tooltip: 'تسجيل الخروج',
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('لوحة الموزع',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff112b16),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            // قسم معلومات الموزع
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey[200],
                    child: _userData?['profileImage'] != null &&
                        _userData!['profileImage'].isNotEmpty
                        ? ClipOval(
                      child: Image.network(
                        _userData!['profileImage'],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    )
                        : const Icon(Icons.person, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(_userData?['name'] ?? 'غير معروف',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_userData?['phone'] ?? 'لا يوجد رقم هاتف'),
                  const SizedBox(height: 16),
                  _buildRatingSection(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatusButton(
                          'offline', 'غير متصل', Icons.offline_bolt),
                      _buildStatusButton(
                          'online', 'متصل', Icons.check_circle),
                      _buildStatusButton(
                          'busy', 'مشغول', Icons.delivery_dining),
                    ],
                  ),
                ],
              ),
            ),
            // نهاية قسم معلومات الموزع

            Expanded(
              child: _assignedOrders.isEmpty
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('لا توجد طلبات مخصصة لك حالياً',
                      textDirection: TextDirection.rtl),
                ),
              )
                  : ListView.builder(
                itemCount: _assignedOrders.length,
                itemBuilder: (context, index) {
                  return _buildOrderCard(_assignedOrders[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton(String status, String label, IconData icon) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon,
              color: _deliveryStatus == status ? Colors.green : Colors.grey),
          onPressed: () => _updateDeliveryStatus(status),
        ),
        Text(label,
            style: TextStyle(
                color: _deliveryStatus == status ? Colors.green : Colors.grey)),
      ],
    );
  }

  Future<void> _signOut() async {
    try {
      if (_isDeliveryPerson) {
        await _updateDeliveryStatus('offline');
      }

      await _auth.signOut();
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تسجيل الخروج: ${e.toString()}',
              textDirection: TextDirection.rtl),
        ),
      );
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار';
      case 'assigned': return 'تم التعيين';
      case 'in_progress': return 'قيد التوصيل';
      case 'completed': return 'مكتمل';
      case 'cancelled': return 'ملغي';
      default: return status;
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'غير معروف';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'in_progress': return Colors.blue;
      case 'assigned': return Colors.orange;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildRestaurantOrderDetails(Map<String, dynamic> orderData) {
    final restaurantInfo = orderData['restaurantInfo'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildDetailRow('المطعم:', restaurantInfo['restaurantName'] ?? 'غير معروف'),
        _buildDetailRow('عنوان المطعم:', restaurantInfo['restaurantAddress']),
        _buildDetailRow('هاتف المطعم:', restaurantInfo['restaurantPhone']),

        const SizedBox(height: 8),
        const Text('الوجبات المطلوبة:',
            style: TextStyle(fontWeight: FontWeight.bold),
            textDirection: TextDirection.rtl),

        ...(orderData['items'] as List<dynamic>? ?? []).map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${item['quantity']} × ${item['name']} - ${item['price']} ج.م',
                    textDirection: TextDirection.rtl),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 8),
        _buildDetailRow('الإجمالي:', '${orderData['total'] ?? '0'} ج.م'),
        _buildDetailRow('اسم العميل:', orderData['userName'] ?? 'غير معروف'),
        _buildDetailRow('هاتف العميل:', orderData['deliveryPhone']),
        _buildDetailRow('عنوان التسليم:', orderData['deliveryAddress']),
        _buildDetailRow('ملاحظات:', orderData['notes'] ?? 'لا توجد'),
      ],
    );
  }

  Widget _buildPharmacyOrderDetails(Map<String, dynamic> orderData) {
    final prescriptionImageUrl = orderData['prescriptionImageUrl'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildDetailRow('الصيدلية:', orderData['pharmacyName'] ?? 'غير معروف'),

        if (prescriptionImageUrl != null && prescriptionImageUrl.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('صورة الوصفة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _openPrescriptionImage(prescriptionImageUrl),
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Image.network(
                          prescriptionImageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const CircularProgressIndicator();
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.error, color: Colors.red);
                          },
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'انقر لعرض الصورة',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        else
          _buildDetailRow('صورة الوصفة:', 'لا توجد'),

        const SizedBox(height: 8),
        _buildDetailRow('الإجمالي:', '${orderData['total'] ?? '0'} ج.م'),
        _buildDetailRow('اسم العميل:', orderData['userName'] ?? 'غير معروف'),
        _buildDetailRow('هاتف العميل:', orderData['deliveryPhone']),
        _buildDetailRow('عنوان التسليم:', orderData['deliveryAddress']),
        _buildDetailRow('ملاحظات:', orderData['notes'] ?? 'لا توجد'),
      ],
    );
  }

  Widget _buildDeliveryOrderDetails(Map<String, dynamic> orderData) {
    // تحديد موقع الاستلام من أي حقل متاح
    final pickupLocation = orderData['pickupLocation'] ??
        orderData['location'] ??
        orderData['coordinates']?['pickup'];

    // تحديد موقع التسليم من أي حقل متاح
    final dropoffLocation = orderData['dropoffLocation'] ??
        orderData['location'] ??
        orderData['coordinates']?['dropoff'];

    final pickupAddress = orderData['pickupAddress'] ?? 'موقع على الخريطة';
    final deliveryAddress = orderData['deliveryAddress'] ?? 'موقع على الخريطة';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildDetailRow('مكان الاستلام:', pickupAddress),
        if (pickupLocation != null)
          _buildLocationButton('إحداثيات الاستلام:', pickupLocation),

        _buildDetailRow('مكان التسليم:', deliveryAddress),
        if (dropoffLocation != null)
          _buildLocationButton('إحداثيات التسليم:', dropoffLocation),

        _buildDetailRow('قيمة الطلب:', '${orderData['total'] ?? '0'} ج.م'),
        _buildDetailRow('اسم العميل:', orderData['userName'] ?? 'غير معروف'),
        _buildDetailRow('هاتف العميل:', orderData['deliveryPhone']),
        _buildDetailRow('ملاحظات:', orderData['notes'] ?? 'لا توجد'),
      ],
    );
  }

  Widget _buildLocationButton(String label, dynamic location) {
    GeoPoint? geoPoint;

    // تحويل الموقع إلى GeoPoint بغض النظر عن نوع التخزين
    if (location is GeoPoint) {
      geoPoint = location;
    } else if (location is Map<String, dynamic>) {
      if (location['latitude'] != null && location['longitude'] != null) {
        geoPoint = GeoPoint(location['latitude'], location['longitude']);
      }
    }

    if (geoPoint == null) {
      return _buildDetailRow(label, 'تنسيق غير معروف');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => _launchMaps(geoPoint!.latitude, geoPoint.longitude),
            child: Text(
              '${geoPoint.latitude.toStringAsFixed(6)}° N, ${geoPoint.longitude.toStringAsFixed(6)}° E',
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _launchMaps(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح الخريطة', textDirection: TextDirection.rtl),
        ),
      );
    }
  }

  Future<void> _openPrescriptionImage(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          content: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.error);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    }
  }

  Widget _buildRatingInfo(Map<String, dynamic> orderData) {
    final rating = orderData['deliveryRating'];
    final feedback = orderData['deliveryFeedback'];

    if (rating == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 8),
        const Text('تقييم العميل:',
            style: TextStyle(fontWeight: FontWeight.bold),
            textDirection: TextDirection.rtl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: List.generate(5, (index) {
            return Icon(
              index < rating ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 20,
            );
          }),
        ),
        if (feedback?.isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          const Text('ملاحظات العميل:',
              style: TextStyle(fontWeight: FontWeight.bold),
              textDirection: TextDirection.rtl),
          Text(feedback!,
              textDirection: TextDirection.rtl),
        ],
      ],
    );
  }
  Widget _buildRatingSection() {
    final ratingCount = _userData?['deliveryRatingCount'] ?? 0;
    final averageRating = _userData?['deliveryAverageRating'] ?? 0.0;

    if (ratingCount == 0) {
      return const Column(
        children: [
          Text('لا توجد تقييمات بعد',
              style: TextStyle(color: Colors.grey)),
          SizedBox(height: 8),
        ],
      );
    }

    return Column(
      children: [
        const Text('تقييماتك',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        RatingBarIndicator(
          rating: averageRating,
          itemBuilder: (context, index) => const Icon(
            Icons.star,
            color: Colors.amber,
          ),
          itemCount: 5,
          itemSize: 30.0,
          direction: Axis.horizontal,
        ),
        const SizedBox(height: 8),
        Text(
          '$averageRating من 5 (بناءً على $ratingCount تقييم${ratingCount > 1 ? 'ات' : ''})',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

}