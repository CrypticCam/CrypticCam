import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_tab.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _usernameController.text = prefs.getString('remembered_username') ?? "";
      _rememberMe = prefs.getBool('remember_me') ?? false;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      _showSnackBar("Önce kullanıcı adınızı giriniz!");
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
      if (!userDoc.exists) {
        _showSnackBar("Bu kullanıcı adı sistemde kayıtlı değil.");
        return;
      }
      final email = userDoc.data()?['email'];
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnackBar("Sıfırlama linki $email adresine gönderildi! ");
    } catch (e) {
      _showSnackBar("E-posta gönderilemedi: $e");
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showSnackBar("Lütfen tüm alanları doldurun.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_rememberMe) {
        await prefs.setString('remembered_username', username);
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('remembered_username');
        await prefs.setBool('remember_me', false);
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
      if (!userDoc.exists) throw "Bu kullanıcı adı kayıtlı değil.";

      final email = userDoc.data()?['email'];
      if (email == null) throw "Kullanıcı verisi bozuk.";

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardTab(currentUsername: username),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg = "Giriş başarısız.";
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMsg = "Hatalı şifre veya kullanıcı adı.";
      }
      _showSnackBar(errorMsg);
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                const SizedBox(height: 30),
                const Text("CrypticCam", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const Text("Giriş Yap", style: TextStyle(fontSize: 16, color: Colors.black38)),
                const SizedBox(height: 50),
                _buildTextField(controller: _usernameController, hintText: "Kullanıcı Adı", icon: Icons.alternate_email),
                const SizedBox(height: 20),
                _buildTextField(controller: _passwordController, hintText: "Şifre", icon: Icons.lock_outline, isPassword: true),
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            activeColor: const Color(0xFFADCFD0),
                            onChanged: (val) => setState(() => _rememberMe = val!),
                          ),
                          const Text("Beni Hatırla", style: TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                      ),
                      TextButton(
                        onPressed: _handleForgotPassword,
                        child: const Text("Şifremi Unuttum?", style: TextStyle(color: Color(0xFFADCFD0), fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _buildLoginButton(),
                const SizedBox(height: 20),
                _buildSignupLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() => Image.asset('assets/images/logo.jpeg', height: 140, fit: BoxFit.contain);

  Widget _buildTextField({required TextEditingController controller, required String hintText, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow:
      [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        decoration: InputDecoration(hintText: hintText, prefixIcon:
        Icon(icon, color: const Color(0xFFADCFD0)), border: InputBorder.none, contentPadding:
        const EdgeInsets.symmetric(vertical: 20, horizontal: 20)),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFBC8B6),
            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0),
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) :
        const Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSignupLink() {
    return TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen())),
      child: RichText(text: const TextSpan(text: "Hesabınız yok mu? ", style: TextStyle(color: Colors.black54), children:
      [TextSpan(text: "Kayıt Ol", style: TextStyle(color: Color(0xFFADCFD0), fontWeight: FontWeight.bold))])),
    );
  }
}