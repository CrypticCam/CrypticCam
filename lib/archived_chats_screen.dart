import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';

class ArchivedChatsScreen extends StatelessWidget {
  final String currentUsername;
  const ArchivedChatsScreen({super.key, required this.currentUsername});

  @override
  Widget build(BuildContext context) {
    // Mevcut temanın karanlık olup olmadığını kontrol ediyoruz
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // DİNAMİK: Arka plan rengi temadan gelir
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
            "Arşivlenmiş Mesajlar",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white70 : Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUsername)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // ARŞİVLENENLERİ FİLTRELE
          final archivedChats = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final List archivedBy = data['archivedBy'] ?? [];
            return archivedBy.contains(currentUsername);
          }).toList();

          if (archivedChats.isEmpty) {
            return Center(
                child: Text(
                    "Arşivlenmiş bir mesaj bulunmuyor. ",
                    style: TextStyle(color: isDark ? Colors.white24 : Colors.grey)
                )
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: archivedChats.length,
            itemBuilder: (context, index) {
              final chatDoc = archivedChats[index];
              final participants = chatDoc['participants'] as List;
              final friendName = participants.firstWhere((p) => p != currentUsername);

              return _buildArchivedTile(context, friendName, chatDoc.id, isDark);
            },
          );
        },
      ),
    );
  }

  // --- ARŞİV KARTI ---
  Widget _buildArchivedTile(BuildContext context, String friendName, String chatId, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4)
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const CircleAvatar(
            backgroundColor: Color(0xFFADCFD0), // Mint Yeşili
            child: Icon(Icons.person, color: Colors.white)
        ),
        title: Text(
            "@$friendName",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87
            )
        ),
        subtitle: Text(
            "Arşivden çıkarmak için sağdaki butona dokun",
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 11)
        ),
        trailing: IconButton(
          icon: Icon(Icons.unarchive_outlined, color: const Color(0xFFFBC8B6)),
          onPressed: () async {
            await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
              'archivedBy': FieldValue.arrayRemove([currentUsername])
            });
          },
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: friendName))),
      ),
    );
  }
}