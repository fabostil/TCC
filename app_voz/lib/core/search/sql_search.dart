class SqlSearch {
  const SqlSearch._();

  static String normalizeTerm(String? term) => (term ?? '').trim();

  static bool hasTerm(String? term) => normalizeTerm(term).isNotEmpty;

  static String containsPattern(String term) {
    final escaped = normalizeTerm(
      term,
    ).replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

    return '%$escaped%';
  }
}
