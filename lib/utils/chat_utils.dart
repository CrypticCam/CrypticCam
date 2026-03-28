class ChatUtils {
  /// İki kullanıcı adını alfabetik sıraya göre birleştirip eşsiz ID üretir
  static String getChatRoomId(String user1, String user2) {
    // Küçük harfe çevirip listeye alıyoruz
    List<String> users = [user1.toLowerCase(), user2.toLowerCase()];
    // Alfabetik sıralıyoruz (Örn: "ayse" ve "rana" -> "ayse_rana")
    users.sort();
    return "${users[0]}_${users[1]}";
  }
}