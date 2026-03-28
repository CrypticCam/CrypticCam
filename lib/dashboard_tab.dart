import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'chat_list_screen.dart';
import 'profile_tab.dart';

class DashboardTab extends StatefulWidget {
  final String currentUsername;
  const DashboardTab({super.key, required this.currentUsername});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  int _selectedIndex = 0;

  late List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeScreen(currentUsername: widget.currentUsername), //
      const ChatListScreen(),
      const ProfileTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),

      // --- 3 SEKMELİ DİNAMİK NAVİGASYON BARI ---
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),

          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          selectedItemColor: const Color(0xFFADCFD0),
          unselectedItemColor: isDark ? Colors.white24 : Colors.grey[400],

          showSelectedLabels: true,
          showUnselectedLabels: false,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          iconSize: 26,

          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: "Sohbetler",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded), // Kişiler için ikon
              activeIcon: Icon(Icons.people_rounded),
              label: "Kişiler",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: "Profil",
            ),
          ],
        ),
      ),
    );
  }
}