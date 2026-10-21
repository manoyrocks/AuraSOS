import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/pwa_status.dart';

/// Version, offline readiness (web) and a plain-language privacy summary.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final PwaStatus status = readPwaStatus();
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('About', style: text.titleMedium),
        const SizedBox(height: 8),
        const Text('$kAppName $kAppVersion'),
        if (status.isWeb) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                status.offlineReady
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_download_rounded,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.offlineReady
                      ? 'Ready to use offline'
                      : 'Not cached for offline use yet. Open the app once on a secure (https) '
                          'connection and reload.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: reloadApp,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reload app (applies updates)'),
          ),
        ],
        const SizedBox(height: 4),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Privacy'),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Everything stays on this device: your child\'s profile, the session log and '
                  'your notes. There are no accounts, ads or analytics, and the app sends nothing '
                  'anywhere. Reports are only shared if you copy or save them yourself. '
                  'AuraSOS is a calming aid, not a medical device.',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
