import 'package:flutter/material.dart';
import 'ai_service.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    {"role": "ai", "text": "Merhaba! Ben Cryptic AI. Sana nasıl yardımcı olabilirim?"}
  ];
  bool _isLoading = false;

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    String userMsg = _controller.text.trim();
    setState(() {
      _messages.add({"role": "user", "text": userMsg});
      _isLoading = true;
    });
    _controller.clear();

    String response = await AIService.getResponse(userMsg);

    setState(() {
      _messages.add({"role": "ai", "text": response});
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cryptic AI"),
        backgroundColor: const Color(0xFFADCFD0),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                bool isAI = _messages[i]["role"] == "ai";
                return Align(
                  alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAI ? Colors.grey[200] : const Color(0xFFFBC8B6),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(_messages[i]["text"]!, style: TextStyle(color: isAI ? Colors.black87 : Colors.white)),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Color(0xFFADCFD0)),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: "AI'ya bir şeyler sor...", border: InputBorder.none))),
        IconButton(icon: const Icon(Icons.send, color: Color(0xFFADCFD0)), onPressed: _sendMessage),
      ]),
    );
  }
}