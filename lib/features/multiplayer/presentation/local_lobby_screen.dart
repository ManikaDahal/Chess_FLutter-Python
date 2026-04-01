import 'package:flutter/material.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/networking/local_discovery_service.dart';
import '../../../core/networking/local_game_server.dart';
import '../../../core/utils/const.dart';
import '../../game/presentation/screens/chess_board.dart';

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
  final TextEditingController _nameController = TextEditingController(text: "Guest");
  bool _isHosting = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  Future<void> _startScanning() async {
    // Check if at least one of the necessary discovery permissions is granted
    final locStatus = await Permission.location.status;
    final nearbyStatus = await Permission.nearbyWifiDevices.status;
    
    if (locStatus.isDenied && nearbyStatus.isDenied) {
      // If BOTH are denied, we try to request them one last time
      final result = await [Permission.location, Permission.nearbyWifiDevices].request();
      if (result[Permission.location]?.isDenied == true && result[Permission.nearbyWifiDevices]?.isDenied == true) {
        _showSnackBar("Permissions missing. Discovery might not work.", isError: true);
        // We still try to proceed as some devices might work with limited permissions
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
      final result = await [Permission.location, Permission.nearbyWifiDevices].request();
      if (result[Permission.location]?.isDenied == true && result[Permission.nearbyWifiDevices]?.isDenied == true) {
        _showSnackBar("Permissions required to host game.", isError: true);
        return;
      }
    }

    try {
      final port = await _server.start();
      final String hostName = _nameController.text.isEmpty ? "Local Game" : "${_nameController.text}'s Game";
      
      await _discovery.startBroadcasting(hostName, port);
      
      setState(() {
        _isHosting = true;
      });
      
      Constants.localHostIp = "127.0.0.1";
      Constants.localPort = port;
      
      _showSnackBar("Hosting... Ask your friend to join!");
    } catch (e) {
      _showSnackBar("Error hosting game: $e", isError: true);
    }
  }

  void _joinGame(BonsoirService service) {
    final ip = service.attributes['ip'];
    if (ip != null) {
      Constants.localHostIp = ip;
      Constants.localPort = service.port;
      
      _showSnackBar("Connected to ${service.name}!");
      
      // Navigate to Game Board using local mode
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameBoard(
            currentUserId: 1, // Placeholder for local
            roomId: 9999,    // Constant room for local P2P
            isMultiplayer: true,
            amIWhite: false, // Joiner is usually black
          ),
        ),
      );
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _discovery.stop();
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Local Hotspot Lobby")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Your Display Name",
                hintText: "Enter your name so friends can find you",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              icon: Icon(_isHosting ? Icons.stop : Icons.wifi_tethering),
              label: Text(_isHosting ? "Stop Hosting" : "Host Local Game"),
              onPressed: _isHosting ? () => setState(() => _isHosting = false) : _hostGame,
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("Nearby Games:", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _discoveredGames.length,
              itemBuilder: (context, index) {
                final game = _discoveredGames[index];
                return ListTile(
                  leading: const Icon(Icons.gamepad),
                  title: Text(game.name),
                  subtitle: Text("Tap to Join"),
                  onTap: () => _joinGame(game),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
