import 'package:bonsoir/bonsoir.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';

class LocalDiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  static const String _serviceType = '_chess-game._tcp';

  /// Advertise the local game to others
  Future<void> startBroadcasting(String name, int port) async {
    try {
      // Improved IP detection: scan all interfaces to find the Host IP (even on Hotspot)
      String? ipAddress;
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final ip = addr.address;
            // Prefer Hotspot IPs (192.168.43.1, etc.) or common private ranges
            if (!addr.isLoopback && ip != '0.0.0.0') {
               if (ip.startsWith('192.168.43.') || ip.startsWith('172.20.10.')) {
                 ipAddress = ip;
                 break;
               }
               // Accept any private range including 10.x (some Android hotspots use it)
               if (ip.startsWith('192.168.') || ip.startsWith('172.') || ip.startsWith('10.')) {
                 ipAddress ??= ip;
               }
            }
          }
          if (ipAddress?.startsWith('192.168.43.') == true) break;
        }
      } catch (e) {
        print("[Discovery] Interface scan failed: $e");
      }

      // Final fallback if manual scan failed
      ipAddress ??= await NetworkInfo().getWifiIP();

      print("[Discovery] Attempting to broadcast. My Local IP: $ipAddress Port: $port");

      if (ipAddress == null || ipAddress.isEmpty) {
        print("[Discovery] Error: Could not retrieve Local IP! Check WiFi/Location permissions.");
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
      if (_discovery != null) {
        _discovery!.stop();
        _discovery = null;
      }
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
