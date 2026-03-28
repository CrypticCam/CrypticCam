import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsScreen extends StatefulWidget {
  final String currentUsername;
  const NotificationsScreen({super.key, required this.currentUsername});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {

  // --- 1. EKRANDAN ÇIKARKEN TEMİZLİK ---
  Future<void> _cleanupOnExit() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUsername)
        .collection('requests')
        .where('status', isEqualTo: 'accepted')
        .get();

    if (snapshot.docs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // --- 2. İSTEK KABUL ETME ---
  Future<void> _acceptRequest(String fromUser) async {
    final batch = FirebaseFirestore.instance.batch();
    final myDoc = FirebaseFirestore.instance.collection('users').doc(widget.currentUsername);
    final friendDoc = FirebaseFirestore.instance.collection('users').doc(fromUser);

    batch.set(myDoc.collection('followers').doc(fromUser), {'timestamp': FieldValue.serverTimestamp()});
    batch.update(myDoc, {'followers': FieldValue.increment(1)});
    batch.set(friendDoc.collection('following').doc(widget.currentUsername), {'timestamp': FieldValue.serverTimestamp()});
    batch.update(friendDoc, {'following': FieldValue.increment(1)});

    batch.update(myDoc.collection('requests').doc(fromUser), {'status': 'accepted'});
    await batch.commit();
  }

  // --- 3. GERİ TAKİP ET VE TEMİZLE ---
  Future<void> _followBack(String targetUser) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.set(FirebaseFirestore.instance.collection('users').doc(targetUser).collection('requests').doc(widget.currentUsername), {
      'from': widget.currentUsername,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending'
    });
    batch.delete(FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('requests').doc(targetUser));
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    // Tema kontrolü
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) await _cleanupOnExit();
      },
      child: Scaffold(
        // DİNAMİK: Arka plan rengi
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text("Bildirimler",
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => Navigator.pop(context)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.currentUsername)
              .collection('requests')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.docs.isEmpty) return _buildEmptyState(isDark);

            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                String status = data['status'] ?? 'pending';
                return _buildNotificationTile(doc.id, status, isDark);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotificationTile(String fromUser, String status, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // DİNAMİK: Kart tasarımı
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: const Color(0xFFFBC8B6).withOpacity(0.2),
              child: const Icon(Icons.person, color: Color(0xFFFBC8B6))),
          const SizedBox(width: 12),
          Expanded(
              child: Text("@$fromUser size takip isteği gönderdi.",
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),

          if (status == 'accepted')
            _buildAcceptedAction(fromUser, isDark)
          else ...[
            IconButton(
                icon: const Icon(Icons.check_circle_outline, color: Color(0xFFADCFD0)),
                onPressed: () => _acceptRequest(fromUser)),
            IconButton(
                icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                onPressed: () => _rejectRequest(fromUser)),
          ],
        ],
      ),
    );
  }

  // ---  AKILLI AKSİYON BUTONU ---
  Widget _buildAcceptedAction(String fromUser, bool isDark) {
    return StreamBuilder<DocumentSnapshot>(
      // 1. KONTROL: Ben onu zaten takip ediyor muyum?
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUsername)
          .collection('following')
          .doc(fromUser)
          .snapshots(),
      builder: (context, followSnap) {
        bool alreadyFollowing = followSnap.hasData && followSnap.data!.exists;

        return StreamBuilder<DocumentSnapshot>(
          // 2. KONTROL: Ona gönderdiğim bekleyen bir isteğim var mı?
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(fromUser)
              .collection('requests')
              .doc(widget.currentUsername)
              .snapshots(),
          builder: (context, requestSnap) {
            bool isRequestSent = requestSnap.hasData && requestSnap.data!.exists;

            // Durum Belirleme
            String buttonText = "Sen de Takip Et";
            Color btnColor = const Color(0xFFADCFD0); // Mint Yeşili
            bool isDisable = false;

            if (alreadyFollowing) {
              buttonText = "Takip";
              btnColor = isDark ? Colors.white12 : Colors.grey.shade300;
              isDisable = true;
            } else if (isRequestSent) {
              buttonText = "İstek Gönderildi";
              btnColor = isDark ? Colors.white10 : Colors.grey.shade200;
              isDisable = true;
            }

            return ElevatedButton(
              onPressed: isDisable ? null : () => _followBack(fromUser),
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                buttonText, //
                style: TextStyle(
                    color: isDisable ? (isDark ? Colors.white24 : Colors.black38) : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _rejectRequest(String fromUser) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('requests').doc(fromUser).delete();
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
        child: Text("Henüz bildirim yok.",
            style: TextStyle(color: isDark ? Colors.white24 : Colors.grey)));
  }
}