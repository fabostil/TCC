class VoiceSessionContextHolder {
  String? _currentProjectId;
  String? _currentUserId;

  String? get currentProjectId => _currentProjectId;
  String? get currentUserId => _currentUserId;

  void updateActiveContext({String? projectId, String? userId}) {
    _currentProjectId = projectId;
    _currentUserId = userId;
  }
}
