import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CodexLogBrowserApp());
}

class CodexLogBrowserApp extends StatelessWidget {
  const CodexLogBrowserApp({super.key});

  static const Color _macAccentBlue = Color(0xFF0A84FF);

  @override
  Widget build(BuildContext context) {
    final lightScheme = const ColorScheme.light(
      primary: _macAccentBlue,
      secondary: Color(0xFF5E5CE6),
      surface: Color(0xFFF2F2F7),
      surfaceContainerHighest: Color(0xFFE5E5EA),
      outline: Color(0xFF8E8E93),
    );
    final darkScheme = const ColorScheme.dark(
      primary: _macAccentBlue,
      secondary: Color(0xFF64D2FF),
      surface: Color(0xFF1C1C1E),
      surfaceContainerHighest: Color(0xFF2C2C2E),
      outline: Color(0xFF636366),
    );

    return MaterialApp(
      title: 'Codex Chat Log Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: lightScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: lightScheme.surface,
          foregroundColor: const Color(0xFF1C1C1E),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: darkScheme.surface,
          foregroundColor: const Color(0xFFF2F2F7),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const LogBrowserPage(),
    );
  }
}

enum MessageCategory {
  prompt,
  assistantResponse,
  assistantCommentary,
  assistantFinal,
  instruction,
  toolCall,
  toolOutput,
  reasoning,
  event,
  meta,
  state,
  unknown,
}

extension MessageCategoryLabel on MessageCategory {
  String get label {
    switch (this) {
      case MessageCategory.prompt:
        return 'Prompt';
      case MessageCategory.assistantResponse:
        return 'Assistant Response';
      case MessageCategory.assistantCommentary:
        return 'Assistant Commentary';
      case MessageCategory.assistantFinal:
        return 'Assistant Final';
      case MessageCategory.instruction:
        return 'Instruction';
      case MessageCategory.toolCall:
        return 'Tool Call';
      case MessageCategory.toolOutput:
        return 'Tool Output';
      case MessageCategory.reasoning:
        return 'Reasoning';
      case MessageCategory.event:
        return 'Event';
      case MessageCategory.meta:
        return 'Session Meta';
      case MessageCategory.state:
        return 'State';
      case MessageCategory.unknown:
        return 'Unknown';
    }
  }
}

class SessionLog {
  SessionLog({
    required this.sessionId,
    required this.filePath,
    required this.directoryInfoLabel,
    required this.messages,
    this.startedAt,
  });

  final String sessionId;
  final String filePath;
  final String directoryInfoLabel;
  final DateTime? startedAt;
  final List<LogEntry> messages;

  int get messageCount => messages.length;

