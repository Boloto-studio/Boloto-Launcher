import 'package:flutter/widgets.dart';

import '../ui/crt.dart';
import '../ui/layout.dart';

/// Placeholder for tabs that aren't built yet: a dead channel.
class OffAirScreen extends StatelessWidget {
  const OffAirScreen({
    super.key,
    required this.path,
    required this.channel,
    required this.title,
    required this.subtitle,
  });

  final String path;
  final String channel;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: CrtPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenTopRow(path: path, channel: channel),
              Expanded(
                child: BigMessage(
                  title: title,
                  titleN: title.length,
                  subtitle: subtitle,
                  subtitleN: subtitle.length,
                  delay: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
}
