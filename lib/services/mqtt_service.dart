import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/notification_service.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;
  final String _host = 'broker.hivemq.com'; // Using HiveMQ public broker
  final int _port = 1883;

  Future<void> connect(int userId) async {
    final String clientId = 'chess_user_$userId';
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
      print("MQTT: Starting connection to $_host:$_port");
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
      subscribeToUserMessages(userId);
    } else {
      print(
        'MQTT: client connection failed - status is ${client!.connectionStatus}',
      );
      client!.disconnect();
    }
  }

  void subscribeToUserMessages(int userId) {
    final String topic = 'chess/user/$userId/messages';
    client!.subscribe(topic, MqttQos.atLeastOnce);

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      print(
        'MQTT: Received message on topic: ${c[0].topic}, payload: $payload',
      );

      try {
        final data = jsonDecode(payload);
        final msg = ChatMessage.fromJson(data);
        final int roomId = data['room_id'] ?? 1;

        // We handle the notification here
        NotificationService.showNotification(msg, roomId);
      } catch (e) {
        print('MQTT: Error parsing message - $e');
      }
    });
  }

  void onDisconnected() {
    print('MQTT: OnDisconnected client callback - Client disconnection');
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
}
