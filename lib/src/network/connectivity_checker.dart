import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Checks internet connectivity (and optionally VPN) before a sync cycle.
class ConnectivityChecker {
  /// Optional VPN check callback. Return `true` if VPN is active.
  /// Leave `null` to skip the VPN check.
  final Future<bool> Function()? checkVpn;

  const ConnectivityChecker({this.checkVpn});

  /// Returns `true` when internet (and VPN, if configured) are available.
  ///
  /// In debug mode this always returns `true` so you can test syncs on an
  /// emulator without a real network.
  Future<bool> isReady() async {
    if (kDebugMode) return true;

    final results = await Connectivity().checkConnectivity();
    final hasInternet = results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );

    if (!hasInternet) {
      debugPrint('[OfflineSyncKit] No internet connection detected');
      return false;
    }

    if (checkVpn != null) {
      final vpnOk = await checkVpn!();
      if (!vpnOk) {
        debugPrint('[OfflineSyncKit] VPN is not connected');
        return false;
      }
    }

    return true;
  }
}
