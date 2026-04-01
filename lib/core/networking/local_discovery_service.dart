import 'package:bonsoir/bonsoir.dart';
import 'package:network_info_plus/network_info_plus.dart';

class LocalDiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  static const String _serviceType = '_chess-game._tcp';

  /// Advertise the local game to others
  Future<void> startBroadcasting(String name, int port) async {
    try {
      final info = NetworkInfo();
      final String? ipAddress = await info.getWifiIP();
      print("[Discovery] Attempting to broadcast. My Local IP: $ipAddress Port: $port");

      if (ipAddress == null || ipAddress.isEmpty) {
        print("[Discovery] Error: Could not retrieve Local IP! Check WiFi/Location permissions.");
        // We still attempt to broadcast, but clients might not be able to connect via IP attribute
      }

      // Create a service and broadcast it
      final service = BonsoirService(
        name: name,
        type: _serviceType,
        port: port,
        attributes: {'ip': ipAddress ?? ""},
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
      print("[Discovery] Successfully broadcasting as $name at port $port");
    } catch (e) {
      print("[Discovery] CRITICAL: Failed to start broadcasting: $e");
      rethrow;
    }
  }

  /// Look for other games on the network
  Future<void> startScanning(Function(BonsoirService) onFound) async {
    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      final discovery = _discovery!;
      await discovery.initialize();
      discovery.eventStream!.listen((BonsoirDiscoveryEvent event) {
        if (event is BonsoirDiscoveryServiceResolvedEvent) {
          print("[Discovery] Found Local Game: ${event.service.name}");
          onFound(event.service);
        }
      }, onError: (e) {
        print("[Discovery] Scanning Error: $e");
      });

      await _discovery!.start();
      print("[Discovery] Scanning for local games...");
    } catch (e) {
      print("[Discovery] Failed to start scanning: $e");
      rethrow;
    }
  }

  void stop() {
    _broadcast?.stop();
    _discovery?.stop();
    print("[Discovery] Services stopped.");
  }
}
