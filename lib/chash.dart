// ignore_for_file: non_constant_identifier_names

class CHash {
  static int adler32(String buf) {
    int s1 = 1;
    int s2 = 0;

    for (int n = 0; n < buf.length; n++) {
      s1 = (s1 + buf[n].codeUnitAt(0)) % 65521;
      s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
  }

  static int hash(String buf) {
    String salt = "sooltye";
    int result = adler32(buf + salt) & 0xffffffff;
    return result;
  }

  static int hash_with_seed(String input, int seed) {
    final d = "$input$seed";
    return hash(d);
  }
}
