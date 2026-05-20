import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_screen.dart';
import 'archived_chats_screen.dart';
import 'received_images_screen.dart';
import 'group_chat_screen.dart';
import 'group_screen.dart';
import 'broadcast_message_screen.dart';
import 'ai_chat_screen.dart';

import '../utils/chat_utils.dart';
import 'biometric_service.dart';

class HomeScreen extends StatefulWidget {
  final String currentUsername;
  const HomeScreen({super.key, required this.currentUsername});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isProcessing = false;

  // --- GRUP ARŞİVLEME MENÜSÜ ---
  void _showGroupActionMenu(String groupName, String groupId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text("Grubu Arşivle"),
              onTap: () {
                Navigator.pop(ctx);
                _archiveGroup(groupId);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- ARŞİVLEME MOTORU ---
  Future<void> _archiveGroup(String groupId) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
        'archivedBy': FieldValue.arrayUnion([widget.currentUsername]),
      });
      _msg("Grup arşivlendi.");
    } catch (e) {
      _msg("Hata: $e");
    }
  }

  // --- SOHBET ARŞİVLEME ---
  Future<void> _archiveChat(String chatId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'archivedBy': FieldValue.arrayUnion([widget.currentUsername]),
      });
      _msg("Sohbet arşivlendi.");
    } catch (e) {
      _msg("Hata: $e");
    }
  }

  // --- CLOUDINARY YÜKLEME ---
  Future<String> _uploadToWeb(File file) async {
    String cloudName = "dqim4rdfp";
    var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));
    request.fields['upload_preset'] = 'cryptic_preset';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      return jsonDecode(responseData)['secure_url'];
    } throw "Yükleme hatası!";
  }

  // --- GİZLEME (STEGO) AKIŞI ---
  Future<void> _handleGizleFlow() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    String? secretMsg = await _showTextDialog(context);
    if (secretMsg == null || secretMsg.isEmpty) return;

    if (!mounted) return;
    String? recipient = await _showRecipientPicker(context);
    if (recipient == null) return;

    _startSendingProcess(File(pickedFile.path), secretMsg, recipient);
  }

  Future<void> _startSendingProcess(File imageFile, String msg, String recipient) async {
    setState(() => _isProcessing = true);
    try {
      String webUrl = await _uploadToWeb(imageFile);
      String chatId = ChatUtils.getChatRoomId(widget.currentUsername, recipient);
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

      await chatRef.set({
        'participants': FieldValue.arrayUnion([widget.currentUsername, recipient]),
        'lastMessage': "Fotoğraf",
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'sender': widget.currentUsername,
        'receiverId': recipient,
        'imageUrl': webUrl,
        'secret': msg,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _msg("Veri mühürlendi ve gönderildi!");
    } catch (e) {
      _msg("Hata: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- ANA MENÜ (YENI MESAJ, GRUP VB) ---
  void _showNewMessageMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. BİREBİR MESAJ
                ListTile(
                  leading: const Icon(Icons.message_outlined, color: Color(0xFFADCFD0)),
                  title: const Text("Yeni Mesaj"),
                  subtitle: const Text("Tek bir kişiyle sohbet başlatın"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    String? recipient = await _showRecipientPicker(context);
                    if (recipient != null && recipient.isNotEmpty && mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: recipient)));
                    }
                  },
                ),

                // 2. YENİ GRUP OLUŞTUR (Sadece bu blok kalmalı)
                ListTile(
                  leading: const Icon(Icons.group_add_outlined, color: Color(0xFFADCFD0)),
                  title: const Text("Yeni Grup Oluştur"),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        // Parametre burada doğru şekilde iletiliyor
                        builder: (context) => CreateGroupScreen(currentUsername: widget.currentUsername),
                      ),
                    );
                  },
                ),

                // 3. TOPLU MESAJ GÖNDER
                ListTile(
                  leading: const Icon(Icons.campaign_outlined, color: Color(0xFFFBC8B6)),
                  title: const Text("Toplu Mesaj Gönder"),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const BroadcastMessageScreen())
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewMessageMenu(context),
        backgroundColor: const Color(0xFFADCFD0),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),
                  Text("Merhaba", style: TextStyle(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38)),
                  Text("CrypticCam", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      _buildActionCard("Gizle", Icons.add_photo_alternate_outlined, _handleGizleFlow, const Color(0xFFFBC8B6), false),
                      const SizedBox(width: 16),
                      _buildActionCard("Çöz", Icons.waves, () async {
                        bool auth = await BiometricService.authenticate();
                        if (auth) {
                          if (!mounted) return;
                          Navigator.push(context, MaterialPageRoute(builder: (context) => ReceivedImagesScreen(currentUsername: widget.currentUsername)));
                        }
                      }, isDark ? const Color(0xFF1A1A1A) : Colors.white, true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildArchivedButton(),
                  const SizedBox(height: 40),
                  _buildGroupList(isDark),
                  const Text("Aktif Sohbetler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildChatList(isDark),
                  const SizedBox(height: 100),
                ],
              ),
            ),
            if (_isProcessing) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0)))),
          ],
        ),
      ),
    );
  }

  // --- SOHBET LİSTESİ (FİLTRELİ) ---
  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: widget.currentUsername)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.where((d) {
          var data = d.data() as Map<String, dynamic>;
          List archived = data['archivedBy'] ?? [];
          return !archived.contains(widget.currentUsername);
        }).toList();

        if (docs.isEmpty) return const Center(child: Text("Aktif sohbet bulunamadı."));

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Toplam sayıya +1 ekliyoruz (Yapay zeka satırı için)
          itemCount: docs.length + 1,
          itemBuilder: (context, index) {
            // İLK SATIRA YAPAY ZEKAYI KOYALIM
            if (index == 0) {
              return _buildAITile(isDark);
            }

            // Diğer normal mesajlar (index-1 diyerek kaydırıyoruz)
            var chatData = docs[index - 1].data() as Map<String, dynamic>;
            List participants = chatData['participants'] ?? [];
            String otherUser = participants.firstWhere((p) => p != widget.currentUsername, orElse: () => "Bilinmeyen");
            return _buildChatTile(otherUser, docs[index - 1].id, isDark, chatData);
          },
        );
      },
    );
  }
  Widget _buildAITile(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1A1A), const Color(0xFF2C3E50)]
              : [Colors.white, const Color(0xFFF0F7F7)],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFADCFD0).withOpacity(0.3)),
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AIChatScreen())),
        leading: const CircleAvatar(
          radius: 25,
          backgroundColor: Color(0xFFADCFD0),
          child: Icon(Icons.auto_awesome, color: Colors.white),
        ),
        title: const Text("Cryptic AI", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("Yapay zeka ile sohbet et...", style: TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(color: Color(0xFFADCFD0), shape: BoxShape.circle),
          child: const Icon(Icons.bolt, size: 12, color: Colors.white),
        ),
      ),
    );
  }
  // --- GRUP LİSTESİ (FİLTRELİ) ---
  Widget _buildGroupList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: widget.currentUsername)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final docs = snapshot.data!.docs.where((d) {
          var data = d.data() as Map<String, dynamic>;
          List archived = data['archivedBy'] ?? [];
          return !archived.contains(widget.currentUsername);
        }).toList();

        if (docs.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Gruplar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                var groupData = docs[index].data() as Map<String, dynamic>;
                return _buildGroupTile(groupData, isDark);
              },
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> data, bool isDark) {
    final String? groupPic = data['groupPic'];
    final String groupId = data['groupId'];
    bool hasGroupPic = groupPic != null && groupPic.isNotEmpty;

    // Kullanıcının bu grup için saklanan son okuma zamanı damgası
    dynamic lastReadVal = data['lastRead_${widget.currentUsername}'];
    Timestamp lastReadTimestamp = lastReadVal is Timestamp ? lastReadVal : Timestamp.fromMillisecondsSinceEpoch(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1A1A) : Colors.white, borderRadius: BorderRadius.circular(25)),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GroupChatScreen(
          groupId: groupId,
          groupName: data['groupName'],
          currentUsername: widget.currentUsername,
        ))),
        onLongPress: () => _showGroupActionMenu(data['groupName'], groupId),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFFFBC8B6),
          backgroundImage: hasGroupPic ? NetworkImage(groupPic!) : null,
          child: !hasGroupPic ? const Icon(Icons.groups, color: Colors.white, size: 28) : null,
        ),
        title: Text(data['groupName'] ?? "Grup", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${(data['members'] as List).length} Üye"),

        // --- GRUP OKUNMAMIŞ MESAJ SAYACI SİSTEMİ (YENİ) ---
        trailing: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .collection('messages')
              .where('timestamp', isGreaterThan: lastReadTimestamp) // Son okuma zamanından büyük olan mesajlar
              .snapshots(),
          builder: (context, unreadSnap) {
            if (!unreadSnap.hasData || unreadSnap.data!.docs.isEmpty) {
              return const Icon(Icons.arrow_forward_ios, size: 14); // Mesaj yoksa sadece ok göster
            }

            // Gelen mesajların içinden benim atmadığım mesajları filtrele
            final unreadDocs = unreadSnap.data!.docs.where((doc) {
              var msgData = doc.data() as Map<String, dynamic>;
              return msgData['sender'] != widget.currentUsername;
            }).toList();

            if (unreadDocs.isEmpty) {
              return const Icon(Icons.arrow_forward_ios, size: 14);
            }

            return Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFADCFD0),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              child: Text(
                unreadDocs.length.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatTile(String name, String chatId, bool isDark, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1A1A) : Colors.white, borderRadius: BorderRadius.circular(25)),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: name))),
        onLongPress: () {
          showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.archive_outlined), title: const Text("Sohbeti Arşivle"), onTap: () { Navigator.pop(ctx); _archiveChat(chatId); }),
          ])));
        },
        leading: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(name).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) return const CircleAvatar(radius: 25, backgroundColor: Color(0xFFADCFD0));
            String? pic;
            if (userSnap.hasData && userSnap.data!.exists) {
              pic = (userSnap.data!.data() as Map<String, dynamic>)['profilePic'];
            }
            if (pic == null || pic.isEmpty) return CircleAvatar(radius: 25, backgroundColor: const Color(0xFFADCFD0), child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)));
            return CircleAvatar(radius: 25, backgroundImage: pic.startsWith('http') ? NetworkImage(pic) : null, child: !pic.startsWith('http') ? ClipOval(child: Image.memory(base64Decode(pic.trim()), width: 50, height: 50, fit: BoxFit.cover)) : null);
          },
        ),
        title: Text("@$name", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(data['lastMessage'] ?? "Mesaj yok", maxLines: 1),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ZAMAN DAMGASI
            if (data['timestamp'] != null)
              Text(
                  DateFormat('HH:mm').format((data['timestamp'] as Timestamp).toDate()),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)
              ),
            const SizedBox(height: 5),
            // OKUNMAMIŞ MESAJ SAYACI (DÜZELTME)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .where('sender', isEqualTo: name) // Karşı taraftan gelen mesajlar
                  .where('isRead', isEqualTo: false) // Okunmamış olanlar
                  .snapshots(),
              builder: (context, unreadSnap) {
                if (!unreadSnap.hasData || unreadSnap.data!.docs.isEmpty) {
                  return const SizedBox.shrink(); // Okunmamış mesaj yoksa hiçbir şey gösterme
                }
                int unreadCount = unreadSnap.data!.docs.length;
                return Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFADCFD0), // Temana uygun yeşil tonu
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- YARDIMCI METODLAR ---
  Widget _buildActionCard(String title, IconData icon, VoidCallback onTap, Color bgColor, bool isDecoder) {
    return Expanded(child: GestureDetector(onTap: onTap, child: Container(height: 120, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(30)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: isDecoder ? const Color(0xFFFBC8B6) : Colors.white, size: 32), const SizedBox(height: 10), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDecoder ? const Color(0xFFADCFD0) : (isDecoder ? Colors.black : Colors.white)))]))));
  }

  Future<String?> _showTextDialog(BuildContext context) async {
    TextEditingController c = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text("Gizli Mesaj"), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Devam"))]));
  }

  Widget _buildArchivedButton() {
    return Center(child: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ArchivedChatsScreen(currentUsername: widget.currentUsername))), icon: const Icon(Icons.archive_outlined, color: Color(0xFFADCFD0)), label: const Text("Arşivlenmiş Sohbetler", style: TextStyle(color: Color(0xFFADCFD0)))));
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  // --- RECIPIENT PICKER (MUTUAL FOLLOWING) ---
  Future<String?> _showRecipientPicker(BuildContext context) async {
    return await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const Text("Kişi Seçin", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('following').snapshots(),
                  builder: (context, followingSnap) {
                    if (!followingSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = followingSnap.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text("Takip ettiğiniz kimse yok."));

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final friend = docs[index].id;
                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('followers').doc(friend).snapshots(),
                          builder: (context, followerSnap) {
                            if (!followerSnap.hasData || !followerSnap.data!.exists) return const SizedBox.shrink();
                            return ListTile(
                              onTap: () => Navigator.pop(ctx, friend),
                              leading: const CircleAvatar(backgroundColor: Color(0xFFADCFD0), child: Icon(Icons.person, color: Colors.white)),
                              title: Text("@$friend"),
                              trailing: const Icon(Icons.chevron_right),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}