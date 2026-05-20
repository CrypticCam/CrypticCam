import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../utils/chat_utils.dart';
import '../utils/stego_utils.dart';
import 'biometric_service.dart';

class ChatScreen extends StatefulWidget {
  final String userName;
  const ChatScreen({super.key, required this.userName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _currentUsername;
  bool _isProcessing = false;
  File? _backgroundImage;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUsername();
  }

  // --- KULLANICI VE ARKA PLAN İŞLEMLERİ ---
  Future<void> _fetchCurrentUsername() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty && mounted) {
        setState(() => _currentUsername = userDoc.docs.first.id);
        _loadBackground();
        _markMessagesAsRead(); // Kullanıcı adı yüklenir yüklenmez ilk okundu temizliğini yap
      }
    }
  }

  // --- OKUNMAMIŞ MESAJLARI SIFIRLAMA MOTORU (YENİ) ---
  void _markMessagesAsRead() async {
    if (_currentUsername == null) return;
    String chatId = ChatUtils.getChatRoomId(_currentUsername!, widget.userName);

    try {
      final unreadMessagesQuery = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('sender', isEqualTo: widget.userName) // Sadece karşı taraftan gelenler
          .where('isRead', isEqualTo: false)           // Okunmamış olanlar
          .get();

      if (unreadMessagesQuery.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in unreadMessagesQuery.docs) {
          batch.update(doc.reference, {'isRead': true});
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Okundu işaretleme hatası: $e");
    }
  }

  Future<void> _loadBackground() async {
    if (_currentUsername == null) return;
    String chatRoomId = ChatUtils.getChatRoomId(_currentUsername!, widget.userName);
    File? savedImage = await ChatUtils.loadSavedBackground(chatRoomId);
    if (savedImage != null && mounted) {
      setState(() => _backgroundImage = savedImage);
    }
  }

  Future<void> _changeBackground(String roomId) async {
    File? newImage = await ChatUtils.pickAndSaveBackground(roomId);
    if (newImage != null && mounted) {
      setState(() => _backgroundImage = newImage);
      _showSnackBar("Arka plan güncellendi");
    }
  }

  // --- İFADE (REACTION) İŞLEMLERİ ---
  Future<void> _addReaction(String roomId, String msgId, String emoji) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .doc(msgId)
        .set({
      'reactions': {_currentUsername: emoji}
    }, SetOptions(merge: true));
  }

  void _showReactionPicker(String roomId, String msgId) {
    final List<String> reactions = ["❤️", "👍", "😂", "😮", "😢", "🙏"];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: reactions.map((e) => GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              _addReaction(roomId, msgId, e);
            },
            child: Text(e, style: const TextStyle(fontSize: 30)),
          )).toList(),
        ),
      ),
    );
  }

  // --- MESAJLAŞMA VE GİZLİ GÖRSEL ---
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

  Future<void> _sendSecretImage(String roomId) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    String? secretMsg = await _showSecretInputDialog(context);
    if (secretMsg == null || secretMsg.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      Uint8List originalBytes = await File(image.path).readAsBytes();
      String encryptedMsg = StegoUtils.encryptMessage(secretMsg);
      Uint8List stegoBytes = StegoUtils.embedData(originalBytes, encryptedMsg);

      final tempDir = await Directory.systemTemp.createTemp();
      File stegoFile = File('${tempDir.path}/stego_image.png');
      await stegoFile.writeAsBytes(stegoBytes);

      String webUrl = await _uploadToWeb(stegoFile);

      await FirebaseFirestore.instance.collection('chats').doc(roomId).set({
        'participants': [_currentUsername, widget.userName],
        'lastMessage': "Gizli bir görsel gönderildi",
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('chats').doc(roomId).collection('messages').add({
        'sender': _currentUsername,
        'imageUrl': webUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
        'isRead': false,
        'isDestroyed': false,
        'reactions': {},
      });
      _showSnackBar("Görsel piksellere mühürlendi!");
    } catch (e) {
      _showSnackBar("Hata: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendMessage(String roomId) async {
    if (_messageController.text.trim().isEmpty) return;
    String text = _messageController.text.trim();
    _messageController.clear();

    try {
      await FirebaseFirestore.instance.collection('chats').doc(roomId).set({
        'participants': [_currentUsername, widget.userName],
        'lastMessage': text,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('chats').doc(roomId).collection('messages').add({
        'text': text,
        'sender': _currentUsername,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'isDestroyed': false,
        'reactions': {},
      });
    } catch (e) { _showSnackBar("Hata: $e"); }
  }

  // --- FAVORİLEME VE AKSİYON MENÜSÜ ---
  Future<void> _starMessage(Map<String, dynamic> msgData, String messageId, String roomId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUsername)
          .collection('starredMessages')
          .doc(messageId)
          .set({
        ...msgData,
        'starredAt': FieldValue.serverTimestamp(),
        'originalRoomId': roomId,
        'messageId': messageId,
        'isFromGroup': false,
      });
      _showSnackBar("Mesaj yıldızlandı");
    } catch (e) { _showSnackBar("Hata: $e"); }
  }

  void _showActionMenu({
    required Map<String, dynamic> msgData,
    required String msgId,
    required String roomId,
    required String? imageUrl,
    Timestamp? expiresAt,
  }) {
    bool isMe = msgData['sender'] == _currentUsername;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ["❤️", "👍", "😂", "😮", "😢", "🙏"].map((emojiStr) => GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addReaction(roomId, msgId, emojiStr);
                    },
                    child: Text(emojiStr, style: const TextStyle(fontSize: 28)),
                  )).toList(),
                ),
              ),

            if (!isMe) const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.star_border_rounded, color: Color(0xFFFBC8B6)),
              title: const Text("Yıldızla"),
              onTap: () {
                Navigator.pop(ctx);
                _starMessage(msgData, msgId, roomId);
              },
            ),
            if (imageUrl != null && !(msgData['isDestroyed'] ?? false))
              ListTile(
                leading: const Icon(Icons.lock_open_rounded, color: Color(0xFFADCFD0)),
                title: const Text("Şifreyi Çöz"),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleImageDecryption(imageUrl, msgId, roomId, expiresAt);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- BUILD METODU ---
  @override
  Widget build(BuildContext context) {
    if (_currentUsername == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    String chatRoomId = ChatUtils.getChatRoomId(_currentUsername!, widget.userName);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text("@${widget.userName}"),
        backgroundColor: const Color(0xFFADCFD0),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.wallpaper_rounded),
            onPressed: () => _backgroundImage != null ? _showWallpaperOptions(chatRoomId) : _changeBackground(chatRoomId),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _backgroundImage != null
                ? Image.file(_backgroundImage!, fit: BoxFit.cover)
                : Container(color: isDark ? Colors.black : Colors.white),
          ),
          Container(color: isDark ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.15)),
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(chatRoomId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    // Ekran açıkken veya anlık akış güncellendiğinde okunmayan yeni mesajları temizle
                    WidgetsBinding.instance.addPostFrameCallback((_) => _markMessagesAsRead());

                    final messages = snapshot.data!.docs;
                    return ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        var data = messages[index].data() as Map<String, dynamic>;
                        return _buildMessageBubble(
                          data: data,
                          messageId: messages[index].id,
                          chatRoomId: chatRoomId,
                          isMe: data['sender'] == _currentUsername,
                          isDark: isDark,
                        );
                      },
                    );
                  },
                ),
              ),
              _buildMessageInput(chatRoomId),
            ],
          ),
          if (_isProcessing) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required Map<String, dynamic> data,
    required String messageId,
    required String chatRoomId,
    required bool isMe,
    required bool isDark,
  }) {
    bool isDestroyed = data['isDestroyed'] ?? false;
    Map reactions = data['reactions'] ?? {};

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onLongPress: () {
              if (!isDestroyed) {
                _showActionMenu(
                  msgData: data,
                  msgId: messageId,
                  roomId: chatRoomId,
                  imageUrl: data['imageUrl'],
                  expiresAt: data['expiresAt'],
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isDestroyed
                    ? (isMe ? const Color(0xFFFFD8C7) : const Color(0xFFF2F2F2))
                    : (isMe ? const Color(0xFFFBC8B6) : (isDark ? Colors.grey[800] : Colors.grey[300])),
                borderRadius: BorderRadius.circular(20),
              ),
              child: isDestroyed
                  ? Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.delete_sweep, size: 18, color: Colors.grey),
                  SizedBox(width: 5),
                  Text("İmha Edildi", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                ],
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['imageUrl'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.network(data['imageUrl']),
                    ),
                  if (data['text'] != null)
                    Text(data['text'],
                        style: TextStyle(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87))),
                ],
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            Positioned(
              bottom: -4,
              right: isMe ? 15 : null,
              left: !isMe ? 15 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                ),
                child: Text(
                  reactions.values.toSet().join(" "),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (isMe && !isDestroyed)
            Positioned(
                bottom: 0,
                right: 0,
                child: Icon(Icons.done_all_rounded,
                    size: 14, color: (data['isRead'] ?? false) ? Colors.blueAccent : Colors.grey)),
        ],
      ),
    );
  }

  // --- YARDIMCI METODLAR VE DİALOGLAR ---
  Future<void> _handleImageDecryption(String imageUrl, String messageId, String chatRoomId, Timestamp? expiresAt) async {
    bool authenticated = await BiometricService.authenticate();
    if (authenticated) {
      setState(() => _isProcessing = true);
      try {
        var response = await http.get(Uri.parse(imageUrl));
        String extractedEncrypted = StegoUtils.extractData(response.bodyBytes);
        if (!mounted) return;
        _showResultDialog(extractedEncrypted, messageId, chatRoomId, expiresAt);
      } catch (e) {
        _showSnackBar("Veri deşifre edilemedi.");
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  void _showResultDialog(String text, String messageId, String roomId, Timestamp? expiresAt) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _MatrixDecodeDialog(
            secretText: text, messageId: messageId, roomId: roomId, expiresAt: expiresAt));
  }

  void _showWallpaperOptions(String roomId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFADCFD0)),
                title: const Text("Yeni Fotoğraf Seç"),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeBackground(roomId);
                }),
            ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text("Arka Planı Kaldır"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatUtils.clearSavedBackground(roomId);
                  if (mounted) setState(() => _backgroundImage = null);
                }),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(String roomId) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Colors.grey, width: 0.2))),
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.add_a_photo, color: Color(0xFFADCFD0)),
            onPressed: () => _sendSecretImage(roomId)),
        Expanded(
            child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: "Bir mesaj yazın...", border: InputBorder.none))),
        IconButton(
            icon: const Icon(Icons.send, color: Color(0xFFFBC8B6)),
            onPressed: () => _sendMessage(roomId)),
      ]),
    );
  }

  Future<String?> _showSecretInputDialog(BuildContext context) async {
    TextEditingController c = TextEditingController();
    return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("Piksellere Mesaj Göm"),
            content: TextField(controller: c),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Mühürle ve Gönder"))
            ]));
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}

