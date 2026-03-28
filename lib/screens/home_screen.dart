// Home screen with bottom nav: Detect | Lands.
library;

import 'package:flutter/material.dart';

import 'detection_screen.dart';
import 'lands_screen.dart';

/// Home screen with bottom nav: Detection | Lands
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DetectionScreen(),
          LandsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt),
            label: 'Detect',
          ),
          NavigationDestination(
            icon: Icon(Icons.terrain),
            label: 'Lands',
          ),
        ],
      ),
    );
  }
}
