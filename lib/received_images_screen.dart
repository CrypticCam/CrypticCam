
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../utils/stego_utils.dart';
import 'biometric_service.dart';

class ReceivedImagesScreen extends StatefulWidget {
  final String currentUsername;
  const ReceivedImagesScreen({super.key, required this.currentUsername});

  @override
  State<ReceivedImagesScreen> createState() => _ReceivedImagesScreenState();
}

class _ReceivedImagesScreenState extends State<ReceivedImagesScreen> {
  bool _isProcessing = false;

  // --- URL ÜZERİNDEN RESMİ İNDİR VE PİKSELLERDEN ÇÖZ ---
  // Eski hali muhtemelen: Future<void> _processImageFromUrl(String url) async { ... }

  Future<void> _processImageFromUrl(String url, String messageId, Timestamp? expiresAt) async {
    // 1. Biyometrik Doğrulama
    bool authenticated = await BiometricService.authenticate();

    if (authenticated) {
      setState(() => _isProcessing = true);
      try {
        // 2. Resmi indir
        var response = await http.get(Uri.parse(url));

        // 3. Piksellerden veriyi sök (LSB Extraction)
        String extractedEncrypted = StegoUtils.extractData(response.bodyBytes);

        if (!mounted) return;

        // 4. Matrix efektli deşifre diyaloğunu göster
        _showResultDialog(extractedEncrypted, messageId, url, expiresAt);

      } catch (e) {
        _showSnackBar("Piksellerde gizli veri bulunamadı veya bozulmuş.");
      } finally {
        setState(() => _isProcessing = false);
      }
    } else {
      _showSnackBar("Kimlik doğrulaması başarısız!");
    }
  }

  void _showResultDialog(String text, String messageId, String roomId, Timestamp? expiresAt) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MatrixDecodeDialog(
        secretText: text,
        messageId: messageId,
        roomId: roomId,
        expiresAt: expiresAt,
      ),
    );
  }
  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7F5),
      appBar: AppBar(
        title: const Text("Gelen Fotoğraflar"),
        backgroundColor: const Color(0xFFADCFD0),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSnackBar("Süresi dolan görseller otomatik imha edilir."),
          )
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            // 1. ADIM: Tüm odalardaki 'messages' koleksiyonlarını tara
            stream: FirebaseFirestore.instance
                .collectionGroup('messages')
                .where('receiverId', isEqualTo: widget.currentUsername) // Bana gelenler
                .orderBy('timestamp', descending: true) // En yeni en üstte
                .snapshots(),
            builder: (context, snapshot) {
              // Hata kontrolü (Terminaldeki Index linkini buradan yakalayabilirsin)
              if (snapshot.hasError) {
                print("Sorgu Hatası: ${snapshot.error}");
                return Center(child: Text("Hata: ${snapshot.error}"));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // --- MÜHENDİSLİK ANALİZİ: Gelen ham veriyi filtreleme ---
              final now = DateTime.now();
              final allMessages = snapshot.data?.docs ?? [];

              // DEBUG: Kaç tane döküman geldiğini terminalden izle
              print("Toplam gelen döküman: ${allMessages.length}");

              final activeDocs = allMessages.where((doc) {
                var data = doc.data() as Map<String, dynamic>;

                // Sadece imageUrl olanları al (Metin mesajlarını ele)
                bool hasImage = data.containsKey('imageUrl') && data['imageUrl'] != null;

                // Süre kontrolü
                Timestamp? expiresAt = data['expiresAt'];
                bool isNotExpired = expiresAt != null && expiresAt.toDate().isAfter(now);

                return hasImage && isNotExpired;
              }).toList();

              // Görsel yoksa veya hepsi imha edildiyse
              if (activeDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_delete_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        "Aktif bir gizli görselin yok.\nSüresi dolmuş olabilir.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // Yan yana iki resim
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: activeDocs.length,
                itemBuilder: (context, index) {
                  var data = activeDocs[index].data() as Map<String, dynamic>;
                  String url = data['imageUrl'] ?? "";
                  String messageId = activeDocs[index].id;
                  Timestamp? expiresAt = data['expiresAt'];

                  return GestureDetector(
                    // Resme tıklandığında deşifre sürecini başlat
                    onTap: () => _processImageFromUrl(url, messageId, expiresAt),
                    child: Hero(
                      tag: url,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Resim önizlemesi
                              Image.network(
                                url,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                              ),
                              // Üzerine parmak izi katmanı
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                                  ),
                                ),
                              ),
                              const Center(
                                child: Icon(Icons.fingerprint, color: Colors.white, size: 45),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: Color(0xFFADCFD0))),
            ),
        ],
      ),
    );
  }
}

// --- MATRIX DECODE DIALOG---
class _MatrixDecodeDialog extends StatefulWidget {
  final String secretText;
  final String messageId;
  final String? roomId; //  Burayı String? (opsiyonel) yapalım
  final Timestamp? expiresAt; //  Bu parametre eksikti, ekledik

  const _MatrixDecodeDialog({
    required this.secretText,
    required this.messageId,
    this.roomId, // Artık opsiyonel
    this.expiresAt, // Yeni ekledik
  });

  @override State<_MatrixDecodeDialog> createState() => _MatrixDecodeDialogState();
}

class _MatrixDecodeDialogState extends State<_MatrixDecodeDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _displayText = "";
  bool _isDecoded = false;
  int _secondsRemaining = 300;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..addListener(() {
      setState(() {
        if (_controller.value < 0.8) {
          // Matrix efekti için rastgele karakterler
          _displayText = List.generate(widget.secretText.length, (index) => String.fromCharCode(_random.nextInt(93) + 33)).join();
        } else {
          _isDecoded = true;
          try {
            // Şifreli metni AES-256 ile deşifre ediyoruz
            _displayText = StegoUtils.decryptMessage(widget.secretText);
          } catch (e) {
            // Pikseller bozulmuşsa buraya düşer
            _displayText = "Hatalı Anahtar veya Bozuk Veri!";
          }
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
      if (_secondsRemaining <= 0) {
        _handleClose();
        return false;
      }
      return true;
    });
  }

  void _handleClose() {
    if (mounted) Navigator.pop(context);
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F0F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(_isDecoded ? "DESIFRE BASARILI" : "VERI COZULUYOR...",
          style: const TextStyle(color: Color(0xFFADCFD0), fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFADCFD0), width: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _displayText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Courier', color: Colors.greenAccent, fontSize: 18),
            ),
          ),
          if (_isDecoded) Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Text("Imha süresi: ${_secondsRemaining}s", style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _handleClose,
          child: const Text("ANLADIM", style: TextStyle(color: Color(0xFFADCFD0))),
        ),
      ],
    );
  }
}