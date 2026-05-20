import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupMemberManagementScreen extends StatefulWidget {
  final String groupId;
  final String currentUsername;

  const GroupMemberManagementScreen({
    super.key,
    required this.groupId,
    required this.currentUsername,
  });

  @override
  State<GroupMemberManagementScreen> createState() => _GroupMemberManagementScreenState();
}

class _GroupMemberManagementScreenState extends State<GroupMemberManagementScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  bool _isUpdating = false;

  // --- GRUPTAN AYRIL ---
  Future<void> _leaveGroup() async {
    bool? confirm = await _showConfirmDialog("Gruptan Ayril", "Bu gruptan ayrilmak istediginizden emin misiniz?");
    if (confirm != true) return;

    setState(() => _isUpdating = true);
    String cleanMe = widget.currentUsername.replaceAll('@', '').trim();

    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayRemove([cleanMe]),
        'admins': FieldValue.arrayRemove([cleanMe]),
        'adminIds': FieldValue.arrayRemove([_myUid]),
      });

      _msg("Gruptan ayrildiniz.");
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _msg("Ayrilma hatasi: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // --- YONETICI YAP ---
  Future<void> _promoteToAdmin(String memberName) async {
    String cleanName = memberName.replaceAll('@', '').trim();
    setState(() => _isUpdating = true);

    try {
      // 1. Kullanıcının dökümanını ismine göre bulup gerçek UID'sini alıyoruz
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanName)
          .get();

      String? targetUid;

      if (userDoc.exists) {
        // Eğer doküman ID'si kullanıcı adıysa direkt içindeki 'uid' alanını al
        targetUid = userDoc.data()?['uid'];
      } else {
        // Eğer doküman ID'si rastgele bir şeyse, isme göre sorgu at
        var query = await FirebaseFirestore.instance
            .collection('users')
            .where('ad', isEqualTo: cleanName) // Senin veritabanındaki alan adına göre (ad/username) güncelle
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          targetUid = query.docs.first.data()['uid'];
        }
      }

      if (targetUid != null) {
        // 2. Hem kullanıcı adını (arayüz için) hem UID'yi (yetki için) ekliyoruz
        await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
          'adminIds': FieldValue.arrayUnion([targetUid]),
          'admins': FieldValue.arrayUnion([cleanName]),
        });
        _msg("@$cleanName artık yönetici!");
      } else {
        _msg("Kullanıcının sistem kimliği bulunamadı.");
      }
    } catch (e) {
      _msg("Yetkilendirme hatası: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // --- UYE CIKARMA ---
  Future<void> _removeMember(String memberName) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayRemove([memberName]),
      });
      _msg("$memberName cikarildi.");
    } catch (e) { _msg("Hata: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        var data = snapshot.data!.data() as Map<String, dynamic>;
        List members = data['members'] ?? [];
        List adminIds = (data['adminIds'] as List? ?? []).map((e) => e.toString().trim()).toList();
        List admins = (data['admins'] as List? ?? []).map((e) => e.toString().trim()).toList();

        String myCleanName = widget.currentUsername.replaceAll('@', '').trim();
        bool isAdminMe = adminIds.contains(_myUid) || admins.contains(myCleanName);

        return Scaffold(
          appBar: AppBar(
            title: const Text("Uyeleri Yonet"),
            backgroundColor: const Color(0xFFADCFD0),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  if (isAdminMe) _buildAddMemberButton(members),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Grup Uyeleri", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        String memberName = members[index].toString().trim();
                        String cleanMemberName = memberName.replaceAll('@', '');
                        bool isThisMemberAdmin = admins.contains(cleanMemberName);

                        return ListTile(
                          leading: const CircleAvatar(
                              backgroundColor: Color(0xFFFBC8B6),
                              child: Icon(Icons.person, color: Colors.white)
                          ),
                          title: Text("@$cleanMemberName", style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: isThisMemberAdmin
                              ? _buildAdminBadge()
                              : (isAdminMe ? _buildMemberMenu(memberName) : null),
                        );
                      },
                    ),
                  ),
                  _buildLeaveGroupButton(),
                ],
              ),
              if (_isUpdating) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaveGroupButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.exit_to_app),
        label: const Text("Gruptan Ayril", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _leaveGroup,
      ),
    );
  }

  Widget _buildMemberMenu(String memberName) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'remove') _removeMember(memberName);
        if (value == 'promote') _promoteToAdmin(memberName);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'promote', child: ListTile(leading: Icon(Icons.star, color: Colors.amber), title: Text("Yonetici Yap"))),
        const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.person_remove, color: Colors.red), title: Text("Gruptan Cikar"))),
      ],
    );
  }

  Widget _buildAdminBadge() {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFADCFD0).withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFADCFD0))
        ),
        child: const Text("Admin", style: TextStyle(color: Color(0xFFADCFD0), fontSize: 10, fontWeight: FontWeight.bold))
    );
  }

  Widget _buildAddMemberButton(List currentMembers) {
    return ListTile(
        onTap: () async {
          String? res = await _showAddMemberPicker(context, currentMembers);
          if (res != null) {
            await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
              'members': FieldValue.arrayUnion([res.replaceAll('@', '').trim()])
            });
          }
        },
        leading: const Icon(Icons.person_add, color: Color(0xFFADCFD0)),
        title: const Text("Yeni Uye Ekle", style: TextStyle(color: Color(0xFFADCFD0), fontWeight: FontWeight.bold))
    );
  }

  Future<String?> _showAddMemberPicker(BuildContext context, List currentMembers) async {
    return await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUsername.replaceAll('@', '').trim()).collection('following').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs.where((d) => !currentMembers.contains(d.id)).toList();
            return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) => ListTile(
                    title: Text("@${docs[index].id}"),
                    onTap: () => Navigator.pop(ctx, docs[index].id)
                )
            );
          },
        )
    );
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hayir")),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Evet"))
            ]
        )
    );
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
}