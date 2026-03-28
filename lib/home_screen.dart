import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; // Tarih formatı için gerekli
import 'chat_screen.dart';
import 'archived_chats_screen.dart';
import '../utils/chat_utils.dart';
import 'received_images_screen.dart';
import 'biometric_service.dart';

class HomeScreen extends StatefulWidget {
  final String currentUsername;
  const HomeScreen({super.key, required this.currentUsername});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isProcessing = false;

  // --- CLOUDINARY YÜKLEME MOTORU ---
  Future<String> _uploadToWeb(File file) async {
    String cloudName = "dqim4rdfp";
    var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));

    request.fields['upload_preset'] = 'cryptic_preset';
    //  KRİTİK: Cloudinary'ye resmi olduğu gibi saklamasını, formatını değiştirmemesini söylüyoruz
    request.fields['quality_analysis'] = 'false';
    request.fields['unique_filename'] = 'true';

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      //  URL'yi alırken 'secure_url' kullan ve sonunun .png olduğundan emin ol
      return json['secure_url'];
    } throw "Yükleme hatası!";
  }

  // --- GİZLEME AKIŞI ---
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
        'lastMessage': " Fotoğraf",
        'lastMessageTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'sender': widget.currentUsername,
        'receiverId': recipient,
        'imageUrl': webUrl,
        'secret': msg,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
      });

      _msg("Veri piksellere mühürlendi! ");
    } catch (e) {
      _msg("Hata: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  Text("CrypticCam", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      _buildActionCard("Gizle", Icons.add_photo_alternate_outlined, _handleGizleFlow, const Color(0xFFFBC8B6), false),
                      const SizedBox(width: 16),
                      _buildActionCard("Çöz", Icons.waves, () async {
                        bool authenticated = await BiometricService.authenticate();
                        if (authenticated) {
                          if (!mounted) return;
                          Navigator.push(context, MaterialPageRoute(builder: (context) => ReceivedImagesScreen(currentUsername: widget.currentUsername)));
                        } else {
                          _msg("Parmak izi doğrulanmadı! ");
                        }
                      }, isDark ? const Color(0xFF1A1A1A) : Colors.white, true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildArchivedButton(isDark),
                  const SizedBox(height: 40),
                  Text("Aktif Sohbetler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 15),
                  _buildChatList(isDark), // Sohbet listesi burada çağrılıyor
                  const SizedBox(height: 100),
                ],
              ),
            ),
            if (_isProcessing)
              Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0)))),
          ],
        ),
      ),
    );
  }

  // --- SOHBET LİSTESİ ---
  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: widget.currentUsername)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Dizin hatası varsa burada bir uyarı gösterelim
          return Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red.withOpacity(0.1),
            child: const Text("Sohbetler yüklenemedi. Lütfen Firebase Console üzerinden Index oluşturun.", style: TextStyle(color: Colors.red, fontSize: 12)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Henüz aktif bir sohbet yok. "));

        return ListView.builder(
          shrinkWrap: true, // Column içinde düzgün çalışması için
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var chatData = docs[index].data() as Map<String, dynamic>;
            List participants = chatData['participants'] ?? [];
            String otherUser = participants.firstWhere((p) => p != widget.currentUsername, orElse: () => "Bilinmeyen");

            return _buildChatTile(otherUser, docs[index].id, isDark, chatData);
          },
        );
      },
    );
  }

  Widget _buildChatTile(String name, String chatId, bool isDark, Map<String, dynamic> chatData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: name))),
        onLongPress: () => _showChatActionMenu(name, chatId),

        // --- 1. SOL TARAF: PROFIL FOTOĞRAFI ---
        leading: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(name).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const CircleAvatar(radius: 25, child: CircularProgressIndicator(strokeWidth: 2));
            }

            String? picData;
            if (userSnap.hasData && userSnap.data!.exists) {
              final userData = userSnap.data!.data() as Map<String, dynamic>;
              picData = userData['profilePic'];
            }

            if (picData == null || picData.isEmpty) {
              return const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFADCFD0),
                child: Icon(Icons.person, color: Colors.white),
              );
            }

            return CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFADCFD0),
              child: ClipOval(
                child: picData.startsWith('http')
                    ? Image.network(
                  picData,
                  width: 50, height: 50, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.person),
                )
                    : Image.memory(
                  base64Decode(picData),
                  width: 50, height: 50, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.person),
                ),
              ),
            );
          },
        ),

        // --- 2. ORTA TARAF: KULLANICI ADI VE SON MESAJ ---
        title: Text("@$name", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        subtitle: Text(chatData['lastMessage'] ?? "Mesaj yok", maxLines: 1, overflow: TextOverflow.ellipsis),

        // --- 3. SAĞ TARAF: SAAT VE SOFT MAVİ BİLDİRİM ---
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Saat Bilgisi (Index ile uyumlu 'timestamp' kullanıldı)
            if (chatData['timestamp'] != null)
              Text(
                DateFormat('HH:mm').format((chatData['timestamp'] as Timestamp).toDate()),
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
              ),

            const SizedBox(height: 5),

            // Okunmamış Mesaj Sayacı
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .where('sender', isEqualTo: name) // Karşı taraftan gelenler
                  .where('isRead', isEqualTo: false) // Okunmamış olanlar
                  .snapshots(),
              builder: (context, unreadSnap) {
                if (!unreadSnap.hasData || unreadSnap.data!.docs.isEmpty) {
                  return const SizedBox(height: 20); // Okunmamış yoksa yer tutsun ama görünmesin
                }
                if (unreadSnap.hasError) {
                  print(" SORGUB HATASI: ${unreadSnap.error}");
                }

                int count = unreadSnap.data!.docs.length;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF90CAF9), // Soft Mavi
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                  child: Text(
                    "$count",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- ARŞİVLEME VE SİLME MODALLARI ---
  void _showChatActionMenu(String name, String chatId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              ListTile(
                leading: const Icon(Icons.archive_outlined, color: Color(0xFFADCFD0)),
                title: const Text("Sohbeti Arşivle"),
                onTap: () { Navigator.pop(ctx); _archiveChat(chatId); },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                title: const Text("Sohbeti Sil", style: TextStyle(color: Colors.redAccent)),
                onTap: () { Navigator.pop(ctx); _deleteChatFull(chatId); },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _archiveChat(String chatId) async {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({'archivedBy': FieldValue.arrayUnion([widget.currentUsername])});
    _msg("Sohbet arşivlendi. ");
  }

  Future<void> _deleteChatFull(String chatId) async {
    setState(() => _isProcessing = true);
    try {
      // 1. ADIM: Mesajlar alt koleksiyonundaki tüm dökümanları al
      final messagesRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages');

      final messagesSnapshot = await messagesRef.get();

      // 2. ADIM: WriteBatch kullanarak toplu silme işlemi başlat (Daha hızlı ve güvenli)
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // Tüm mesajları silme listesine ekle
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 3. ADIM: Ana sohbet dökümanını (oda) silme listesine ekle
      batch.delete(FirebaseFirestore.instance.collection('chats').doc(chatId));

      // 4. ADIM: Tüm işlemleri tek seferde onayla
      await batch.commit();

      _msg("Sohbet ve tüm mesajlar kalıcı olarak silindi. ");
    } catch (e) {
      _msg("Silme işlemi başarısız: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildActionCard(String title, IconData icon, VoidCallback onTap, Color bgColor, bool isDecoder) {
    return Expanded(
        child: GestureDetector(
            onTap: onTap,
            child: Container(
                height: 120,
                decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: isDecoder ? const Color(0xFFFBC8B6) : Colors.white, size: 32),
                      const SizedBox(height: 10),
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDecoder ? const Color(0xFFADCFD0) : Colors.white))
                    ]
                )
            )
        )
    );
  }

  Future<String?> _showTextDialog(BuildContext context) async { TextEditingController c = TextEditingController(); return showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text("Gizli Mesaj 🕵️"), content: TextField(controller: c, decoration: const InputDecoration(hintText: "Ne saklayalım?")), actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Devam"))])); }
  Widget _buildArchivedButton(bool isDark) { return Center(child: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ArchivedChatsScreen(currentUsername: widget.currentUsername))), icon: const Icon(Icons.archive_outlined, color: Color(0xFFADCFD0)), label: const Text("Arşivlenmiş Sohbetler", style: TextStyle(color: Color(0xFFADCFD0))))); }
  void _msg(String t) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating)); }

  Future<String?> _showRecipientPicker(BuildContext context) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text("Alıcı Seç", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('following').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final name = docs[index].id;
                      return ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFADCFD0), child: Icon(Icons.person, color: Colors.white)),
                        title: Text("@$name", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        onTap: () => Navigator.pop(ctx, name),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}