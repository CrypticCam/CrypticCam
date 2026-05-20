import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';

class ArchivedChatsScreen extends StatelessWidget {
  final String currentUsername;
  const ArchivedChatsScreen({super.key, required this.currentUsername});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Arşivlenmiş Mesajlar",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white70 : Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // İki farklı kaynağı (Stream) tek ekranda göstermek için CustomScrollView kullanıyoruz
      body: CustomScrollView(
        slivers: [
          // 1. BÖLÜM: ARŞİVLENMİŞ BİREBİR SOHBETLER
          _buildSliverSection("Birebir Sohbetler", "chats", false, isDark),

          // 2. BÖLÜM: ARŞİVLENMİŞ GRUPLAR
          _buildSliverSection("Gruplar", "groups", true, isDark),
        ],
      ),
    );
  }

  // --- DİNAMİK SLIVER BÖLÜMÜ ---
  Widget _buildSliverSection(String title, String collection, bool isGroup, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      // KRİTİK: Firestore sorgusunda direkt 'arrayContains' kullanmak performansı artırır
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('archivedBy', arrayContains: currentUsername)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: SizedBox());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  return _buildArchivedTile(context, data, docs[index].id, isGroup, isDark);
                },
                childCount: docs.length,
              ),
            ),
          ],
        );
      },
    );
  }

  // --- ARŞİV KARTI (ORTAK TASARIM) ---
  Widget _buildArchivedTile(BuildContext context, Map<String, dynamic> data, String docId, bool isGroup, bool isDark) {
    String displayName = "";
    if (isGroup) {
      displayName = data['groupName'] ?? "İsimsiz Grup";
    } else {
      List participants = data['participants'] ?? [];
      displayName = participants.firstWhere((p) => p != currentUsername, orElse: () => "Kullanıcı");
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.02), blurRadius: 10)],
      ),
      child: ListTile(
        onTap: () {
          if (isGroup) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => GroupChatScreen(
              groupId: docId,
              groupName: displayName,
              currentUsername: currentUsername,
            )));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: displayName)));
          }
        },
        leading: CircleAvatar(
            backgroundColor: isGroup ? const Color(0xFFFBC8B6) : const Color(0xFFADCFD0),
            child: Icon(isGroup ? Icons.groups : Icons.person, color: Colors.white)
        ),
        title: Text(isGroup ? displayName : "@$displayName",
            style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        subtitle: const Text("Arşivden çıkarmak için butona dokun", style: TextStyle(fontSize: 10)),
        trailing: IconButton(
          icon: const Icon(Icons.unarchive_outlined, color: Color(0xFFFBC8B6)),
          onPressed: () async {
            // Hangi koleksiyonsa oradan siler
            await FirebaseFirestore.instance.collection(isGroup ? "groups" : "chats").doc(docId).update({
              'archivedBy': FieldValue.arrayRemove([currentUsername])
            });
          },
        ),
      ),
    );
  }
}