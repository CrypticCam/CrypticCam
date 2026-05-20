import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Ekranlar
import 'login_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'starred_messages_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isUploading = false;
  List<DocumentSnapshot> _filteredUsers = [];
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _fetchMyUsername();
  }

  // --- VERİ ÇEKME İŞLEMLERİ ---

  Future<void> _fetchMyUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty && mounted) {
        final data = userDoc.docs.first.data();
        setState(() => _currentUsername = userDoc.docs.first.id);
        _checkBirthdayGreeting(data);
      }
    }
  }

  Future<void> _checkBirthdayGreeting(Map<String, dynamic> userData) async {
    if (userData['dogumGunu'] == null) return;
    DateTime today = DateTime.now();
    DateTime birthday = (userData['dogumGunu'] as Timestamp).toDate();

    if (today.day == birthday.day && today.month == birthday.month) {
      String lastGreetingYear = userData['lastGreetingYear'] ?? "";
      if (lastGreetingYear != today.year.toString()) {
        final chatRef = FirebaseFirestore.instance
            .collection('chats')
            .doc("crypticcam_$_currentUsername");

        await chatRef.set({
          'participants': ["CrypticCam", _currentUsername],
          'lastMessage': "İyi ki doğdun, iyi ki aramızdasın! ",
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUsername!)
            .update({'lastGreetingYear': today.year.toString()});
      }
    }
  }

  // --- FOTOĞRAF VE TAKİP İŞLEMLERİ ---

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 25
    );

    if (image == null || _currentUsername == null) return;

    setState(() => _isUploading = true);
    try {
      final Uint8List bytes = await image.readAsBytes();
      String base64Image = base64Encode(bytes);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUsername!)
          .update({'profilePic': base64Image});

      if (mounted) _msg("Profil fotoğrafı güncellendi! 🛡");
    } catch (e) {
      if (mounted) _msg("Hata oluştu veya dosya çok büyük.");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeFollower(String followerName) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    DocumentReference myRef = FirebaseFirestore.instance.collection('users').doc(_currentUsername!);
    DocumentReference theirRef = FirebaseFirestore.instance.collection('users').doc(followerName);

    batch.delete(myRef.collection('followers').doc(followerName));
    batch.delete(theirRef.collection('following').doc(_currentUsername!));
    batch.update(myRef, {'followers': FieldValue.increment(-1)});
    batch.update(theirRef, {'following': FieldValue.increment(-1)});

    await batch.commit();
    _msg("@$followerName takipçilerinden çıkarıldı.");
  }

  Future<void> _unfollowUser(String targetName) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    DocumentReference myRef = FirebaseFirestore.instance.collection('users').doc(_currentUsername!);
    DocumentReference theirRef = FirebaseFirestore.instance.collection('users').doc(targetName);

    batch.delete(myRef.collection('following').doc(targetName));
    batch.delete(theirRef.collection('followers').doc(_currentUsername!));
    batch.update(myRef, {'following': FieldValue.increment(-1)});
    batch.update(theirRef, {'followers': FieldValue.increment(-1)});

    await batch.commit();
    _msg("@$targetName takibi bırakıldı.");
  }

  // --- ANA BUILD METODU ---

  @override
  Widget build(BuildContext context) {
    if (_currentUsername == null) return const Center(child: CircularProgressIndicator());
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername!).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String? profilePicBase64 = data['profilePic'];

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFFF5F2),
          appBar: _buildAppBar(isDark),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                if (!_isSearching) ...[
                  _buildProfileHeader(profilePicBase64, data, isDark),
                  const SizedBox(height: 30),
                  _buildStatCard(data, isDark),
                  const SizedBox(height: 20),
                  _buildStarredMessagesButton(isDark),
                  const SizedBox(height: 25),
                ],
                _buildSearchInput(isDark),
                if (_isSearching) _buildSearchResults(isDark),
                if (!_isSearching) ...[
                  const SizedBox(height: 30),
                  _buildQRCodeSection(isDark),
                  const SizedBox(height: 40),
                  _buildLogoutButton(isDark),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UI BİLEŞENLERİ ---

  Widget _buildStarredMessagesButton(bool isDark) {
    return InkWell(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => StarredMessagesScreen(currentUsername: _currentUsername!)
          )
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFFFBC8B6).withOpacity(0.5),
              width: 1
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFBC8B6), size: 28),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                "Yıldızlı Mesajlar",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String? base64String, Map<String, dynamic> data, bool isDark) {
    bool hasImage = base64String != null && base64String.trim().isNotEmpty;

    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              backgroundImage: hasImage
                  ? MemoryImage(base64Decode(base64String!.trim()))
                  : null,
              child: !hasImage ? const Icon(Icons.person, size: 55, color: Color(0xFFFBC8B6)) : null,
            ),
            if (_isUploading)
              const Positioned.fill(
                  child: CircularProgressIndicator(color: Color(0xFFADCFD0), strokeWidth: 2)
              ),
            Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFADCFD0),
                        child: Icon(Icons.camera_alt, size: 18, color: Colors.white)
                    )
                )
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
            "${data['ad'] ?? ''} ${data['soyad'] ?? ''}",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)
        ),
        Text("@$_currentUsername", style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 15),
        _buildSettingsButton(),
      ],
    );
  }

  Widget _buildStatCard(Map<String, dynamic> data, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFADCFD0).withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFADCFD0).withOpacity(0.4), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(data['followers']?.toString() ?? "0", "Takipçi", Icons.people_outline, "followers", isDark),
          Container(height: 30, width: 1, color: const Color(0xFFADCFD0).withOpacity(0.2)),
          _buildStatItem(data['following']?.toString() ?? "0", "Takip", Icons.person_add_outlined, "following", isDark),
        ],
      ),
    );
  }

  Widget _buildSearchInput(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFADCFD0).withOpacity(0.3), width: 0.8),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _searchUser,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: "Arkadaşlarını bul...",
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFADCFD0)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final userDoc = _filteredUsers[index];
        final userData = userDoc.data() as Map<String, dynamic>;
        final tUser = userDoc.id;
        final String? searchUserPic = userData['profilePic'];
        bool hasSearchImg = searchUserPic != null && searchUserPic.trim().isNotEmpty;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUsername!)
              .collection('following')
              .doc(tUser)
              .snapshots(),
          builder: (context, followSnap) {
            bool isAlreadyFollowing = followSnap.hasData && followSnap.data!.exists;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(tUser)
                  .collection('requests')
                  .doc(_currentUsername!)
                  .snapshots(),
              builder: (context, requestSnap) {
                bool isRequestSent = requestSnap.hasData && requestSnap.data!.exists;

                String buttonText = "Takip Et";
                Color buttonColor = const Color(0xFFFBC8B6);
                bool isDisable = false;

                if (isAlreadyFollowing) {
                  buttonText = "Takip";
                  buttonColor = isDark ? Colors.white12 : Colors.grey[300]!;
                  isDisable = true;
                } else if (isRequestSent) {
                  buttonText = "İstek Gönderildi";
                  buttonColor = isDark ? Colors.white10 : Colors.grey[200]!;
                  isDisable = true;
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFADCFD0),
                    backgroundImage: hasSearchImg ? MemoryImage(base64Decode(searchUserPic!.trim())) : null,
                    child: !hasSearchImg ? Icon(Icons.person, color: isDark ? Colors.white24 : Colors.white) : null,
                  ),
                  title: Text("@$tUser", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  trailing: ElevatedButton(
                    onPressed: isDisable ? null : () => _sendFollowRequest(tUser),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text(buttonText, style: TextStyle(color: isDisable ? Colors.black38 : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showFollowList(String title, String collection) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        height: 400,
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername!).collection(collection).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, idx) {
                      final u = snapshot.data!.docs[idx].id;
                      return ListTile(
                        title: Text("@$u", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                          onPressed: () => collection == "followers" ? _removeFollower(u) : _unfollowUser(u),
                        ),
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

  // --- YARDIMCI METODLAR ---

  Widget _buildSettingsButton() {
    return ElevatedButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(currentUsername: _currentUsername!))),
      style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFADCFD0).withOpacity(0.1),
          foregroundColor: const Color(0xFFADCFD0),
          elevation: 0,
          side: const BorderSide(color: Color(0xFFADCFD0), width: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
      ),
      child: const Text("Profil Ayarları", style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatItem(String count, String label, IconData icon, String col, bool isDark) {
    return GestureDetector(
      onTap: () => _showFollowList(label, col),
      child: Column(
          children: [
            Icon(icon, color: const Color(0xFFADCFD0), size: 20),
            const SizedBox(height: 4),
            Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11))
          ]
      ),
    );
  }

  Widget _buildQRCodeSection(bool isDark) {
    return Column(
        children: [
          Text("Hızlı Erişim QR", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: isDark ? const Color(0xFFADCFD0).withOpacity(0.3) : Colors.transparent)
              ),
              child: QrImageView(
                  data: _currentUsername!,
                  version: QrVersions.auto,
                  size: 150.0,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFFADCFD0)),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: isDark ? Colors.white : const Color(0xFFFBC8B6))
              )
          )
        ]
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(_currentUsername!).collection('requests').snapshots(),
            builder: (context, snapshot) {
              int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return IconButton(
                  icon: Badge(
                      label: count > 0 ? Text(count.toString()) : null,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.notifications_none_rounded, color: Color(0xFFADCFD0), size: 28)
                  ),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationsScreen(currentUsername: _currentUsername!)))
              );
            }
        ),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFADCFD0), size: 28), onPressed: _openQRScanner),
          const SizedBox(width: 15)
        ]
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return SizedBox(
        width: double.infinity,
        child: TextButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (r) => false);
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text("Güvenli Çıkış Yap"),
            style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 15)
            )
        )
    );
  }

  void _searchUser(String q) async {
    if (q.isEmpty) { setState(() => _isSearching = false); return; }
    setState(() => _isSearching = true);
    final results = await FirebaseFirestore.instance.collection('users')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: q.toLowerCase())
        .where(FieldPath.documentId, isLessThanOrEqualTo: '${q.toLowerCase()}\uf8ff').get();
    if (mounted) setState(() => _filteredUsers = results.docs.where((doc) => doc.id != _currentUsername).toList());
  }

  Future<void> _sendFollowRequest(String t) async {
    if (t == _currentUsername) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(t).collection('requests').doc(_currentUsername).set({
        'from': _currentUsername,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending'
      });
      _msg("İstek gönderildi.");
    } catch (e) { _msg("Hata!"); }
  }

  void _openQRScanner() async {
    final String? scanned = await Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen()));
    if (scanned != null && scanned != _currentUsername) _sendFollowRequest(scanned);
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
  }
}

class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("QR Tara")),
        body: MobileScanner(
            onDetect: (capture) {
              final b = capture.barcodes;
              if (b.isNotEmpty && b.first.rawValue != null) Navigator.pop(context, b.first.rawValue);
            }
        )
    );
  }
}