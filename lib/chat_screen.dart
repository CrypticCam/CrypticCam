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
  final String userName; // Karsı tarafın kullanıcı adı
  const ChatScreen({super.key, required this.userName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _currentUsername;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUsername();
  }

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
      }
    }
  }

  // --- CLOUDINARY YUKLEME ---
  Future<String> _uploadToWeb(File file) async {
    String cloudName = "dqim4rdfp";
    var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));
    request.fields['upload_preset'] = 'cryptic_preset';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      return jsonDecode(responseData)['secure_url'];
    } throw "Yukleme hatasi!";
  }

  // --- GIZLI GORSEL GONDERME ---
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
        'lastMessage': "Gizli bir gorsel gonderildi",
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('chats').doc(roomId).collection('messages').add({
        'sender': _currentUsername,
        'receiverId': widget.userName,
        'imageUrl': webUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
        'isRead': false,
        'isDestroyed': false,
      });
      _showSnackBar("Gorsel piksellere muhurlendi!");
    } catch (e) {
      _showSnackBar("Hata: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- NORMAL MESAJ GONDERME ---
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
      });
    } catch (e) { _showSnackBar("Hata: $e"); }
  }

  // --- OKUNDU ISARETLEME ---
  void _markAllMessagesAsRead(String chatRoomId) async {
    final unreadQuery = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .where('sender', isEqualTo: widget.userName)
        .where('isRead', isEqualTo: false)
        .get();

    if (unreadQuery.docs.isNotEmpty) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadQuery.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUsername == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    String chatRoomId = ChatUtils.getChatRoomId(_currentUsername!, widget.userName);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("@${widget.userName}"),
        backgroundColor: const Color(0xFFADCFD0),
        elevation: 0,
      ),
      body: Stack(
        children: [
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

                      final messages = snapshot.data!.docs;
                      final now = DateTime.now();

                      // --- ARKA PLAN TEMIZLIK DONGUSU ---
                      for (var doc in messages) {
                        var data = doc.data() as Map<String, dynamic>;

                        // Mesaj zaten imha edilmisse isleme alma
                        if (data['isDestroyed'] == true) continue;

                        if (data.containsKey('expiresAt') && data['expiresAt'] != null) {
                          Timestamp expiresAt = data['expiresAt'];
                          if (now.isAfter(expiresAt.toDate())) {
                            // Veritabanindan hassas verileri fiziksel olarak siliyoruz
                            FirebaseFirestore.instance
                                .collection('chats')
                                .doc(chatRoomId)
                                .collection('messages')
                                .doc(doc.id)
                                .update({
                              'imageUrl': FieldValue.delete(),
                              'text': FieldValue.delete(),
                              'expiresAt': FieldValue.delete(),
                              'isDestroyed': true,
                            });
                          }
                        }
                      }

                      _markAllMessagesAsRead(chatRoomId);

                      return ListView.builder(
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          var data = messages[index].data() as Map<String, dynamic>;
                          return _buildMessageBubble(
                            text: data['text'],
                            imageUrl: data['imageUrl'],
                            expiresAt: data['expiresAt'],
                            messageId: messages[index].id,
                            chatRoomId: chatRoomId,
                            isMe: data['sender'] == _currentUsername,
                            isRead: data['isRead'] ?? false,
                            isDestroyed: data['isDestroyed'] ?? false,
                          );
                        },
                      );
                    },
                  )
              ),
              _buildMessageInput(chatRoomId),
            ],
          ),
          if (_isProcessing) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

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
        _showSnackBar("Pikseller muhurlenirken bir hata olustu veya veri bozulmus.");
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } else {
      _showSnackBar("Kimlik dogrulamasi basarisiz!");
    }
  }

  Widget _buildMessageBubble({
    String? text,
    String? imageUrl,
    Timestamp? expiresAt,
    required String messageId,
    required String chatRoomId,
    required bool isMe,
    bool isRead = false,
    bool isDestroyed = false,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isDestroyed
                  ? (isMe ? const Color(0xFFFFD8C7) : const Color(0xFFF2F2F2))
                  : (isMe ? const Color(0xFFFBC8B6) : const Color(0xFFE8E8E8)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 20),
              ),
            ),
            child: isDestroyed
                ? _buildDestroyedPlaceholder()
                : _buildActualContent(text, imageUrl, messageId, chatRoomId, expiresAt, isMe),
          ),
          if (isMe && !isDestroyed)
            Padding(
              padding: const EdgeInsets.only(right: 15, bottom: 5),
              child: Icon(
                Icons.done_all_rounded,
                size: 16,
                color: isRead ? Colors.blueAccent : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDestroyedPlaceholder() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.grey),
        SizedBox(width: 8),
        Text(
          "Imha Edildi",
          style: TextStyle(
            color: Colors.grey,
            fontStyle: FontStyle.italic,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildActualContent(String? text, String? imageUrl, String msgId, String roomId, Timestamp? exp, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null)
          GestureDetector(
            onLongPress: () => _handleImageDecryption(imageUrl, msgId, roomId, exp),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(imageUrl),
            ),
          ),
        if (text != null)
          Text(text, style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
      ],
    );
  }

  Widget _buildMessageInput(String roomId) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey, width: 0.2))),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.add_a_photo, color: Color(0xFFADCFD0)), onPressed: () => _sendSecretImage(roomId)),
        Expanded(child: TextField(controller: _messageController, decoration: const InputDecoration(hintText: "Bir mesaj yazın...", border: InputBorder.none))),
        IconButton(icon: const Icon(Icons.send, color: Color(0xFFFBC8B6)), onPressed: () => _sendMessage(roomId)),
      ]),
    );
  }

  void _showResultDialog(String text, String messageId, String roomId, Timestamp? expiresAt) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => _MatrixDecodeDialog(
      secretText: text, messageId: messageId, roomId: roomId, expiresAt: expiresAt,
    ));
  }

  Future<String?> _showSecretInputDialog(BuildContext context) async {
    TextEditingController c = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Piksellere Mesaj Gom"),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: "Gizli mesajınızı yazın...")),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Muhurle ve Gonder"))],
    ));
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

  const _MatrixDecodeDialog({required this.secretText, required this.messageId, required this.roomId, this.expiresAt});

  @override State<_MatrixDecodeDialog> createState() => _MatrixDecodeDialogState();
}

