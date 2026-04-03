import 'package:flutter/material.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../core/networking/local_discovery_service.dart';
import '../../../core/networking/local_game_server.dart';
import '../../../core/utils/const.dart';
import '../../game/presentation/screens/chess_board.dart';
import '../../game/services/game_websocket_service.dart';

class LocalLobbyScreen extends StatefulWidget {
  final bool isSnakeMode;
  const LocalLobbyScreen({super.key, this.isSnakeMode = false});

  @override
  State<LocalLobbyScreen> createState() => _LocalLobbyScreenState();
}

class _LocalLobbyScreenState extends State<LocalLobbyScreen> {
  final LocalDiscoveryService _discovery = LocalDiscoveryService();
  final LocalGameServer _server = LocalGameServer();
  final List<BonsoirService> _discoveredGames = [];
  final TextEditingController _nameController = TextEditingController(
    text: "Guest",
  );
  bool _isHosting = false;
  bool _waitingForPlayer = false; // New: show "Waiting for opponent..." state
  String? _hostingIp; // Store the Host's IP to display on screen

  @override
  void initState() {
    super.initState();
    // Ensure any stale GameWebsocketService reconnect timer from a previous
    // game session is cancelled before the server is started again.
    GameWebsocketService().disconnect();
    Constants.localHostIp = null;
    Constants.localPort = 8080; // Default local port

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationService();
    });
    _startScanning();
  }

  Future<void> _checkLocationService() async {
    final isLocationEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!isLocationEnabled && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                "Action Required",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            "To discover or host local games, Android requires your device's Location (GPS) to be turned ON.\n\n"
            "Please pull down your top notification bar and turn on:\n\n"
            "1. Location (GPS)\n"
            "2. Mobile Hotspot (if hosting)\n"
            "    -OR- WiFi (if joining)",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "OK, I'll do it",
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _startScanning() async {
    // Check if at least one of the necessary discovery permissions is granted
    final locStatus = await Permission.location.status;
    final nearbyStatus = await Permission.nearbyWifiDevices.status;

    if (locStatus.isDenied && nearbyStatus.isDenied) {
      final result = await [
        Permission.location,
        Permission.nearbyWifiDevices,
      ].request();
      if (result[Permission.location]?.isDenied == true &&
          result[Permission.nearbyWifiDevices]?.isDenied == true) {
        _showSnackBar(
          "Permissions missing. Discovery might not work.",
          isError: true,
        );
      }
    }

    try {
      await _discovery.startScanning((service) {
        if (!mounted) return;
        setState(() {
          if (!_discoveredGames.any((g) => g.name == service.name)) {
            _discoveredGames.add(service);
          }
        });
      });
    } catch (e) {
      _showSnackBar("Discovery Error: $e", isError: true);
    }
  }

  Future<void> _hostGame() async {
    // Check permissions before hosting
    final locStatus = await Permission.location.status;
    final nearbyStatus = await Permission.nearbyWifiDevices.status;

    if (locStatus.isDenied && nearbyStatus.isDenied) {
      final result = await [
        Permission.location,
        Permission.nearbyWifiDevices,
      ].request();
      if (result[Permission.location]?.isDenied == true &&
          result[Permission.nearbyWifiDevices]?.isDenied == true) {
        _showSnackBar("Permissions required to host game.", isError: true);
        return;
      }
    }

    try {
      // Get our local IP — works on both WiFi client AND hotspot mode
      final String? myIp = await _getLocalIp();

      if (myIp == null) {
        _showSnackBar(
          "No network detected. Enable WiFi or create a Hotspot first.",
          isError: true,
        );
        return;
      }

      print("[LocalLobby] Hosting with IP: $myIp");

      // Stop any existing server and disconnect stale sockets first.
      await _server.stop();
      GameWebsocketService().disconnect();
      
      // Artificial delay to let the OS release port 8080
      await Future.delayed(const Duration(milliseconds: 200));

      // Start the server first — port is assigned by OS
      int? port;
      port = await _server.start(
        onClientConnected: () {
          // When a joiner connects, navigate the HOST to GameBoard
          if (!mounted) return;
          Constants.localHostIp = "127.0.0.1";
          Constants.localPort = port!;
          _navigateToGame(amIWhite: true); // Host is always White
        },
      );

      final String hostName = _nameController.text.isEmpty
          ? "Local Game"
          : "${_nameController.text}'s Game";

      await _discovery.startBroadcasting(hostName, port);

      setState(() {
        _hostingIp = myIp;
        _isHosting = true;
        _waitingForPlayer = true;
      });

      _showSnackBar("Hosting as $hostName ($myIp). Waiting for a player...");
    } catch (e) {
      _showSnackBar("Error hosting game: $e", isError: true);
    }
  }

  /// Gets the device's local network IP.
  /// Works whether the device is a WiFi CLIENT or a HOTSPOT HOST.
  Future<String?> _getLocalIp() async {
    String? bestIp;
    
    // 1. Scan all network interfaces (works for hotspot hosts and WiFi)
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        // Skip cellular/mobile data interfaces
        if (interface.name.contains('rmnet') || interface.name.contains('pdp_ip')) continue;

        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback || ip == '0.0.0.0') continue;

          // TOP PRIORITY: Known standard Android Hotspot ranges
          if (ip.startsWith('192.168.43.') || ip.startsWith('172.20.10.')) {
            print("[LocalLobby] Found known Hotspot IP via '${interface.name}': $ip");
            return ip;
          }

          // SECOND PRIORITY: Any 192.168.x or 172.x range WiFi
          if (ip.startsWith('192.168.') || ip.startsWith('172.')) {
            bestIp = ip;
          }

          // THIRD PRIORITY: 10.x.x.x — valid on many Android hotspots & corporate WiFi
          if (ip.startsWith('10.') && bestIp == null) {
            print("[LocalLobby] Found 10.x IP via '${interface.name}': $ip");
            bestIp = ip;
          }
        }
      }
    } catch (e) {
      print("[LocalLobby] NetworkInterface scan failed: $e");
    }

    // 2. Fallback: try network_info_plus WiFi IP
    if (bestIp == null) {
      try {
        final info = NetworkInfo();
        final wifiIp = await info.getWifiIP();
        if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
          bestIp = wifiIp;
        }
      } catch (_) {}
    }

    return bestIp;
  }

  Future<void> _stopHosting() async {
    await _server.stop();
    _discovery.stop();
    // Kill any pending reconnect timer in the GameWebsocketService singleton
    // so it doesn't reconnect to port 8080 when we start hosting again.
    GameWebsocketService().disconnect();
    Constants.localHostIp = null;
    Constants.localPort = 8080; 
    setState(() {
      _isHosting = false;
      _waitingForPlayer = false;
      _hostingIp = null;
    });
    _showSnackBar("Stopped hosting.");
  }

  void _joinGame(BonsoirService service) {
    final attrs = service.attributes;
    final ip = attrs['ip'];
    if (ip == null || ip.isEmpty) {
      _showSnackBar("Could not read host IP from service.", isError: true);
      return;
    }

    Constants.localHostIp = ip;
    Constants.localPort = service.port;

    _showSnackBar("Connecting to ${service.name}...");
    _navigateToGame(amIWhite: false); // Joiner is always Black
  }

  void _navigateToGame({required bool amIWhite}) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameBoard(
          // Host (White) = user 1, Joiner (Black) = user 2.
          // This ensures received moves (sender_id from the OTHER user)
          // don't match our own currentUserId and get correctly applied.
          currentUserId: amIWhite ? 1 : 2,
          roomId: 9999, // Constant room ID for local mode
          isMultiplayer: true,
          amIWhite: amIWhite,
        ),
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _connectManually() {
    final ipController = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16213E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Manual Connect", style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Enter the IP address shown on the Host device.",
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ipController,
                    enabled: !isLoading,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Host's IP Address",
                      hintText: "e.g., 192.168.43.1",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintStyle: const TextStyle(color: Colors.white30),
                      errorText: errorText,
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  
                  if (errorText != null || !isLoading) ...[
                    const SizedBox(height: 20),
                    const Text(
                      "Hotspot Quick-Connect:",
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickLink("Android Hotspot (192.168.43.1)", "192.168.43.1", ipController, setDialogState),
                        _buildQuickLink("iOS Hotspot (172.20.10.1)", "172.20.10.1", ipController, setDialogState),
                        _buildQuickLink("USB Tether (192.168.42.129)", "192.168.42.129", ipController, setDialogState),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.bolt, size: 16, color: Colors.orangeAccent),
                      label: const Text("Scan Standard IPs", style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                      onPressed: isLoading ? null : () async {
                        final List<String> standardIps = ["192.168.43.1", "172.20.10.1", "192.168.42.129", "192.168.1.1"];
                        
                        setDialogState(() {
                          isLoading = true;
                          errorText = null;
                        });

                        for (final ip in standardIps) {
                          try {
                            final socket = await Socket.connect(ip, 8080, timeout: const Duration(milliseconds: 800));
                            socket.destroy();
                            
                            if (!mounted) return;
                            setDialogState(() {
                              ipController.text = ip;
                              isLoading = false;
                            });
                            _showSnackBar("Found game at $ip!");
                            return;
                          } catch (_) {
                            continue;
                          }
                        }
                        
                        if (mounted) {
                          setDialogState(() => isLoading = false);
                          _showSnackBar("No game found on standard hotspot IPs.", isError: true);
                        }
                      },
                    ),
                  ],

                  if (isLoading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
                    const SizedBox(height: 8),
                    const Center(child: Text("Testing connection...", style: TextStyle(color: Colors.white70))),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: Text("Cancel", style: TextStyle(color: isLoading ? Colors.white24 : Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: isLoading ? null : () async {
                  final ip = ipController.text.trim();
                  if (ip.isEmpty) {
                    setDialogState(() => errorText = "Please enter an IP.");
                    return;
                  }

                  final ipRegExp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                  if (!ipRegExp.hasMatch(ip)) {
                    setDialogState(() => errorText = "Invalid IP format.");
                    return;
                  }

                  setDialogState(() {
                    errorText = null;
                    isLoading = true;
                  });

                  try {
                    // INCREASED TIMEOUT: 5s for mobile hotspot stability
                    final socket = await Socket.connect(
                      ip,
                      8080,
                      timeout: const Duration(seconds: 5),
                    );
                    socket.destroy();

                    if (!mounted) return;
                    Navigator.pop(context);
                    Constants.localHostIp = ip;
                    Constants.localPort = 8080;
                    _showSnackBar("Connected to $ip!");
                    _navigateToGame(amIWhite: false);
                  } catch (e) {
                    if (mounted) {
                      setDialogState(() {
                        errorText = "No game found at $ip.\nCheck if Hotspot is active.";
                        isLoading = false;
                      });
                    }
                  }
                },
                child: const Text("Join Game", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickLink(String label, String ip, TextEditingController controller, StateSetter setDialogState) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: const Color(0xFF1565C0), // solid deep blue — clearly visible
      side: const BorderSide(color: Colors.blueAccent, width: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onPressed: () {
        setDialogState(() {
          controller.text = ip;
        });
      },
    );
  }

  @override
  void dispose() {
    _discovery.stop();
    _server.stop(); // Can't await in dispose, but close is fire-and-forget here
    GameWebsocketService().disconnect();
    Constants.localHostIp = null;
    Constants.localPort = 8080;
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F3460),
      appBar: AppBar(
        title: const Text("Local Hotspot Lobby"),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Scan",
            onPressed: () {
              if (!_isHosting) {
                setState(() => _discoveredGames.clear());
                _startScanning();
                _showSnackBar("Scanning for local games...");
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Name field
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              enabled: !_isHosting, // Lock name while hosting
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Your Display Name",
                labelStyle: const TextStyle(color: Colors.white60),
                hintText: "Enter your name so friends can find you",
                hintStyle: const TextStyle(color: Colors.white30),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
                prefixIcon: const Icon(Icons.person, color: Colors.white60),
              ),
            ),
          ),

          // Host button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  _isHosting
                      ? Icons.stop_circle_outlined
                      : Icons.wifi_tethering,
                  color: Colors.white,
                ),
                label: Text(
                  _isHosting ? "Stop Hosting" : "Host Local Game",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isHosting
                      ? Colors.redAccent
                      : Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                onPressed: _isHosting ? _stopHosting : _hostGame,
              ),
            ),
          ),

          // Waiting for player indicator AND IP Display
          if (_waitingForPlayer && _hostingIp != null)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      "Tell your friend to connect to:",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hostingIp!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        letterSpacing: 1.5,
                      ),
                    ),
                    // High-visibility Hotspot Help
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.help_outline, color: Colors.blueAccent, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  "Hotspot Guidelines",
                                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "If the IP above doesn't work, ask your friend to tap 'Join via IP' and select 'Android Hotspot' (192.168.43.1)",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Waiting for opponent to join...",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const Divider(color: Colors.white24),

          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "Nearby Games:",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),

          Expanded(
            child: _discoveredGames.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_find, size: 48, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                          "Scanning for nearby games...",
                          style: TextStyle(color: Colors.white38),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Both devices must be on same WiFi.\nGames joined via IP won't appear here.",
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _discoveredGames.length,
                    itemBuilder: (context, index) {
                      final game = _discoveredGames[index];
                      return Card(
                        color: const Color(0xFF16213E),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.gamepad,
                            color: Colors.blueAccent,
                          ),
                          title: Text(
                            game.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            "Tap to Join · Port ${game.port}",
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white24,
                            size: 16,
                          ),
                          onTap: () => _joinGame(game),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _isHosting
          ? null
          : FloatingActionButton.extended(
              onPressed: _connectManually,
              backgroundColor: Colors.orangeAccent,
              icon: const Icon(Icons.link, color: Colors.white),
              label: const Text(
                "Join via IP",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
