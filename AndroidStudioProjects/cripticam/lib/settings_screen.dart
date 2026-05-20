import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import 'login_screen.dart';
import 'package:cripticam/EditProfileScreen.dart';

class SettingsScreen extends StatefulWidget {
  final String currentUsername;
  const SettingsScreen({super.key, required this.currentUsername});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  void _showEditInfoModal() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).get();
    final data = doc.data() as Map<String, dynamic>;

    final adController = TextEditingController(text: data['ad'] ?? "");
    final soyadController = TextEditingController(text: data['soyad'] ?? "");
    final emailController = TextEditingController(text: data['email'] ?? "");
    final passController = TextEditingController();
    DateTime? selectedDate = (data['dogumGunu'] as Timestamp?)?.toDate();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Klavyenin modalı yukarı itmesi için şart
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          // 1. ADIM: Klavyenin yüksekliğini Padding olarak ekliyoruz
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ConstrainedBox(
            // Modalın ekranın en fazla %80'ini kaplamasını sağlıyoruz
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 20),
                  const Text("Bilgileri Düzenle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 25),

                  TextField(controller: adController, decoration: const InputDecoration(labelText: "Ad", border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextField(controller: soyadController, decoration: const InputDecoration(labelText: "Soyad", border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: "E-posta", border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextField(controller: passController, decoration: const InputDecoration(labelText: "Yeni Şifre", border: OutlineInputBorder()), obscureText: true),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(selectedDate == null ? "Doğum Günü Seç" : "Tarih: ${DateFormat('dd/MM/yyyy').format(selectedDate!)}"),
                    trailing: const Icon(Icons.cake_rounded, color: Color(0xFFFBC8B6)),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime(2000),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now()
                      );
                      if (picked != null) setModalState(() => selectedDate = picked);
                    },
                  ),
                  const Divider(height: 30),
                  _buildSmallAction(
                    label: "Profil Fotoğrafını Kaldır",
                    icon: Icons.no_photography_outlined,
                    color: Colors.redAccent,
                    onTap: () { Navigator.pop(context); _deletePhoto(); },
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => _saveInfo(adController.text, soyadController.text, emailController.text, passController.text, selectedDate),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBC8B6),
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    child: const Text("Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 2. ENGELLENENLER MODALI ---
  void _showBlockedModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        height: 400,
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("Engellenen Kişiler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('blocked').snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  if (snap.data!.docs.isEmpty) return const Center(child: Text("Engellenen kimse yok."));

                  return ListView.builder(
                    itemCount: snap.data!.docs.length,
                    itemBuilder: (c, i) {
                      final targetName = snap.data!.docs[i].id;
                      return ListTile(
                        title: Text("@$targetName"),
                        trailing: IconButton(
                          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                          onPressed: () => _unblockUser(targetName),
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

  // --- 3. HESAP SİLME VE YARDIMCI METOTLAR ---
  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    bool confirm = await _showDialog("Hesabı Sil", "Tüm verileriniz kalıcı olarak yok olacak. Emin misiniz?");
    if (confirm && user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).delete();
        await user.delete();
        if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const LoginScreen()), (r) => false);
      } catch (e) { _msg("Hata: Yeniden giriş yapmanız gerekebilir."); }
    }
  }

  Future<void> _deletePhoto() async {
    try {
      await FirebaseStorage.instance.ref().child('profile_pics/${widget.currentUsername}.jpg').delete();
      await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).update({'profilePic': FieldValue.delete()});
      _msg("Fotoğraf kaldırıldı.");
    } catch (_) { _msg("Fotoğraf zaten yok."); }
  }

  Future<void> _unblockUser(String targetUser) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).collection('blocked').doc(targetUser).delete();
      _msg("@$targetUser kullanıcısının engeli kaldırıldı.");
    } catch (e) { _msg("Hata: $e"); }
  }

  Future<void> _saveInfo(String a, String s, String e, String p, DateTime? d) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (p.isNotEmpty) await user?.updatePassword(p);
      if (e.isNotEmpty && e != user?.email) await user?.verifyBeforeUpdateEmail(e);
      await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).update({
        'ad': a, 'soyad': s, 'email': e, 'dogumGunu': d != null ? Timestamp.fromDate(d) : null,
      });
      if (mounted) Navigator.pop(context);
      _msg("Bilgiler güncellendi.");
    } catch (_) { _msg("Güncelleme başarısız."); }
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Ayarlar", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: isDarkMode ? Colors.white70 : Colors.black54),
            onPressed: () => Navigator.pop(context)
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: const Color(0xFFADCFD0),
            ),
            onPressed: () {
              setState(() {
                themeNotifier.value = isDarkMode ? ThemeMode.light : ThemeMode.dark;
              });
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildSettingButton(
                "Bilgileri Düzenle",
                Icons.manage_accounts_outlined,
                const Color(0xFFADCFD0),
                    () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => EditProfileScreen(currentUsername: widget.currentUsername)
                      )
                  );
                }
            ),
            _buildSettingButton("Engellenenleri Gör", Icons.block, const Color(0xFFFBC8B6), _showBlockedModal),
            const SizedBox(height: 16),
            _buildSettingButton("Hesabı Kalıcı Olarak Sil", Icons.delete_forever_rounded, Colors.redAccent, _deleteAccount),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingButton(String t, IconData i, Color c, VoidCallback onTap) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 10)]
        ),
        child: Row(
          children: [
            Icon(i, color: c),
            const SizedBox(width: 15),
            Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallAction({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 8), Text(label, style: TextStyle(color: color, fontSize: 12))]),
      ),
    );
  }

  Future<bool> _showDialog(String t, String c) async => await showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(t), content: Text(c), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal")), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Onayla", style: TextStyle(color: Colors.red)))])) ?? false;
  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
}