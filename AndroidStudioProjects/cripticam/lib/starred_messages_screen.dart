import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class StarredMessagesScreen extends StatelessWidget {
  final String currentUsername;

  const StarredMessagesScreen({super.key, required this.currentUsername});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Yildizli Mesajlar"),
        backgroundColor: const Color(0xFFADCFD0),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Kullanicinin kendi altindaki favori koleksiyonunu dinliyoruz
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUsername)
            .collection('starredMessages')
            .orderBy('starredAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_outline, size: 80, color: Colors.grey.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    "Henuz hicbir mesaji yildizlamadiniz.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final starredMessages = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: starredMessages.length,
            itemBuilder: (context, index) {
              var data = starredMessages[index].data() as Map<String, dynamic>;
              String docId = starredMessages[index].id;
              bool isImage = data['imageUrl'] != null;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 2,
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ust Bilgi: Gonderen ve Tarih
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "@${data['sender']}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFBC8B6),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.star, color: Colors.amber, size: 20),
                            onPressed: () => _removeFromStarred(docId), // Favoriden cikar
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Mesaj Icerigi (Metin veya Gorsel)
                      if (isImage)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            data['imageUrl'],
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                          ),
                        )
                      else
                        Text(
                          data['text'] ?? "",
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Alt Bilgi: Hangi oda ve ne zaman favorilendi
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            data['isFromGroup'] == true ? "Grup Mesaji" : "Bireysel Mesaj",
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          if (data['starredAt'] != null)
                            Text(
                              DateFormat('dd.MM.yyyy HH:mm').format(
                                (data['starredAt'] as Timestamp).toDate(),
                              ),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Favoriden cikarma islemi
  Future<void> _removeFromStarred(String docId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUsername)
        .collection('starredMessages')
        .doc(docId)
        .delete();
  }
}