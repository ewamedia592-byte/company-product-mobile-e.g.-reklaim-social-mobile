class MessageFormatter {
  static String formatMessage(String text) {
    String formatted = text;
    
    formatted = formatted.replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*'),
      (match) => '**${match.group(1)}**'
    );
    
    return formatted;
  }

  static bool containsEmoji(String text) {
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])'
    );
    return emojiRegex.hasMatch(text);
  }
}