import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();

  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged
      .map((results) => _isConnected(results));

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  bool _isConnected(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        results.any((r) =>
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.vpn);
  }
}