  Map<MessageCategory, int> get categoryCounts {
    final counts = <MessageCategory, int>{};
    for (final entry in messages) {
      counts.update(entry.category, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

class LogEntry {
  LogEntry({
    required this.lineNo,
    required this.category,
    required this.sourceType,
    required this.preview,
    required this.raw,
    this.role,
    this.phase,
    this.timestamp,
    this.text,
    this.primaryText,
  });

  final int lineNo;
  final MessageCategory category;
  final String sourceType;
  final String preview;
  final Map<String, dynamic> raw;
  final String? role;
  final String? phase;
  final DateTime? timestamp;
  final String? text;
  final String? primaryText;
}

enum DetailViewMode {
  assistantResponse,
  promptMetadata,
  responseMetadata,
}

extension DetailViewModeLabel on DetailViewMode {
  String get label {
    switch (this) {
      case DetailViewMode.assistantResponse:
        return 'Assistant response';
      case DetailViewMode.promptMetadata:
        return 'Prompt metadata';
      case DetailViewMode.responseMetadata:
        return 'Response metadata';
    }
  }
}

class PromptItem {
  PromptItem({
    required this.key,
    required this.sessionId,
    required this.filePath,
    required this.fileLabel,
    required this.promptLineNo,
    required this.promptText,
    required this.promptEntry,
    required this.timestamp,
    this.responseText,
    this.responseEntry,
  });

  final String key;
  final String sessionId;
  final String filePath;
  final String fileLabel;
  final int promptLineNo;
  final String promptText;
  final LogEntry promptEntry;
  final DateTime? timestamp;
  final String? responseText;
  final LogEntry? responseEntry;
}

class LogBrowserPage extends StatefulWidget {
  const LogBrowserPage({super.key});

  @override
  State<LogBrowserPage> createState() => _LogBrowserPageState();
}

class _LogBrowserPageState extends State<LogBrowserPage> {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');
  static const String _lastFolderPrefKey = 'last_selected_sessions_dir';

  late final TextEditingController _pathController;
  late final TextEditingController _searchController;

  List<SessionLog> _sessions = const [];
  String? _selectedSessionId;
  bool _loading = false;
  String? _error;
  String _selectedFilePath = '__all__';
  String? _selectedPromptKey;
  DetailViewMode _detailViewMode = DetailViewMode.assistantResponse;
  bool _showAdvancedContext = false;
  String? _selectedEntryKey;
  final Set<String> _expandedPromptKeys = <String>{};

  late Set<MessageCategory> _visibleCategories;
  late Map<MessageCategory, bool> _autoExpand;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _visibleCategories = MessageCategory.values.toSet();
    _autoExpand = {
      MessageCategory.prompt: true,
      MessageCategory.assistantResponse: true,
      MessageCategory.assistantCommentary: false,
      MessageCategory.assistantFinal: true,
      MessageCategory.instruction: false,
      MessageCategory.toolCall: false,
      MessageCategory.toolOutput: false,
      MessageCategory.reasoning: false,
      MessageCategory.event: false,
      MessageCategory.meta: false,
      MessageCategory.state: false,
      MessageCategory.unknown: false,
    };
    _restorePathAndLoad();
  }

  Future<void> _restorePathAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_lastFolderPrefKey);
    final initialPath = (savedPath != null && savedPath.isNotEmpty)
        ? savedPath
        : _defaultSessionsPath();
    _pathController.text = initialPath;
    await _loadLogs();
  }

  Future<void> _persistSelectedPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFolderPrefKey, path);
  }

  String _defaultSessionsPath() {
    final home = Platform.environment['HOME'];
    final user = Platform.environment['USER'];

    if (home != null && home.isNotEmpty) {
      final normalizedHome = home.replaceAll('\\', '/');
      // macOS app launches can provide a container HOME; prefer real user home.
      if (normalizedHome.contains('/Library/Containers/') &&
          user != null &&
          user.isNotEmpty) {
        return '/Users/$user/.codex/sessions';
      }
      return '$home${Platform.pathSeparator}.codex${Platform.pathSeparator}sessions';
    }

    if (user != null && user.isNotEmpty) {
      return '/Users/$user/.codex/sessions';
    }

    return '${Directory.current.path}${Platform.pathSeparator}sessions';
  }

  @override
  void dispose() {
    _pathController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final rootPath = _pathController.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessions = await _parseSessions(rootPath);
      await _persistSelectedPath(rootPath);
      setState(() {
        _sessions = sessions;
        if (_sessions.isEmpty) {
          _selectedSessionId = null;
          _selectedPromptKey = null;
          _selectedEntryKey = null;
        } else if (_selectedSessionId == null ||
            !_sessions.any((s) => s.sessionId == _selectedSessionId)) {
          _selectedSessionId = _sessions.first.sessionId;
          final first = _sessions.first.messages;
          _selectedEntryKey = first.isEmpty ? null : _entryKey(_sessions.first.sessionId, first.first.lineNo);
        }
        _selectedPromptKey ??= _firstPromptKeyFromSessions(_sessions);
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  String? _firstPromptKeyFromSessions(List<SessionLog> sessions) {
    for (final session in sessions) {
      for (final message in session.messages) {
        if (message.category == MessageCategory.prompt) {
          return _promptKey(session.filePath, message.lineNo);
        }
      }
    }
    return null;
  }

  Future<void> _pickSessionsDirectory() async {
    try {
      final selectedPath = await getDirectoryPath(confirmButtonText: 'Use this folder');
      if (!mounted) {
        return;
      }
      if (selectedPath == null || selectedPath.isEmpty) {
        _showMessage('Folder picker canceled.');
        return;
      }

      _pathController.text = selectedPath;
      await _persistSelectedPath(selectedPath);
      _showMessage('Selected: $selectedPath');
      await _loadLogs();
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showMessage('Folder picker failed: $e');
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<List<SessionLog>> _parseSessions(String rootPath) async {
    final directory = Directory(rootPath);
    if (!directory.existsSync()) {
      throw Exception('Directory not found: $rootPath');
    }

    final files = await directory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));

    final sessions = <SessionLog>[];
    for (final file in files) {
      final parsed = await _parseFile(file, rootPath);
      sessions.add(parsed);
    }

    sessions.sort((a, b) {
      final aTime = a.startedAt;
      final bTime = b.startedAt;
      if (aTime == null && bTime == null) {
        return a.filePath.compareTo(b.filePath);
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      return bTime.compareTo(aTime);
    });

    return sessions;
  }

  Future<SessionLog> _parseFile(File file, String rootPath) async {
    var lineNo = 0;
    final messages = <LogEntry>[];
    String? sessionId;
    DateTime? startedAt;

    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      lineNo++;
      if (line.trim().isEmpty) {
        continue;
      }

      Map<String, dynamic> raw;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          raw = <String, dynamic>{'_raw': line, '_error': 'Root object is not a map'};
        } else {
          raw = decoded;
        }
      } catch (e) {
        raw = <String, dynamic>{'_raw': line, '_error': 'JSON parse error: $e'};
      }

      sessionId ??= _detectSessionId(raw) ?? file.uri.pathSegments.last;
      startedAt ??= _detectTimestamp(raw);

      messages.add(_toLogEntry(raw, lineNo));
    }

    return SessionLog(
      sessionId: sessionId ?? file.uri.pathSegments.last,
      filePath: file.path,
      directoryInfoLabel: _directoryInfoLabel(file.path, rootPath),
      startedAt: startedAt,
      messages: messages,
    );
  }

  String _directoryInfoLabel(String filePath, String rootPath) {
    final sep = Platform.pathSeparator;
    final normalizedRoot = rootPath.endsWith(sep) ? rootPath : '$rootPath$sep';
    var relative = filePath;
    if (filePath.startsWith(normalizedRoot)) {
      relative = filePath.substring(normalizedRoot.length);
    }

    final parts = relative.split(sep).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) {
      return 'No directory info';
    }

    final dirs = parts.sublist(0, parts.length - 1);
    if (dirs.length >= 3 &&
        RegExp(r'^\d{4}$').hasMatch(dirs[0]) &&
        RegExp(r'^\d{2}$').hasMatch(dirs[1]) &&
        RegExp(r'^\d{2}$').hasMatch(dirs[2])) {
      return '${dirs[0]}-${dirs[1]}-${dirs[2]}';
    }

    return dirs.join('/');
  }

  String? _detectSessionId(Map<String, dynamic> raw) {
    final payload = _asMap(raw['payload']);
    return _asString(payload?['id']) ?? _asString(raw['id']);
  }

  DateTime? _detectTimestamp(Map<String, dynamic> raw) {
    final candidates = <String?>[
      _asString(raw['timestamp']),
      _asString(_asMap(raw['payload'])?['timestamp']),
    ];
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      final parsed = DateTime.tryParse(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  LogEntry _toLogEntry(Map<String, dynamic> raw, int lineNo) {
    final topType = _asString(raw['type']) ?? _asString(raw['record_type']) ?? 'unknown';
    final payload = _asMap(raw['payload']);

    var sourceType = topType;
    var role = _asString(raw['role']);
    var phase = _asString(raw['phase']);
    var text = _extractText(raw);
    String? primaryText;

    MessageCategory category = MessageCategory.unknown;

    if (topType == 'session_meta') {
      category = MessageCategory.meta;
    } else if (topType == 'event_msg') {
      category = MessageCategory.event;
      sourceType = '$topType:${_asString(payload?['type']) ?? 'unknown'}';
      text = _extractText(payload);
    } else if (topType == 'response_item') {
      final pType = _asString(payload?['type']) ?? 'unknown';
      sourceType = '$topType:$pType';
      role = _asString(payload?['role']) ?? role;
      phase = _asString(payload?['phase']) ?? phase;
      text = _extractText(payload);
      category = _categoryFromResponsePayloadType(pType, role, phase);
    } else if (topType == 'message') {
      category = _categoryFromRole(role, phase);
    } else if (topType == 'reasoning') {
      category = MessageCategory.reasoning;
    } else if (topType == 'state' || _asString(raw['record_type']) == 'state') {
      category = MessageCategory.state;
    }

    final timestamp = _detectTimestamp(raw);
    primaryText = _extractPrimaryMessageText(topType, raw, payload) ?? text;
    final preview = _buildPreview(text, raw, sourceType);

    return LogEntry(
      lineNo: lineNo,
      category: category,
      sourceType: sourceType,
      preview: preview,
      raw: raw,
      role: role,
      phase: phase,
      timestamp: timestamp,
      text: text,
      primaryText: primaryText,
    );
  }

  MessageCategory _categoryFromResponsePayloadType(
    String payloadType,
    String? role,
    String? phase,
  ) {
    if (payloadType == 'message') {
      return _categoryFromRole(role, phase);
    }
    if (payloadType == 'function_call' || payloadType == 'custom_tool_call') {
      return MessageCategory.toolCall;
    }
    if (payloadType == 'function_call_output' || payloadType == 'custom_tool_call_output') {
      return MessageCategory.toolOutput;
    }
    if (payloadType == 'reasoning') {
      return MessageCategory.reasoning;
    }
    return MessageCategory.event;
  }

  MessageCategory _categoryFromRole(String? role, String? phase) {
    final normalizedRole = (role ?? '').toLowerCase();
    final normalizedPhase = (phase ?? '').toLowerCase();

    if (normalizedRole == 'user') {
      return MessageCategory.prompt;
    }
    if (normalizedRole == 'assistant') {
      if (normalizedPhase == 'commentary') {
        return MessageCategory.assistantCommentary;
      }
      if (normalizedPhase == 'final' || normalizedPhase == 'final_answer') {
        return MessageCategory.assistantFinal;
      }
      return MessageCategory.assistantResponse;
    }
    if (normalizedRole == 'developer' || normalizedRole == 'system') {
      return MessageCategory.instruction;
    }
    return MessageCategory.unknown;
  }

  String _buildPreview(String? text, Map<String, dynamic> raw, String sourceType) {
    final cleanText = (text ?? '').trim();
    if (cleanText.isNotEmpty) {
      if (cleanText.length <= 180) {
        return cleanText;
      }
      return '${cleanText.substring(0, 180)}...';
    }

    final payloadType = _asString(_asMap(raw['payload'])?['type']);
    final fallback = payloadType ?? sourceType;
    return '[${fallback.isEmpty ? 'record' : fallback}]';
  }

  String? _extractPrimaryMessageText(
    String topType,
    Map<String, dynamic> raw,
    Map<String, dynamic>? payload,
  ) {
    if (topType == 'message') {
      final text = _extractTextFromContentArray(raw['content']);
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }

    if (topType == 'response_item' && payload != null) {
      if (_asString(payload['type']) == 'message') {
        final text = _extractTextFromContentArray(payload['content']);
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
      if (_asString(payload['type']) == 'function_call') {
        final name = _asString(payload['name']) ?? 'tool';
        final args = _asString(payload['arguments']) ?? '';
        return 'Tool call: $name${args.isEmpty ? '' : '\n$args'}';
      }
      if (_asString(payload['type']) == 'custom_tool_call') {
        final name = _asString(payload['name']) ?? 'tool';
        return 'Tool call: $name';
      }
    }

    if (topType == 'event_msg' && payload != null) {
      final maybe = _asString(payload['message']) ?? _asString(payload['text']);
      if (maybe != null && maybe.trim().isNotEmpty) {
        return maybe.trim();
      }
    }

    return null;
  }

  String? _extractTextFromContentArray(dynamic content) {
    if (content is! List) {
      return null;
    }
    final out = <String>[];
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final itemType = _asString(item['type']) ?? '';
      final text = _asString(item['text']) ?? _asString(item['input_text']) ?? _asString(item['output_text']);
      if (text != null && text.trim().isNotEmpty) {
        out.add(text.trim());
        continue;
      }
      if (itemType == 'input_image') {
        out.add('[image]');
      }
    }
    if (out.isEmpty) {
      return null;
    }
    return out.join('\n');
  }

  String? _extractText(dynamic value) {
    final out = StringBuffer();

    void walk(dynamic node) {
      if (node == null) {
        return;
      }

      if (node is String) {
        if (node.trim().isNotEmpty) {
          if (out.isNotEmpty) {
            out.write('\n');
          }
          out.write(node.trim());
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }

      if (node is Map) {
        for (final key in ['text', 'input_text', 'output_text', 'message']) {
          walk(node[key]);
        }
        walk(node['summary']);
        walk(node['content']);
        return;
      }
    }

    walk(value);
    return out.isEmpty ? null : out.toString();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    return null;
  }

  String? _asString(dynamic value) {
    if (value == null) {
      return null;
    }
    return '$value';
  }

  String _entryKey(String sessionId, int lineNo) => '$sessionId:$lineNo';

  String _promptKey(String filePath, int lineNo) => '$filePath::$lineNo';

  List<PromptItem> get _allPrompts {
    final prompts = <PromptItem>[];
    for (final session in _sessions) {
      for (var i = 0; i < session.messages.length; i++) {
        final entry = session.messages[i];
        if (entry.category != MessageCategory.prompt) {
          continue;
        }

        final rawPrompt = (entry.primaryText ?? entry.text ?? '').trim();
        final promptText = _extractUserRequestText(rawPrompt);
        if (promptText.isEmpty) {
          continue;
        }

        final responseEntry = _findAssistantResponse(session.messages, i);
        final responseText = responseEntry == null
            ? null
            : _extractAssistantReadableText(responseEntry.primaryText ?? responseEntry.text ?? '');

        prompts.add(
          PromptItem(
            key: _promptKey(session.filePath, entry.lineNo),
            sessionId: session.sessionId,
            filePath: session.filePath,
            fileLabel: '${session.directoryInfoLabel} • ${_basename(session.filePath)}',
            promptLineNo: entry.lineNo,
            promptText: promptText,
            promptEntry: entry,
            responseEntry: responseEntry,
            responseText: responseText,
            timestamp: entry.timestamp ?? session.startedAt,
          ),
        );
      }
    }

    prompts.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) {
        return a.filePath.compareTo(b.filePath);
      }
      if (at == null) {
        return 1;
      }
      if (bt == null) {
        return -1;
      }
      return bt.compareTo(at);
    });
    return prompts;
  }

  List<String> get _availableFiles {
    final out = _sessions.map((s) => s.filePath).toSet().toList()..sort();
    return out;
  }

  List<PromptItem> get _filteredPrompts {
    final needle = _normalizeForSearch(_searchController.text);
    return _allPrompts.where((prompt) {
      if (_selectedFilePath != '__all__' && prompt.filePath != _selectedFilePath) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      final haystack = _normalizeForSearch(
        '${prompt.promptText}\n${prompt.responseText ?? ''}\n${prompt.filePath}',
      );
      return haystack.contains(needle);
    }).toList();
  }

  String _normalizeForSearch(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  PromptItem? _resolveSelectedPrompt(List<PromptItem> prompts) {
    if (prompts.isEmpty) {
      return null;
    }
    final key = _selectedPromptKey;
    if (key != null) {
      for (final prompt in prompts) {
        if (prompt.key == key) {
          return prompt;
        }
      }
    }
    return prompts.first;
  }

  String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }

  String _extractUserRequestText(String text) {
    final normalized = text.replaceAll(r'\n', '\n').trim();
    final marker = RegExp(r'##\s*My request for Codex:\s*', caseSensitive: false);
    final match = marker.firstMatch(normalized);
    if (match == null) {
      return normalized;
    }
    return normalized.substring(match.end).trim();
  }

  LogEntry? _findAssistantResponse(List<LogEntry> entries, int promptIndex) {
    LogEntry? commentary;
    LogEntry? response;
    LogEntry? finalResponse;
    for (var i = promptIndex + 1; i < entries.length; i++) {
      final next = entries[i];
      if (next.category == MessageCategory.prompt) {
        break;
      }
      if (next.category == MessageCategory.assistantCommentary) {
        commentary ??= next;
      } else if (next.category == MessageCategory.assistantResponse) {
        response ??= next;
      } else if (next.category == MessageCategory.assistantFinal) {
        finalResponse ??= next;
      }
    }
    return finalResponse ?? response ?? commentary;
  }

  String _extractAssistantReadableText(String text) {
    return text.replaceAll(r'\n', '\n').trim();
  }

  SessionLog? get _selectedSession {
    final id = _selectedSessionId;
    if (id == null) {
      return null;
    }
    for (final session in _sessions) {
      if (session.sessionId == id) {
        return session;
      }
    }
    return null;
  }

  List<LogEntry> get _filteredEntries {
    final session = _selectedSession;
    if (session == null) {
      return const [];
    }

    final needle = _normalizeForSearch(_searchController.text);

    return session.messages.where((entry) {
      if (!_visibleCategories.contains(entry.category)) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }

      final haystack = _normalizeForSearch([
        entry.primaryText ?? '',
        entry.preview,
        entry.sourceType,
        entry.role ?? '',
        entry.phase ?? '',
        entry.text ?? '',
        _prettyJson.convert(entry.raw),
      ].join('\n'));

      return haystack.contains(needle);
    }).toList();
  }

  LogEntry? _resolveSelectedEntry(SessionLog? session, List<LogEntry> filteredEntries) {
    if (session == null || filteredEntries.isEmpty) {
      return null;
    }
    final key = _selectedEntryKey;
    if (key != null) {
      for (final entry in filteredEntries) {
        if (_entryKey(session.sessionId, entry.lineNo) == key) {
          return entry;
        }
      }
    }
    return filteredEntries.first;
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _filteredPrompts;
    final selectedPrompt = _resolveSelectedPrompt(prompts);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex Chat Log Browser'),
      ),
      body: Column(
        children: [
          _buildTopControls(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildPromptLayout(prompts, selectedPrompt),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    final files = _availableFiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 520,
            child: TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Sessions Directory',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _loading ? null : _loadLogs,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload'),
          ),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    await _pickSessionsDirectory();
                  },
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose Folder'),
          ),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    await _persistSelectedPath(_pathController.text.trim());
                    await _loadLogs();
                  },
            icon: const Icon(Icons.check),
            label: const Text('Use Path'),
          ),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search prompts',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            width: 420,
            child: DropdownButtonFormField<String>(
              key: ValueKey('file-filter-$_selectedFilePath-${files.length}'),
              initialValue: _selectedFilePath,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'File filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '__all__',
                  child: Text('All log files'),
                ),
                ...files.map((path) {
                  return DropdownMenuItem<String>(
                    value: path,
                    child: Text(_basename(path), overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedFilePath = value;
                  _selectedPromptKey = null;
                });
              },
            ),
          ),
          Text('Prompts: ${_filteredPrompts.length}/${_allPrompts.length}'),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayout(
    SessionLog? selectedSession,
    List<LogEntry> filteredEntries,
    LogEntry? selectedEntry,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth < 1280 ? 1280.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            height: constraints.maxHeight,
            child: Row(
              children: [
                SizedBox(width: 360, child: _buildSessionList(selectedSession)),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 3,
                  child: _buildMessageListArea(selectedSession, filteredEntries, selectedEntry),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: _buildMessageDetailPanel(selectedSession, selectedEntry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionList(SessionLog? selectedSession) {
    if (_sessions.isEmpty) {
      return const Center(child: Text('No .jsonl files found in selected directory.'));
    }

    return ListView.builder(
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final selected = session.sessionId == _selectedSessionId;

        return Card(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            onTap: () {
              setState(() {
                _selectedSessionId = session.sessionId;
                _selectedEntryKey =
                    session.messages.isEmpty ? null : _entryKey(session.sessionId, session.messages.first.lineNo);
              });
            },
            title: Text(
              session.sessionId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${session.directoryInfoLabel}\n${session.startedAt?.toIso8601String() ?? 'no timestamp'}\n${session.filePath}\n${session.messageCount} records',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageListArea(
    SessionLog? selectedSession,
    List<LogEntry> filteredEntries,
    LogEntry? selectedEntry,
  ) {
    if (selectedSession == null) {
      return const Center(child: Text('Select a chat session.'));
    }

    final categoryCounts = selectedSession.categoryCounts;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selected chat: ${selectedSession.sessionId}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Directory label: ${selectedSession.directoryInfoLabel}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: MessageCategory.values.map((category) {
                  final count = categoryCounts[category] ?? 0;
                  final enabled = _visibleCategories.contains(category);
                  return FilterChip(
                    selected: enabled,
                    label: Text('${category.label} ($count)'),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _visibleCategories.add(category);
                        } else {
                          _visibleCategories.remove(category);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: MessageCategory.values
                    .where((category) => (categoryCounts[category] ?? 0) > 0)
                    .map((category) {
                  final expanded = _autoExpand[category] ?? false;
                  return FilterChip(
                    selected: expanded,
                    label: Text('Auto-expand ${category.label}'),
                    onSelected: (selected) {
                      setState(() {
                        _autoExpand[category] = selected;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show advanced context by default'),
                value: _showAdvancedContext,
                onChanged: (value) {
                  setState(() {
                    _showAdvancedContext = value;
                  });
                },
              ),
              const SizedBox(height: 6),
              Text('Visible records: ${filteredEntries.length} / ${selectedSession.messageCount}'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: filteredEntries.length,
            itemBuilder: (context, index) {
              final entry = filteredEntries[index];
              final isSelected = selectedEntry != null &&
                  _entryKey(selectedSession.sessionId, entry.lineNo) ==
                      _entryKey(selectedSession.sessionId, selectedEntry.lineNo);
              return _buildEntryCard(selectedSession.sessionId, entry, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntryCard(String sessionId, LogEntry entry, bool isSelected) {
    final palette = _colorForCategory(entry.category, context);
    final prominentText = (entry.primaryText ?? entry.preview).trim();

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      color: isSelected ? Theme.of(context).colorScheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedEntryKey = _entryKey(sessionId, entry.lineNo);
          });
        },
        child: ExpansionTile(
          key: ValueKey(_entryKey(sessionId, entry.lineNo)),
          initiallyExpanded: _showAdvancedContext || (_autoExpand[entry.category] ?? false),
          onExpansionChanged: (_) {
            setState(() {
              _selectedEntryKey = _entryKey(sessionId, entry.lineNo);
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          title: Text(
            prominentText.isEmpty ? '[no message text]' : prominentText,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${entry.category.label}  •  ${entry.sourceType}  •  line ${entry.lineNo}  •  role=${entry.role ?? '-'}  •  phase=${entry.phase ?? '-'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: entry.timestamp == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    entry.timestamp!.toIso8601String(),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              color: palette.withValues(alpha: 0.07),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional context',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _prettyJson.convert(entry.raw),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageDetailPanel(SessionLog? session, LogEntry? selectedEntry) {
    if (session == null) {
      return const Center(child: Text('Select a chat session.'));
    }
    if (selectedEntry == null) {
      return const Center(child: Text('Select a message to view details.'));
    }

    final prominentText = (selectedEntry.primaryText ?? selectedEntry.preview).trim();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message detail',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${selectedEntry.category.label}  •  line ${selectedEntry.lineNo}  •  role=${selectedEntry.role ?? '-'}  •  phase=${selectedEntry.phase ?? '-'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  prominentText.isEmpty ? '[no message text]' : prominentText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                if (_showAdvancedContext) ...[
                  const Text('Raw record'),
                  const SizedBox(height: 6),
                  SelectableText(
                    _prettyJson.convert(selectedEntry.raw),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptLayout(List<PromptItem> prompts, PromptItem? selectedPrompt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth < 1320 ? 1320.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            height: constraints.maxHeight,
            child: Row(
              children: [
                SizedBox(width: 320, child: _buildFileColumn()),
                const VerticalDivider(width: 1),
                Expanded(flex: 3, child: _buildPromptListColumn(prompts, selectedPrompt)),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: _buildPromptDetailPanel(selectedPrompt)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileColumn() {
    final files = _availableFiles;
    if (files.isEmpty) {
      return const Center(child: Text('No files loaded.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Text(
            'Files (${files.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: files.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final selected = _selectedFilePath == '__all__';
                return ListTile(
                  selected: selected,
                  title: const Text('All log files'),
                  subtitle: Text('${_allPrompts.length} prompts'),
                  onTap: () {
                    setState(() {
                      _selectedFilePath = '__all__';
                      _selectedPromptKey = null;
                    });
                  },
                );
              }
              final path = files[index - 1];
              final selected = _selectedFilePath == path;
              final count = _allPrompts.where((p) => p.filePath == path).length;
              return ListTile(
                selected: selected,
                title: Text(_basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('$count prompts\n$path', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  setState(() {
                    _selectedFilePath = path;
                    _selectedPromptKey = null;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromptListColumn(List<PromptItem> prompts, PromptItem? selectedPrompt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            'Prompt feed (${prompts.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: prompts.isEmpty
              ? const Center(child: Text('No prompts for current filter.'))
              : ListView.builder(
                  itemCount: prompts.length,
                  itemBuilder: (context, index) {
                    final prompt = prompts[index];
                    final isSelected = selectedPrompt != null && selectedPrompt.key == prompt.key;
                    return _buildPromptListItem(prompt, isSelected);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPromptListItem(PromptItem prompt, bool isSelected) {
    final isExpanded = _expandedPromptKeys.contains(prompt.key);
    final previewText = _promptPreviewText(prompt.promptText);
    final responseText = (prompt.responseText == null || prompt.responseText!.isEmpty)
        ? 'No assistant response found for this prompt.'
        : prompt.responseText!;
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      color: isSelected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ExpansionTile(
        key: ValueKey(prompt.key),
        initiallyExpanded: isExpanded || isSelected,
        onExpansionChanged: (_) {
          setState(() {
            _selectedPromptKey = prompt.key;
            if (_expandedPromptKeys.contains(prompt.key)) {
              _expandedPromptKeys.remove(prompt.key);
            } else {
              _expandedPromptKeys.add(prompt.key);
            }
          });
        },
        title: Text(
          previewText,
          softWrap: true,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          maxLines: isExpanded ? null : 6,
          overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${prompt.fileLabel}  •  line ${prompt.promptLineNo}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              responseText,
              softWrap: true,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _promptPreviewText(String rawText) {
    final input = rawText.replaceAll(r'\n', '\n');
    final lines = input.split('\n');
    final out = <String>[];
    var inFence = false;

    final logLike = RegExp(r'^\s*(\d{4}-\d{2}-\d{2}|INFO\b|WARN\b|ERROR\b|\[[A-Z ]+\])');
    final codeLike = RegExp(r'^\s*(import |from |class |def |function |const |let |var |#include|public |private |<\?php)');
    final htmlLike = RegExp(r'^\s*</?[a-zA-Z][^>]*>\s*$');

    for (final original in lines) {
      final line = original.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) {
          out.add('');
        }
        continue;
      }
      if (trimmed.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        continue;
      }
      if (htmlLike.hasMatch(trimmed)) {
        continue;
      }
      if (logLike.hasMatch(trimmed) || codeLike.hasMatch(trimmed)) {
        continue;
      }
      if (trimmed.contains('{') && trimmed.contains('}') && trimmed.length > 40) {
        continue;
      }
      out.add(trimmed);
    }

    final compact = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return compact.isEmpty ? '[prompt text hidden - expand to view]' : compact;
  }

  Widget _buildPromptDetailPanel(PromptItem? selectedPrompt) {
    if (selectedPrompt == null) {
      return const Center(child: Text('Select a prompt.'));
    }

    final responseText = (selectedPrompt.responseText == null || selectedPrompt.responseText!.isEmpty)
        ? 'No assistant response found for this prompt.'
        : selectedPrompt.responseText!;
    final promptRows = _tableRowsFromDynamic(selectedPrompt.promptEntry.raw);
    final responseRows = _tableRowsFromDynamic(selectedPrompt.responseEntry?.raw ?? const <String, dynamic>{});

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Prompt detail',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                DropdownButton<DetailViewMode>(
                  value: _detailViewMode,
                  items: DetailViewMode.values.map((mode) {
                    return DropdownMenuItem(value: mode, child: Text(mode.label));
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _detailViewMode = value;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  selectedPrompt.promptText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (_detailViewMode == DetailViewMode.assistantResponse) ...[
                  Text(responseText),
                ] else if (_detailViewMode == DetailViewMode.promptMetadata) ...[
                  _buildStructuredTable(promptRows),
                ] else ...[
                  _buildStructuredTable(responseRows),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredTable(List<MapEntry<String, String>> rows) {
    if (rows.isEmpty) {
      return const Text('No metadata available.');
    }
    return Table(
      border: TableBorder.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(2.8),
      },
      children: [
        const TableRow(
          children: [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Field', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Value', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        ...rows.map((row) {
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(row.key),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(row.value),
              ),
            ],
          );
        }),
      ],
    );
  }

  List<MapEntry<String, String>> _tableRowsFromDynamic(dynamic value, [String prefix = '']) {
    final rows = <MapEntry<String, String>>[];

    void walk(dynamic node, String path) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = '$path${path.isEmpty ? '' : '.'}${entry.key}';
          walk(entry.value, key);
        }
        return;
      }
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], '$path[$i]');
        }
        return;
      }
      rows.add(MapEntry(path.isEmpty ? '(value)' : path, node == null ? '' : '$node'));
    }

    walk(value, prefix);
    return rows;
  }

  Color _colorForCategory(MessageCategory category, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (category) {
      case MessageCategory.prompt:
        return Colors.blue;
      case MessageCategory.assistantResponse:
        return Colors.green;
      case MessageCategory.assistantCommentary:
        return Colors.teal;
      case MessageCategory.assistantFinal:
        return Colors.indigo;
      case MessageCategory.instruction:
        return Colors.deepPurple;
      case MessageCategory.toolCall:
        return Colors.orange;
      case MessageCategory.toolOutput:
        return Colors.deepOrange;
      case MessageCategory.reasoning:
        return Colors.pink;
      case MessageCategory.event:
        return Colors.brown;
      case MessageCategory.meta:
        return scheme.primary;
      case MessageCategory.state:
        return scheme.secondary;
      case MessageCategory.unknown:
        return scheme.outline;
    }
  }
}
