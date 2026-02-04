import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Global refresh tick for product-based feeds.
///
/// Any screen that shows product lists can `ref.watch(productsRefreshTickProvider)`
/// to rebuild/reload when the user explicitly refreshes:
/// - Pull-to-refresh
/// - Re-tapping the active Home tab (when already on /home)
final productsRefreshTickProvider = StateProvider<int>((ref) => 0);
