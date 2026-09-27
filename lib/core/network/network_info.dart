import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements NetworkInfo {
  final InternetConnectionChecker connectionChecker;
  final Connectivity connectivity;

  NetworkInfoImpl(this.connectionChecker, this.connectivity);

  static const _cacheFor = Duration(seconds: 4);
  DateTime? _cachedAt;
  bool? _cachedValue;

  @override
  Future<bool> get isConnected async {
    final cachedAt = _cachedAt;
    final cachedValue = _cachedValue;
    if (cachedValue != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheFor) {
      return cachedValue;
    }

    final connected = await _probe();
    _cachedValue = connected;
    _cachedAt = DateTime.now();
    return connected;
  }

  Future<bool> _probe() async {
    final interfaces = await connectivity.checkConnectivity();
    final hasRadio = interfaces.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn ||
          result == ConnectivityResult.other,
    );
    if (!hasRadio) return false;

    try {
      return await connectionChecker.hasConnection.timeout(
        const Duration(milliseconds: 900),
      );
    } catch (_) {
      return false;
    }
  }
}
