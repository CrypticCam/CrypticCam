import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(
        title: const Text("Yeni Sohbet", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Veritabanındaki tüm kullanıcıları çekiyoruz
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Veriler yüklenirken bir hata oluştu."));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFBC8B6)));
          }

          // Filtreleme: Kendimiz hariç herkesi listeliyoruz
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['uid'] != _auth.currentUser?.uid;
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Text("Henüz kayıtlı başka bir kullanıcı bulunamadı.", style: TextStyle(color: Colors.black26)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final String username = docs[index].id; // Belge ID'si eşsiz kullanıcı adıdır
              final Map<String, dynamic> data = docs[index].data() as Map<String, dynamic>;

              return _buildUserTile(username, data['email'] ?? "", context);
            },
          );
        },
      ),
    );
  }

  Widget _buildUserTile(String username, String email, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFADCFD0),
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(email, style: const TextStyle(fontSize: 12, color: Colors.black38)),
        onTap: () {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => ChatScreen(userName: username))
          );
        },
      ),
    );
  }
}