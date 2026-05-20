import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // UID almak için eklendi
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class CreateGroupScreen extends StatefulWidget {
  final String currentUsername;
  const CreateGroupScreen({super.key, required this.currentUsername});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _selectedUsers = {};
  File? _groupImage;
  bool _isProcessing = false;

  // --- CLOUDINARY YUKLEME ---
  Future<String?> _uploadGroupImage(File file) async {
    String cloudName = "dqim4rdfp";
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'));
      request.fields['upload_preset'] = 'cryptic_preset';
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        return jsonDecode(responseData)['secure_url'];
      }
    } catch (e) {
      debugPrint("Resim yukleme hatasi: $e");
    }
    return null;
  }

  // --- GRUP OLUSTURMA MOTORU ---
  Future<void> _createGroupNow() async {
    String groupName = _groupNameController.text.trim();

    if (groupName.isEmpty || _selectedUsers.isEmpty) {
      _msg("Lutfen grup ismi girin ve en az bir uye secin.");
      return;
    }

    setState(() => _isProcessing = true);

    try {
      String? imageUrl;
      if (_groupImage != null) {
        imageUrl = await _uploadGroupImage(_groupImage!);
      }

      // 1. Üye Listesi Hazırlığı
      List<String> finalMembers = _selectedUsers.toList();
      if (!finalMembers.contains(widget.currentUsername)) {
        finalMembers.add(widget.currentUsername);
      }

      // 2. Çoklu Admin Yapısı Hazırlığı (Başlangıçta sadece kurucu var)
      String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
      List<String> adminList = [widget.currentUsername];
      List<String> adminIdList = [myUid];

      String groupId = FirebaseFirestore.instance.collection('groups').doc().id;

      // 3. Firestore Kaydı
      await FirebaseFirestore.instance.collection('groups').doc(groupId).set({
        'groupId': groupId,
        'groupName': groupName,
        'groupPic': imageUrl ?? "",
        'members': finalMembers,
        // KRİTİK: Çoklu admin desteği için Liste (Array) olarak kaydediliyor
        'admins': adminList,
        'adminIds': adminIdList,
        // Geriye dönük uyumluluk için tekil alanları da dolduruyoruz
        'admin': widget.currentUsername,
        'adminId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': "Grup olusturuldu",
        'lastMessageTime': FieldValue.serverTimestamp(),
        'archivedBy': [],
      });

      _msg("Grup basariyla kuruldu.");
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
      appBar: AppBar(
        title: const Text("Yeni Grup"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(isDark),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Uye Secin (Karsilikli Takip)",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
              ),
              Expanded(child: _buildMutualUserList(isDark)),
              _buildCreateButton(),
            ],
          ),
          if (_isProcessing)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0)))),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final picker = ImagePicker();
              final XFile? img = await picker.pickImage(source: ImageSource.gallery);
              if (img != null) setState(() => _groupImage = File(img.path));
            },
            child: CircleAvatar(
              radius: 35,
              backgroundColor: const Color(0xFFADCFD0),
              backgroundImage: _groupImage != null ? FileImage(_groupImage!) : null,
              child: _groupImage == null ? const Icon(Icons.camera_alt, color: Colors.white) : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(
                hintText: "Grup ismi yazin...",
                border: UnderlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMutualUserList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUsername)
          .collection('following')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // WhatsApp mantığı: Kendini listede görme
        final docs = snapshot.data!.docs.where((d) => d.id != widget.currentUsername).toList();

        if (docs.isEmpty) return const Center(child: Text("Takip ettiginiz kimse yok."));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final friendName = docs[index].id;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.currentUsername)
                  .collection('followers')
                  .doc(friendName)
                  .snapshots(),
              builder: (context, followerSnap) {
                if (!followerSnap.hasData || !followerSnap.data!.exists) return const SizedBox.shrink();

                return CheckboxListTile(
                  activeColor: const Color(0xFFADCFD0),
                  secondary: const CircleAvatar(
                    backgroundColor: Color(0xFFFBC8B6),
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  title: Text("@$friendName"),
                  value: _selectedUsers.contains(friendName),
                  onChanged: (val) {
                    setState(() {
                      val == true ? _selectedUsers.add(friendName) : _selectedUsers.remove(friendName);
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

  Widget _buildCreateButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFADCFD0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _createGroupNow,
          child: const Text("Grubu Olustur",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
  }
}