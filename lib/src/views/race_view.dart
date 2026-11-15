import 'package:flutter/material.dart';

import '../room_client.dart';

/// レース中の画面(映像は次の段階で実装する)。
class RaceView extends StatelessWidget {
  const RaceView({super.key, required this.client});
  final RoomClient client;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('レース中'));
  }
}
