import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentUsername;
  const EditProfileScreen({super.key, required this.currentUsername});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _adController = TextEditingController();
  final _soyadController = TextEditingController();
  final _emailController = TextEditingController();
  final _oldPassController = TextEditingController(); // Eski şifre için
  final _passController = TextEditingController();    // Yeni şifre için
  DateTime? _selectedDate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _adController.text = data['ad'] ?? "";
        _soyadController.text = data['soyad'] ?? "";
        _emailController.text = data['email'] ?? "";
        _selectedDate = (data['dogumGunu'] as Timestamp?)?.toDate();
        _isLoading = false;
      });
    }
  }

  // --- ŞİFRE GÜNCELLEME VE DOĞRULAMA MANTIĞI ---
  Future<void> _saveInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    final String newPass = _passController.text.trim();
    final String oldPass = _oldPassController.text.trim();

    try {
      // 1. Şifre değiştirilmek isteniyorsa kontrolleri yap
      if (newPass.isNotEmpty) {
        // Eski şifre girilmemişse uyar
        if (oldPass.isEmpty) {
          _msg("Şifre değiştirmek için eski şifrenizi girmelisiniz!", Colors.orange);
          return;
        }

        // Yeni şifre uzunluk kontrolü (8 karakter kuralı)
        if (newPass.length < 8) {
          _msg("Yeni şifre en az 8 karakter olmalıdır!", Colors.red);
          return;
        }

        // 2. Firebase Re-authentication (Yeniden Doğrulama)
        // Kullanıcı uzun süredir giriş yapmışsa şifre değiştirmek için bu adım şarttır.
        AuthCredential credential = EmailAuthProvider.credential(
          email: user!.email!,
          password: oldPass,
        );

        await user.reauthenticateWithCredential(credential);

        // 3. Doğrulama başarılıysa şifreyi güncelle
        await user.updatePassword(newPass);
      }

      // 4. Firestore verilerini güncelle (Ad, Soyad, Email, Doğum Günü)
      await FirebaseFirestore.instance.collection('users').doc(widget.currentUsername).update({
        'ad': _adController.text.trim(),
        'soyad': _soyadController.text.trim(),
        'email': _emailController.text.trim(),
        'dogumGunu': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
      });

      if (mounted) {
        Navigator.pop(context);
        _msg("Bilgiler başarıyla güncellendi! ", Colors.green);
      }
    } on FirebaseAuthException catch (e) {
      // Şifre yanlışsa buraya düşer
      if (e.code == 'wrong-password') {
        _msg("Eski şifreniz hatalı!", Colors.red);
      } else {
        _msg("Hata: ${e.message}", Colors.red);
      }
    } catch (e) {
      _msg("Güncelleme başarısız: $e", Colors.red);
    }
  }

  void _msg(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bilgileri Düzenle"),
        backgroundColor: const Color(0xFFADCFD0),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _adController, decoration: const InputDecoration(labelText: "Ad", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _soyadController, decoration: const InputDecoration(labelText: "Soyad", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: "E-posta", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            const Divider(height: 40, thickness: 1),

            // --- ŞİFRE BÖLÜMÜ ---
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Şifre Değiştir", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _oldPassController,
              decoration: const InputDecoration(labelText: "Mevcut Şifre", border: OutlineInputBorder(), hintText: "Doğrulama için gerekli"),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: "Yeni Şifre", border: OutlineInputBorder(), hintText: "En az 8 karakter"),
              obscureText: true,
            ),

            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_selectedDate == null ? "Doğum Günü Seç" : "Tarih: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}"),
              trailing: const Icon(Icons.cake_rounded, color: Color(0xFFFBC8B6)),
              onTap: () async {
                final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate ?? DateTime(2000),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now()
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _saveInfo,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBC8B6),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              child: const Text("KAYDET", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}