class _MatrixDecodeDialog extends StatefulWidget {
  final String secretText;
  final String messageId;
  final String roomId;
  final Timestamp? expiresAt;

  const _MatrixDecodeDialog({
    required this.secretText,
    required this.messageId,
    required this.roomId,
    this.expiresAt,
  });

  @override
  State<_MatrixDecodeDialog> createState() => _MatrixDecodeDialogState();
}

class _MatrixDecodeDialogState extends State<_MatrixDecodeDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _displayText = "";
  bool _isDecoded = false;
  int _secondsRemaining = 30;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..addListener(() {
        setState(() {
          if (_controller.value < 0.8) {
            _displayText = List.generate(
                widget.secretText.length, (index) => String.fromCharCode(_random.nextInt(93) + 33))
                .join();
          } else {
            _isDecoded = true;
            try {
              _displayText = StegoUtils.decryptMessage(widget.secretText);
            } catch (e) {
              _displayText = "Hata!";
            }
            if (_controller.isCompleted) _startBurnTimer();
          }
        });
      });
    _controller.forward();
  }

  void _startBurnTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        _markAsDestroyed();
        return false;
      }
      return true;
    });
  }

  Future<void> _markAsDestroyed() async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('messages')
        .doc(widget.messageId)
        .update({'isDestroyed': true});
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F0F),
      title: Text(_isDecoded ? "DEŞİFRE EDİLDİ" : "ÇÖZÜLÜYOR...", style: const TextStyle(color: Color(0xFFADCFD0))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFADCFD0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _displayText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Courier', color: Colors.greenAccent, fontSize: 18),
            ),
          ),
          if (_isDecoded)
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text("Görsel imha: $_secondsRemaining s", style: const TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _markAsDestroyed,
          child: const Text("TAMAM", style: TextStyle(color: Color(0xFFADCFD0))),
        ),
      ],
    );
  }
}