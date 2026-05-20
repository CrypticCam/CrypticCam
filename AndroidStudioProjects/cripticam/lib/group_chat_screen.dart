import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'group_member_management_screen.dart';
import '../utils/stego_utils.dart';
import '../utils/chat_utils.dart';
import 'biometric_service.dart';
import 'starred_messages_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUsername;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUsername,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  bool _isProcessing = false;
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  File? _backgroundImage; // Dinamik arka plan dosyası

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Uygulama durum değişikliklerini dinle
    _loadBackground(); // Kayıtlı arka planı yükle
    _updateLastReadTime(); // Gruba ilk girildiğinde zamanı güncelle
  }

  @override
  void dispose() {
    _updateLastReadTime(); // Gruptan tamamen çıkarken zamanı son kez güncelle
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    super.dispose();
  }

  // Kullanıcı uygulamayı arka plana atarsa veya kapatırsa zamanı korumak için
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _updateLastReadTime();
    } else if (state == AppLifecycleState.resumed) {
      _updateLastReadTime();
    }
  }

  // --- ZAMAN DAMGASI GÜNCELLEME MOTORU (YENİ) ---
  void _updateLastReadTime() async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'lastRead_${widget.currentUsername}': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Grup zaman damgası güncellenemedi: $e");
    }
  }

  // --- ARKA PLAN İŞLEMLERİ ---
  Future<void> _loadBackground() async {
    File? savedImage = await ChatUtils.loadSavedBackground(widget.groupId);
    if (savedImage != null && mounted) {
      setState(() => _backgroundImage = savedImage);
    }
  }

  Future<void> _changeBackground() async {
    File? newImage = await ChatUtils.pickAndSaveBackground(widget.groupId);
    if (newImage != null && mounted) {
      setState(() => _backgroundImage = newImage);
      _msg("Arka plan güncellendi");
    }
  }

  void _showWallpaperOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Grup Arka Planı Ayarları", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFADCFD0)),
              title: const Text("Yeni Fotoğraf Seç"),
              onTap: () {
                Navigator.pop(ctx);
                _changeBackground();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text("Arka Planı Kaldır", style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await ChatUtils.clearSavedBackground(widget.groupId);
                if (mounted) {
                  setState(() => _backgroundImage = null);
                  _msg("Varsayılan temaya dönüldü.");
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- GRUP DETAYLARI MODALI ---
  void _showGroupDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;

          String adminDisplay = data['admin'] ?? "Yonetici";
          List members = data['members'] ?? [];
          String? groupPic = data['groupPic'];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: Text(data['groupName'] ?? widget.groupName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: const Color(0xFFADCFD0),
                  backgroundImage: (groupPic != null && groupPic.isNotEmpty) ? NetworkImage(groupPic) : null,
                  child: (groupPic == null || groupPic.isEmpty) ? const Icon(Icons.groups, size: 45, color: Colors.white) : null,
                ),
                const SizedBox(height: 20),
                const Text("Grup Yoneticisi:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text("@$adminDisplay", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFBC8B6))),
                const Divider(height: 30),
                Text("Toplam Uye: ${members.length}", style: const TextStyle(fontSize: 14)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Kapat")),
            ],
          );
        },
      ),
    );
  }

  // --- GRUP DUZENLEME MODALI ---
  void _showEditGroupDialog(String currentName, String? currentPic) {
    TextEditingController nameCont = TextEditingController(text: currentName);
    File? selectedImg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Grubu Duzenle"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (img != null) setDialogState(() => selectedImg = File(img.path));
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFFADCFD0),
                    backgroundImage: selectedImg != null
                        ? FileImage(selectedImg!)
                        : (currentPic != null && currentPic.isNotEmpty ? NetworkImage(currentPic) : null),
                    child: (selectedImg == null && (currentPic == null || currentPic.isEmpty))
                        ? const Icon(Icons.camera_alt, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCont,
                  decoration: const InputDecoration(
                    labelText: "Yeni Grup Adi",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Iptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFADCFD0)),
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isProcessing = true);
                try {
                  if (nameCont.text.trim().isNotEmpty) {
                    await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
                      'groupName': nameCont.text.trim(),
                    });
                  }
                  if (selectedImg != null) {
                    String url = await _uploadToWeb(selectedImg!);
                    await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
                      'groupPic': url,
                    });
                  }
                } finally {
                  if (mounted) setState(() => _isProcessing = false);
                }
              },
              child: const Text("Kaydet", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- CLOUDINARY YUKLEME ---
  Future<String> _uploadToWeb(File file) async {
    String cloudName = "dqim4rdfp";
    var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));
    request.fields['upload_preset'] = 'cryptic_preset';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    var responseData = await response.stream.bytesToString();
    if (response.statusCode == 200) return jsonDecode(responseData)['secure_url'];
    throw "Yukleme hatasi";
  }

  // --- NORMAL MESAJ GONDERME ---
  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    String msg = _messageController.text.trim();
    _messageController.clear();

    await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').add({
      'sender': widget.currentUsername,
      'text': msg,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'text',
      'isDestroyed': false,
      'reactions': {},
    });
    _updateLastMessage(msg);
  }

  // --- LSB GIZLE VE GONDER ---
  Future<void> _handleGroupGizle() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    String? secretMsg = await _showTextDialog(context);
    if (secretMsg == null || secretMsg.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      Uint8List originalBytes = await File(pickedFile.path).readAsBytes();
      String encryptedMsg = StegoUtils.encryptMessage(secretMsg);
      Uint8List stegoBytes = StegoUtils.embedData(originalBytes, encryptedMsg);

      final tempDir = await Directory.systemTemp.createTemp();
      File stegoFile = File('${tempDir.path}/stego_group.png');
      await stegoFile.writeAsBytes(stegoBytes);

      String webUrl = await _uploadToWeb(stegoFile);

      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').add({
        'sender': widget.currentUsername,
        'imageUrl': webUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'image',
        'isDestroyed': false,
        'reactions': {},
      });
      _updateLastMessage("Gizli bir gorsel paylasildi");
    } catch (e) {
      debugPrint("Stego Hatasi: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- FAVORILEME ---
  Future<void> _starMessage(Map<String, dynamic> msgData, String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUsername)
          .collection('starredMessages')
          .doc(messageId)
          .set({
        ...msgData,
        'starredAt': FieldValue.serverTimestamp(),
        'originalGroupId': widget.groupId,
        'messageId': messageId,
        'isFromGroup': true,
      });
      _msg("Mesaj yildizlandi");
    } catch (e) { _msg("Hata!"); }
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .doc(messageId)
        .set({
      'reactions': {
        widget.currentUsername: emoji,
      }
    }, SetOptions(merge: true));
  }

  // --- ARSIVLEME ---
  Future<void> _archiveThisGroup() async {
    await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
      'archivedBy': FieldValue.arrayUnion([widget.currentUsername]),
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _updateLastMessage(String msg) async {
    await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
      'lastMessage': msg,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
    _updateLastReadTime(); // Mesajı gönderen kişi için de anında zamanı güncelle
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        var groupData = snapshot.data!.data() as Map<String, dynamic>;

        List adminIds = groupData['adminIds'] ?? [];
        bool isAdmin = adminIds.contains(_myUid);
        String? groupPic = groupData['groupPic'];
        String currentGroupName = groupData['groupName'] ?? widget.groupName;

        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => _showGroupDetails(context),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFFBC8B6),
                    backgroundImage: (groupPic != null && groupPic.isNotEmpty) ? NetworkImage(groupPic) : null,
                    child: (groupPic == null || groupPic.isEmpty) ? const Icon(Icons.groups, size: 18, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentGroupName, style: const TextStyle(fontSize: 16)),
                        const Text("Grup bilgiisi icin tikla", style: TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'members') {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => GroupMemberManagementScreen(groupId: widget.groupId, currentUsername: widget.currentUsername)));
                  } else if (value == 'archive') {
                    _archiveThisGroup();
                  } else if (value == 'edit') {
                    _showEditGroupDialog(currentGroupName, groupPic);
                  } else if (value == 'wallpaper') {
                    if (_backgroundImage != null) {
                      _showWallpaperOptions();
                    } else {
                      _changeBackground();
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'members', child: ListTile(leading: Icon(Icons.group_outlined), title: Text("Uyeler"))),
                  const PopupMenuItem(value: 'archive', child: ListTile(leading: Icon(Icons.archive_outlined), title: Text("Arsivle"))),
                  const PopupMenuItem(value: 'wallpaper', child: ListTile(leading: Icon(Icons.wallpaper_rounded), title: Text("Arka Plan"))),
                  if (isAdmin)
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text("Duzenle"))),
                ],
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. KATMAN: DINAMIK ARKA PLAN
              Positioned.fill(
                child: _backgroundImage != null
                    ? Image.file(_backgroundImage!, fit: BoxFit.cover)
                    : Container(color: isDark ? Colors.black : Colors.white),
              ),
              // 2. KATMAN: OKUNABILIRLIK ICIN OPAKLIK
              Container(color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.15)),

              // 3. KATMAN: ASIL ICERIK
              Column(
                children: [
                  Expanded(child: _buildMessageList(isDark)),
                  _buildMessageInput(),
                ],
              ),
              if (_isProcessing) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0)))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        // Ben sohbetin içindeyken yeni bir mesaj akışı düşerse zaman damgasını anlık güncelle
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateLastReadTime());

        var docs = snapshot.data!.docs;
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            bool isMe = data['sender'] == widget.currentUsername;
            bool isDestroyed = data['isDestroyed'] ?? false;
            String messageId = docs[index].id;

            // İfadeleri Map olarak alıyoruz
            Map reactions = data['reactions'] ?? {};

            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Stack(
                clipBehavior: Clip.none, // İfadelerin balondan taşabilmesi için
                children: [
                  GestureDetector(
                    onLongPress: () {
                      if (!isDestroyed) {
                        _showMessageOptions(data, messageId, isMe);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDestroyed
                            ? (isMe ? const Color(0xFFD1E8E9) : Colors.grey[400])
                            : (isMe
                            ? const Color(0xFFADCFD0)
                            : (isDark ? Colors.grey[800] : Colors.grey[300])),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: isDestroyed
                          ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.grey),
                          SizedBox(width: 5),
                          Text("Imha Edildi", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      )
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(
                              data['sender'],
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFBC8B6),
                              ),
                            ),
                          data['type'] == 'image'
                              ? GestureDetector(
                            onDoubleTap: () => _handleImageDecryption(data['imageUrl'], messageId),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(data['imageUrl'], width: 200, fit: BoxFit.cover),
                            ),
                          )
                              : Text(
                            data['text'] ?? "",
                            style: TextStyle(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // --- İFADELERİN GÖSTERİLDİĞİ KISIM ---
                  if (reactions.isNotEmpty)
                    Positioned(
                      bottom: -4,
                      right: isMe ? 20 : null,
                      left: !isMe ? 20 : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF333333) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 3, spreadRadius: 1)
                          ],
                        ),
                        child: Text(
                          reactions.values.toSet().join(" "),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.transparent,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFFFBC8B6)), onPressed: _handleGroupGizle),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Mesaj yaz...",
                filled: true,
                fillColor: Theme.of(context).cardColor.withOpacity(0.9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFFADCFD0),
            child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _sendMessage),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Map<String, dynamic> msgData, String msgId, bool isMe) {
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
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ["❤️", "👍", "😂", "😮", "😢", "🙏"].map((e) => GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addReaction(msgId, e);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  )).toList(),
                ),
              ),
            if (!isMe) const Divider(),
            ListTile(
              leading: const Icon(Icons.star_border, color: Color(0xFFFBC8B6)),
              title: const Text("Yildizla"),
              onTap: () {
                Navigator.pop(ctx);
                _starMessage(msgData, msgId);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageDecryption(String imageUrl, String messageId) async {
    bool auth = await BiometricService.authenticate();
    if (auth) {
      setState(() => _isProcessing = true);
      try {
        var res = await http.get(Uri.parse(imageUrl));
        String encrypted = StegoUtils.extractData(res.bodyBytes);
        if (!mounted) return;
        showDialog(context: context, builder: (ctx) => _MatrixDecodeDialog(secretText: encrypted, messageId: messageId, groupId: widget.groupId));
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<String?> _showTextDialog(BuildContext context) async {
    TextEditingController c = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text("Veri Muhurle"), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Devam"))]));
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
  }
}

class _MatrixDecodeDialog extends StatefulWidget {
  final String secretText;
  final String messageId;
  final String groupId;
  const _MatrixDecodeDialog({required this.secretText, required this.messageId, required this.groupId});
  @override State<_MatrixDecodeDialog> createState() => _MatrixDecodeDialogState();
}

class _MatrixDecodeDialogState extends State<_MatrixDecodeDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _displayText = "";
  bool _isDecoded = false;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..addListener(() {
      setState(() {
        if (_controller.value < 0.8) {
          _displayText = List.generate(8, (i) => String.fromCharCode(Random().nextInt(93) + 33)).join();
        } else {
          _isDecoded = true;
          _displayText = StegoUtils.decryptMessage(widget.secretText);
        }
      });
    });
    _controller.forward();
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      title: Text(_isDecoded ? "COZULDU" : "COZULUYOR...", style: const TextStyle(color: Colors.greenAccent)),
      content: Text(_displayText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 18)),
      actions: [TextButton(onPressed: () async {
        await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').doc(widget.messageId).update({'isDestroyed': true});
        if (mounted) Navigator.pop(context);
      }, child: const Text("IMHA ET", style: TextStyle(color: Colors.red)))],
    );
  }
}