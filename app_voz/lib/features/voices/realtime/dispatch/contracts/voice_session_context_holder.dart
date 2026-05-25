class VoiceSessionContextHolder {
  String? _currentProjectId;
  String? _currentUserId;
  String? _activeSessionToken;

  String? get currentProjectId => _currentProjectId;
  String? get currentUserId => _currentUserId;
  String? get activeSessionToken => _activeSessionToken;

  void updateActiveContext({
    String? projectId,
    String? userId,
    String? sessionToken,
  }) {
    _currentProjectId = projectId;
    _currentUserId = userId;
    _activeSessionToken = sessionToken;
  }

  void clearActiveContext() {
    _currentProjectId = null;
    _currentUserId = null;
    _activeSessionToken = null;
  }
}
