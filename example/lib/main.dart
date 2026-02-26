import 'package:flutter/material.dart';
import 'package:flutter_offline_sync_queue/flutter_offline_sync_queue.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: The dispatcher must be a TOP-LEVEL function (not inside a class).
// The @pragma annotation ensures it is preserved in AOT/release builds.
//
// The configFactory callback recreates SyncConfig inside the background
// isolate — this is required because WorkManager runs in a separate Dart VM
// and cannot access the main isolate's memory.
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void myBackgroundDispatcher() {
  BackgroundSyncDispatcher.callbackDispatcher(
    configFactory: () => SyncConfig(
      baseUrl: 'https://api.example.com',
      getAuthToken: () async {
        // In a real app, read the token from SharedPreferences / secure storage.
        return 'Bearer your-saved-token';
      },
      entities: _buildEntities(),
      showSyncNotifications: true,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain model
// ─────────────────────────────────────────────────────────────────────────────
class Order {
  final String item;
  final int qty;
  const Order({required this.item, required this.qty});

  Map<String, dynamic> toJson() => {'item': item, 'qty': qty};
  factory Order.fromJson(Map<String, dynamic> j) =>
      Order(item: j['item'] as String, qty: j['qty'] as int);
}

// ─────────────────────────────────────────────────────────────────────────────
// Entity configs — defined as a function so they can be reused in both the
// main isolate (initialize) and the background isolate (configFactory).
// ─────────────────────────────────────────────────────────────────────────────
List<SyncEntityConfig> _buildEntities() => [
      SyncEntityConfig<Order>(
        boxKey: 'create_orders',
        endpoint: '/orders',
        method: HttpMethod.post,
        toJson: (o) => o.toJson(),
        fromJson: Order.fromJson,
        successStatusCodes: {200, 201},
        extractServerId: (data) => data['id']?.toString(),
        onSuccess: (r) =>
            debugPrint('✅ Order created — serverId: ${r.serverId}'),
        onFailure: (r) => debugPrint('❌ Order failed: ${r.errorMessage}'),
        maxRetries: 3,
      ),
      SyncEntityConfig<Map<String, dynamic>>(
        boxKey: 'update_orders',
        endpoint: '/orders',
        method: HttpMethod.patch,
        buildPathSuffix: (record) => '/${record.serverId}',
        toJson: (m) => m,
        successStatusCodes: {200},
        onSuccess: (r) => debugPrint('✅ Order updated'),
      ),
      SyncEntityConfig<Map<String, dynamic>>(
        boxKey: 'delete_orders',
        endpoint: '/orders',
        method: HttpMethod.delete,
        buildPathSuffix: (record) => '/${record.serverId}',
        toJson: (m) => m,
        successStatusCodes: {200, 204},
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Track foreground/background state so the background isolate can check it.
  AppLifecycleObserver.initialize();

  await OfflineSyncKit.initialize(
    backgroundDispatcher: myBackgroundDispatcher,
    config: SyncConfig(
      baseUrl: 'https://api.example.com',
      getAuthToken: () async => 'Bearer your-token',
      entities: _buildEntities(),
      showSyncNotifications: true,
      onSyncStart: () => debugPrint('🔄 Sync started'),
      onSyncComplete: (ok, fail) => debugPrint('🎉 Sync done ✅$ok ❌$fail'),
    ),
  );

  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// App UI
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineSyncKit Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const OrdersScreen(),
    );
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<SyncRecord> _records = [];
  int _pendingCount = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final records = await OfflineSyncKit.getAllRecords('create_orders');
    final count = await OfflineSyncKit.pendingCount();
    if (mounted) {
      setState(() {
        _records = records;
        _pendingCount = count;
        _loading = false;
      });
    }
  }

  Future<void> _addOrder() async {
    await OfflineSyncKit.queue<Order>(
      boxKey: 'create_orders',
      data: Order(
        item: 'Widget #${DateTime.now().second}',
        qty: 1,
      ),
    );
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order queued for sync ✅')),
      );
    }
  }

  Future<void> _updateOrder(SyncRecord record) async {
    await OfflineSyncKit.queueRaw(
      boxKey: 'update_orders',
      payload: {...record.payload, 'qty': (record.payload['qty'] as int) + 1},
      serverId: record.serverId,
    );
    await _refresh();
  }

  Future<void> _deleteOrder(SyncRecord record) async {
    await OfflineSyncKit.queueRaw(
      boxKey: 'delete_orders',
      payload: {},
      serverId: record.serverId ?? record.localId,
    );
    // Also remove the pending create if it hasn't synced yet.
    await OfflineSyncKit.removeRecord('create_orders', record.localId);
    await _refresh();
  }

  Future<void> _triggerSync() async {
    await OfflineSyncKit.triggerSync();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders — Offline Sync Demo'),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Sync now',
                onPressed: _triggerSync,
              ),
              if (_pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Text(
                    'No orders yet.\nTap + to create one.',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (_, i) {
                      final r = _records[i];
                      final hasError = r.errorMessage != null;
                      return ListTile(
                        leading: Icon(
                          hasError
                              ? Icons.error_outline
                              : r.status == SyncStatus.synced
                                  ? Icons.cloud_done
                                  : Icons.cloud_upload_outlined,
                          color: hasError
                              ? Colors.red
                              : r.status == SyncStatus.synced
                                  ? Colors.green
                                  : Colors.orange,
                        ),
                        title: Text(r.payload['item']?.toString() ?? '—'),
                        subtitle: Text(
                          'qty: ${r.payload['qty']}  •  '
                          '${r.status.name}'
                          '${hasError ? '  •  ${r.errorMessage}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'Increment qty',
                              onPressed: () => _updateOrder(r),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _deleteOrder(r),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOrder,
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
    );
  }
}
