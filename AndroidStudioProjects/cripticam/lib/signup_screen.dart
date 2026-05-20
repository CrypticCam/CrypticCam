import 'dart:convert'; // EmailJS API için
import 'dart:math';    // OTP üretimi için
import 'package:http/http.dart' as http; // http paketi
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  DateTime? _selectedDate;
  bool _isLoading = false;
  String? _sentVerificationCode; // Mail ile giden 6 haneli kod

  @override
  void dispose() {
    _nameController.dispose(); _surnameController.dispose();
    _usernameController.dispose(); _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- 1. ADIM: EMAILJS İLE KOD GÖNDERME ---
  Future<void> _sendOTP(String email, String username, String code) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'service_id': 'service_jvvbtns',
        'template_id': 'template_culssku',
        'user_id': 'un6NIYVdIl62u-MHP',
        'template_params': {
          'user_email': email,
          'user_name': username,
          'otp_code': code,
        },
      }),
    );

    // Hata ayıklama için
    if (response.statusCode != 200) {
      debugPrint("EmailJS Hatası: ${response.body}");
      throw "E-posta gönderilemedi. Hata Kodu: ${response.statusCode}";
    }
  }

  // ---  2. ADIM: KAYIT ÖN KONTROL VE OTP TETİĞİ ---
  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 1. Alan Kontrolleri
    if (name.isEmpty || surname.isEmpty || username.isEmpty || email.isEmpty || password.isEmpty || _selectedDate == null) {
      _showSnackBar("Lütfen tüm alanları doldurun.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ️ KONTROL A: Kullanıcı Adı Sorgusu
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
      if (userDoc.exists) throw "Bu kullanıcı adı zaten alınmış. ";

      //  KONTROL B: E-posta Sorgusu (YENİ EKLENEN KISIM)
      // Firestore'da bu e-postaya sahip başka bir döküman var mı bakıyoruz
      final emailQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (emailQuery.docs.isNotEmpty) {
        throw "Bu e-posta adresi zaten bir hesaba bağlı. ";
      }

      // 2. Kod Üret ve Mail Gönder (Eğer yukarıdaki kontrollerden geçerse)
      _sentVerificationCode = (Random().nextInt(900000) + 100000).toString();
      await _sendOTP(email, username, _sentVerificationCode!);

      if (mounted) _showVerificationDialog();

    } catch (e) {
      _showSnackBar(e.toString().replaceAll("Exception:", ""), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---  3. ADIM: OTP DOĞRULAMA PENCERESİ ---
  void _showVerificationDialog() {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Kodu Doğrula ", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Mail kutunuzu kontrol edin.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(hintText: "6 Haneli Kod", border: OutlineInputBorder())
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () {
              if (otpController.text == _sentVerificationCode) {
                Navigator.pop(ctx);
                _finalizeRegistration(); // Kod doğruysa kaydı bitir
              } else { _showSnackBar("Kod hatalı! ", isError: true); }
            },
            child: const Text("Doğrula"),
          ),
        ],
      ),
    );
  }

  // ---  4. ADIM: FİREBASE KAYDINI TAMAMLA ---
  Future<void> _finalizeRegistration() async {
    setState(() => _isLoading = true);
    try {
      // 1. Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Firestore Kaydı
      await FirebaseFirestore.instance.collection('users').doc(_usernameController.text.trim().toLowerCase()).set({
        'ad': _nameController.text.trim(),
        'soyad': _surnameController.text.trim(),
        'email': _emailController.text.trim(),
        'username': _usernameController.text.trim().toLowerCase(),
        'uid': userCredential.user?.uid,
        'dogumGunu': Timestamp.fromDate(_selectedDate!),
        'followers': 0,
        'following': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSnackBar("Başarıyla doğrulandı ve kaydedildi! ");
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
    } catch (e) {
      _showSnackBar("Kayıt Hatası: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI BÖLÜMÜ ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Image.asset('assets/images/logo.jpeg', height: 100, errorBuilder: (c, e, s) => const Icon(Icons.security, size: 100, color: Color(0xFFADCFD0))),
                const SizedBox(height: 20),
                const Text("Yeni Hesap Oluştur", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                _buildTextField(controller: _nameController, hintText: "Ad", icon: Icons.person_outline),
                const SizedBox(height: 15),
                _buildTextField(controller: _surnameController, hintText: "Soyad", icon: Icons.person_outline),
                const SizedBox(height: 15),
                _buildTextField(controller: _usernameController, hintText: "Kullanıcı Adı", icon: Icons.alternate_email),
                const SizedBox(height: 15),
                _buildDatePicker(context),
                const SizedBox(height: 15),
                _buildTextField(controller: _emailController, hintText: "E-posta", icon: Icons.email_outlined),
                const SizedBox(height: 15),
                _buildTextField(controller: _passwordController, hintText: "Şifre", icon: Icons.lock_outline, isPassword: true),
                const SizedBox(height: 30),
                _buildSignupButton(),
                const SizedBox(height: 20),
                _buildLoginLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hintText, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      child: TextField(
        controller: controller, obscureText: isPassword,
        decoration: InputDecoration(hintText: hintText, prefixIcon: Icon(icon, color: const Color(0xFFADCFD0)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20)),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime(2010),
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFADCFD0), onPrimary: Colors.white, onSurface: Colors.black)),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _selectedDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
        child: Row(children: [const Icon(Icons.cake_outlined, color: Color(0xFFADCFD0)), const SizedBox(width: 12), Text(_selectedDate == null ? "Doğum Tarihi Seçin" : DateFormat('dd/MM/yyyy').format(_selectedDate!))]),
      ),
    );
  }

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignup,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFBC8B6),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Kayıt Ol", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: () => Navigator.pop(context),
      child: RichText(
        text: const TextSpan(
          text: "Zaten hesabınız var mı? ",
          style: TextStyle(color: Colors.black54),
          children: [TextSpan(text: "Giriş Yap", style: TextStyle(color: Color(0xFFADCFD0), fontWeight: FontWeight.bold))],
        ),
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : const Color(0xFFADCFD0), behavior: SnackBarBehavior.floating));
  }
}