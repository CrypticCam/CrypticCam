import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _fetchMyUsername();
  }

  // ---  KULLANICI ADI ÇEKME ---
  Future<void> _fetchMyUsername() async {
    final user = _auth.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', isEqualTo: user.uid)
          .limit(1).get();
      if (userDoc.docs.isNotEmpty && mounted) {
        setState(() => _currentUsername = userDoc.docs.first.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUsername == null) return const Center(child: CircularProgressIndicator());
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
            "Kişiler",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 1. ADIM: Takip ettiğin kişilerin listesini dinle
        stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername).collection('following').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return _buildEmptyState(isDark);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final friendName = snapshot.data!.docs[index].id;

              // 2. ADIM: Karşılıklı takip kontrolü (Seni takip ediyor mu?)
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername).collection('followers').doc(friendName).snapshots(),
                builder: (context, followerSnap) {
                  if (!followerSnap.hasData || !followerSnap.data!.exists) return const SizedBox.shrink();

                  return _buildContactTile(friendName, context, isDark);
                },
              );
            },
          );
        },
      ),
    );
  }

  // ---  KİŞİ KARTI TASARIMI ---
  Widget _buildContactTile(String username, BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.02), blurRadius: 10)],
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: username))),

        // --- DİNAMİK PROFİL FOTOĞRAFI (BASE64) ---
        leading: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(username).snapshots(),
          builder: (context, userSnap) {
            String? base64Str;
            if (userSnap.hasData && userSnap.data!.exists) {
              base64Str = (userSnap.data!.data() as Map<String, dynamic>)['profilePic'];
            }

            bool hasImg = base64Str != null && base64Str.trim().isNotEmpty;

            return CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFFBC8B6),
              backgroundImage: hasImg ? MemoryImage(base64Decode(base64Str!.trim())) : null,
              child: !hasImg ? const Icon(Icons.person, color: Colors.white) : null,
            );
          },
        ),

        title: Text(
            "@$username",
            style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)
        ),
        subtitle: Text(
          "Sır paylaşmak için hazır ",
          style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFADCFD0)), // Mint Yeşili
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 60, color: isDark ? Colors.white12 : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "Henüz karşılıklı takipçiniz yok.\nArkadaşlarını bulmaya ne dersin?",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white24 : Colors.grey),
          ),
        ],
      ),
    );
  }
}