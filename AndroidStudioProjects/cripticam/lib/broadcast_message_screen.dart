import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/stego_utils.dart';
import '../utils/chat_utils.dart';

class BroadcastMessageScreen extends StatefulWidget {
  final String encryptedImageUrl;
  final String secretMessage;

  const BroadcastMessageScreen({
    super.key,
    this.encryptedImageUrl = "",
    this.secretMessage = "",
  });

  @override
  State<BroadcastMessageScreen> createState() => _BroadcastMessageScreenState();
}

class _BroadcastMessageScreenState extends State<BroadcastMessageScreen> {
  final List<String> _selectedRecipients = [];
  final TextEditingController _normalMsgController = TextEditingController();
  final TextEditingController _secretMsgController = TextEditingController();
  bool _isProcessing = false;
  File? _imageFile;
  String _currentUsername = "";

  @override
  void initState() {
    super.initState();
    _fetchMyUsername();
  }

  Future<void> _fetchMyUsername() async {
    final user = FirebaseAuth.instance.currentUser;
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

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

  // --- TOPLU GONDERIM MOTORU ---
  Future<void> _broadcastNow() async {
    String normalMsg = _normalMsgController.text.trim();
    String secretMsg = _secretMsgController.text.trim();

    if (_selectedRecipients.isEmpty) {
      _msg("Lutfen en az bir alici secin!");
      return;
    }
    if (_imageFile == null && normalMsg.isEmpty) {
      _msg("Lutfen bir mesaj yazin veya bir gorsel secin!");
      return;
    }

    setState(() => _isProcessing = true);

    try {
      String? webUrl;
      String? encryptedSecret;

      // Eger gorsel secilmisse ve gizli mesaj girilmisse LSB islemini baslat
      if (_imageFile != null && secretMsg.isNotEmpty) {
        Uint8List originalBytes = await _imageFile!.readAsBytes();
        encryptedSecret = StegoUtils.encryptMessage(secretMsg);
        Uint8List stegoBytes = StegoUtils.embedData(originalBytes, encryptedSecret);

        final tempDir = await Directory.systemTemp.createTemp();
        File stegoFile = File('${tempDir.path}/broadcast_stego.png');
        await stegoFile.writeAsBytes(stegoBytes);

        webUrl = await _uploadToWeb(stegoFile);
      }

      for (String recipient in _selectedRecipients) {
        String chatId = ChatUtils.getChatRoomId(_currentUsername, recipient);
        final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

        await chatRef.set({
          'participants': FieldValue.arrayUnion([_currentUsername, recipient]),
          'lastMessage': webUrl != null ? "Gizli Fotograf" : normalMsg,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        Map<String, dynamic> msgData = {
          'sender': _currentUsername,
          'receiverId': recipient,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        };

        if (webUrl != null) {
          msgData['imageUrl'] = webUrl;
          msgData['secret'] = encryptedSecret;
          msgData['type'] = 'image';
        }
        if (normalMsg.isNotEmpty) {
          msgData['text'] = normalMsg;
          if (webUrl == null) msgData['type'] = 'text';
        }

        await chatRef.collection('messages').add(msgData);
      }

      _msg("Mesaj basariyla iletildi!");
      if (mounted) Navigator.pop(context);

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
      appBar: AppBar(title: const Text("Toplu Mesaj")),
      body: _currentUsername.isEmpty
          ? const Center(child: CircularProgressIndicator()) // Kirmizi ekran onleyici
          : Stack(
        children: [
          SingleChildScrollView( // Overflow onleyici
            child: Column(
              children: [
                _buildStegoArea(), // Gorsel + Gizli Mesaj Alani
                _buildTextInputArea(isDark), // Normal Mesaj Alani
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(),
                ),
                const Text("Alicilari Secin:", style: TextStyle(fontWeight: FontWeight.bold)),
                _buildRecipientList(isDark),
                const SizedBox(height: 100), // Buton icin bosluk
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildSendButton(),
          ),
          if (_isProcessing)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildStegoArea() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: const Color(0xFFADCFD0).withOpacity(0.3), borderRadius: BorderRadius.circular(15)),
              child: _imageFile == null
                  ? const Icon(Icons.add_a_photo, color: Color(0xFFADCFD0))
                  : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_imageFile!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: TextField(
              controller: _secretMsgController,
              decoration: const InputDecoration(
                labelText: "Gizli Veri",
                hintText: "Gorsele muhurlenecek mesaj...",
                labelStyle: TextStyle(color: Color(0xFFADCFD0), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInputArea(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _normalMsgController,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: "Normal mesajinizi yazin...",
          filled: true,
          fillColor: isDark ? Colors.white10 : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildRecipientList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername).collection('following').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final friendName = docs[index].id;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername).collection('followers').doc(friendName).snapshots(),
              builder: (context, followerSnap) {
                if (!followerSnap.hasData || !followerSnap.data!.exists) return const SizedBox.shrink();

                return CheckboxListTile(
                  value: _selectedRecipients.contains(friendName),
                  title: Text("@$friendName"),
                  activeColor: const Color(0xFFADCFD0),
                  onChanged: (val) {
                    setState(() {
                      val == true ? _selectedRecipients.add(friendName) : _selectedRecipients.remove(friendName);
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSendButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity, height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFBC8B6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
          onPressed: _broadcastNow,
          child: Text("Gonder (${_selectedRecipients.length})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
}