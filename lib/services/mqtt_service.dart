import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;
  final String _host = 'broker.hivemq.com'; // Using HiveMQ public broker
  final int _port = 1883;

  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  int? _lastUserId;

  Future<void> connect(int userId) async {
    _lastUserId = userId; // Store for auto-reconnect
    // Generate a unique client ID to avoid conflicts (Main Isolate vs Background Isolate)
    final String uniqueId = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(8);
    final String clientId = 'chess_user_${userId}_$uniqueId';
    client = MqttServerClient(_host, clientId);
    client!.port = _port;
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = onDisconnected;
    client!.onConnected = onConnected;
    client!.onSubscribed = onSubscribed;
    client!.logging(on: true);

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client!.connectionMessage = connMess;

    try {
      print(
        "MQTT: Starting connection to $_host:$_port with clientId: $clientId",
      );
      await client!.connect();
    } on NoConnectionException catch (e) {
      print('MQTT: client exception - $e');
      client!.disconnect();
    } on SocketException catch (e) {
      print('MQTT: socket exception - $e');
      client!.disconnect();
    } catch (e) {
      print('MQTT: Unknown error during connect: $e');
      client!.disconnect();
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT: client connected');
      _subscribeToUserNotifications(userId);
    } else {
      print(
        'MQTT: client connection failed - status is ${client!.connectionStatus}',
      );
      client!.disconnect();
    }
  }

  void _subscribeToUserNotifications(int userId) {
    final String topic = 'chess/user/$userId/notifications';
    print("MQTT: Subscribing to global notifications topic: $topic");
    client!.subscribe(topic, MqttQos.atLeastOnce);

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) async {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      print(
        'MQTT: Received notification on topic: ${c[0].topic}, payload: $payload',
      );

      try {
        final data = jsonDecode(payload);
        final msg = ChatMessage.fromJson(data);
        final int roomId = data['room_id'] ?? 1;

        // Filter out old retained messages (older than 5 minutes to account for clock drift)
        if (data.containsKey('timestamp')) {
          final int msgTimestamp = data['timestamp'];
          final int now = DateTime.now().millisecondsSinceEpoch;
          // Allow up to 5 minutes (300,000 ms) delay/drift
          if (now - msgTimestamp > 300000) {
            print(
              "MQTT: Ignoring OLD message (Age: ${now - msgTimestamp}ms - Limit: 300000ms)",
            );
            return;
          }
        }

        print(
          "MQTT: Parsed message from ${msg.senderName} (Room ID: $roomId, User ID: ${msg.userId})",
        );

        // Retrieve current login status and userId from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final bool isLoggedIn = prefs.getBool('loggedIn') ?? false;
        final int currentUserId = prefs.getInt('userId') ?? 0;

        print(
          "MQTT: Check - LoggedIn: $isLoggedIn, CurrentUser: $currentUserId, Sender: ${msg.userId}",
        );

        if (!isLoggedIn) {
          print("MQTT: User logged out, ignoring notification.");
          return;
        }

        if (msg.userId == currentUserId) {
          print("MQTT: This is our own message, ignoring for notification.");
          return;
        }

        // Check if the user is currently viewing this room
        final int? activeRoom = ChatProvider.currentActiveRoomId;
        if (roomId == activeRoom) {
          print(
            "MQTT: User is currently in room $roomId (active: $activeRoom), suppressing notification.",
          );
          return;
        }

        // We handle the notification here
        print(
          "MQTT: Showing notification for room $roomId from ${msg.senderName}",
        );
        await NotificationService.showNotification(msg, roomId);
      } catch (e) {
        print('MQTT: Error parsing notification - $e');
      }
    });
  }

  void onDisconnected() {
    print('MQTT: OnDisconnected client callback - Client disconnection');
    if (client!.connectionStatus!.disconnectionOrigin ==
        MqttDisconnectionOrigin.solicited) {
      print('MQTT: Disconnection was solicited, not reconnecting.');
      return;
    }
    print(
      'MQTT: Disconnection was unsolicited, attempting to reconnect in 5 seconds...',
    );
    Timer(const Duration(seconds: 5), () {
      if (!isConnected) {
        // We need to retrieve userId to reconnect.
        // Ideally we store it, but for now let's try to get it from Client ID or just fail?
        // Better: Store userId in the class when connecting.
        if (_lastUserId != null) {
          print("MQTT: Auto-reconnecting for user $_lastUserId...");
          connect(_lastUserId!);
        }
      }
    });
  }

  void onConnected() {
    print(
      'MQTT: OnConnected client callback - Client connection was successful',
    );
  }

  void onSubscribed(String topic) {
    print(
      'MQTT: OnSubscribed client callback - Subscription confirmed for topic $topic',
    );
  }

  void disconnect() {
    client?.disconnect();
  }

  void testPublish(int userId) {
    if (client?.connectionStatus?.state != MqttConnectionState.connected) {
      print("MQTT: Cannot test publish, client not connected.");
      return;
    }
    final String topic = 'chess/user/$userId/notifications';
    final builder = MqttClientPayloadBuilder();
    final data = {
      "message": "Test Notification",
      "user_id": 99999, // Fake sender
      "room_id": 99999, // Fake room
      "sender_name": "Test System",
    };
    builder.addString(jsonEncode(data));
    print("MQTT: Publishing TEST message to $topic");
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
}