class _MatrixDecodeDialogState extends State<_MatrixDecodeDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _displayText = "";
  bool _isDecoded = false;
  int _secondsRemaining = 0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    if (widget.expiresAt != null) {
      _secondsRemaining = widget.expiresAt!.toDate().difference(DateTime.now()).inSeconds;
      if (_secondsRemaining < 0) _secondsRemaining = 0;
    } else {
      _secondsRemaining = 300;
    }

    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..addListener(() {
      setState(() {
        if (_controller.value < 0.8) {
          _displayText = List.generate(widget.secretText.length, (index) => String.fromCharCode(_random.nextInt(93) + 33)).join();
        } else {
          _isDecoded = true;
          try { _displayText = StegoUtils.decryptMessage(widget.secretText); } catch (e) { _displayText = "Hata!"; }
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
      if (_secondsRemaining <= 0) { _purgeAndClose(); return false; }
      return true;
    });
  }

  // --- HASSAS VERILERI SILIP DIYALOGU KAPATIR ---
  Future<void> _purgeAndClose() async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('messages')
        .doc(widget.messageId)
        .update({
      'imageUrl': FieldValue.delete(),
      'text': FieldValue.delete(),
      'expiresAt': FieldValue.delete(),
      'isDestroyed': true,
    });
    if (mounted) Navigator.pop(context);
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F0F),
      title: Text(_isDecoded ? "DESIFRE EDILDI" : "COZULUYOR...", style: const TextStyle(color: Color(0xFFADCFD0))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFADCFD0)), borderRadius: BorderRadius.circular(10)),
            child: Text(_displayText, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Courier', color: Colors.greenAccent, fontSize: 18)),
          ),
          if (_isDecoded) Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Text("Kendi kendini imha: ${_secondsRemaining}s", style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      actions: [TextButton(onPressed: _purgeAndClose, child: const Text("TAMAM", style: TextStyle(color: Color(0xFFADCFD0))))],
    );
  }
}