import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_tab.dart';

class VerificationScreen extends StatefulWidget {
  final String generatedCode;
  final Map<String, String> userData;

  const VerificationScreen({super.key, required this.generatedCode, required this.userData});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _codeController = TextEditingController();
  bool _isBusy = false;

  Future<void> _completeRegistration() async {
    // 1. KOD KONTROLÜ
    if (_codeController.text.trim() != widget.generatedCode) {
      _msg("Hatalı doğrulama kodu!");
      return;
    }

    setState(() => _isBusy = true);

    try {
      // 2. FIREBASE AUTH KAYDI
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: widget.userData['email']!,
        password: widget.userData['password']!,
      );

      // 3. FIRESTORE KAYDI
      // Not: Kullanıcı adı doküman ID olarak kullanılır.
      await FirebaseFirestore.instance.collection('users').doc(widget.userData['username']).set({
        'uid': cred.user!.uid,
        'ad': widget.userData['ad'],
        'soyad': widget.userData['soyad'],
        'username': widget.userData['username'],
        'email': widget.userData['email'],
        'followers': 0,
        'following': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _msg("Kayıt başarılı! Hoş geldin.");


        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (c) => DashboardTab(
                currentUsername: widget.userData['username']!,
              ),
            ),
                (r) => false
        );
      }
    } catch (e) {
      _msg(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context)
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            const Icon(Icons.verified_user_outlined, size: 80, color: Color(0xFFFBC8B6)),
            const SizedBox(height: 24),
            Text(
                "${widget.userData['email']} adresine gelen 6 haneli kodu girin.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)
              ),
            ),
            const SizedBox(height: 32),
            _isBusy ? const CircularProgressIndicator() : _buildVerifyBtn(),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyBtn() {
    return ElevatedButton(
      onPressed: _completeRegistration,
      style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFADCFD0),
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
      ),
      child: const Text("Doğrula ve Kaydı Tamamla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}