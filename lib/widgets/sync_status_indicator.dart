/// Lightweight online indicator (local DB + Supabase sync).
library;

import 'package:flutter/material.dart';

class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Supabase cloud',
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.cloud_done, color: Colors.white, size: 14),
      ),
    );
  }
}
