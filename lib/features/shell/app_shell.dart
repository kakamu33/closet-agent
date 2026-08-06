import 'package:flutter/material.dart';

import '../../newUI/wardrobe_collection_screen.dart';
import '../outfits/presentation/outfits_screen.dart';
import '../settings/presentation/settings_screen.dart';

final shellTabIndex = ValueNotifier<int>(0);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  final _pages = const [
    WardrobeCollectionScreen(),
    OutfitsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() {
        _index = value;
        shellTabIndex.value = value;
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.checkroom_outlined),
          selectedIcon: Icon(Icons.checkroom),
          label: '衣橱',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_mosaic_outlined),
          selectedIcon: Icon(Icons.auto_awesome_mosaic),
          label: '搭配',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '个人',
        ),
      ],
    ),
  );
}
