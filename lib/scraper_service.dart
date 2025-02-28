import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';

class SavedNovel {
  final String title;
  final String url;
  final DateTime lastVisited;

  SavedNovel({
    required this.title,
    required this.url,
    required this.lastVisited,
  });

  // Convert to Map for SharedPreferences storage
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'url': url,
      'lastVisited': lastVisited.millisecondsSinceEpoch,
    };
  }

  // Create from Map for SharedPreferences retrieval
  factory SavedNovel.fromMap(Map<String, dynamic> map) {
    return SavedNovel(
      title: map['title'],
      url: map['url'],
      lastVisited: DateTime.fromMillisecondsSinceEpoch(map['lastVisited']),
    );
  }

  // For encoding to SharedPreferences
  String toJson() {
    return '${title}:::${url}:::${lastVisited.millisecondsSinceEpoch}';
  }

  // For decoding from SharedPreferences
  factory SavedNovel.fromJson(String json) {
    final parts = json.split(':::');
    if (parts.length >= 3) {
      return SavedNovel(
        title: parts[0],
        url: parts[1],
        lastVisited: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[2])),
      );
    } else {
      // Fallback if format is incorrect
      return SavedNovel(
        title: 'Unknown Title',
        url: parts.length >= 2 ? parts[1] : '',
        lastVisited: DateTime.now(),
      );
    }
  }
}

class ScraperService extends ChangeNotifier {
  final int pageIndex;
  final TextEditingController urlController = TextEditingController();
  final GenerativeModel _generativeModel;
  final StreamController<String> aiStreamController =
      StreamController<String>.broadcast();
  final StringBuffer translationBuffer = StringBuffer();

  late SharedPreferences _prefs;
  late String _urlKey;
  late String _contentKey;
  late String _historyKey;
  late String _savedNovelsKey;

  String extractedContent = '';
  bool isLoading = false;
  bool isTranslating = false;
  String errorMessage = '';
  List<String> contentHistory = [];
  List<Content> history = [];
  bool displayTransactions = false;
  List<SavedNovel> savedNovels = [];
  String currentNovelTitle = '';

  ScraperService({
    required this.pageIndex,
    required String systemInstruction,
    String model = 'gemini-2.0-flash-exp',
    String apiKey = '',
  }) : _generativeModel = GenerativeModel(
          systemInstruction: Content.system(systemInstruction),
          model: model,
          apiKey: apiKey,
        ) {
    _urlKey = 'url_key$pageIndex';
    _contentKey = 'content_key$pageIndex';
    _historyKey = 'history_key$pageIndex';
    _savedNovelsKey = 'saved_novels_key';
  }

  Future<void> initializePreferences() async {
    _prefs = await SharedPreferences.getInstance();
    await loadSavedData();
    await loadSavedNovels();
  }

  Future<void> loadSavedData() async {
    final savedUrl = _prefs.getString(_urlKey);
    urlController.text = savedUrl ?? '';

    extractedContent = _prefs.getString(_contentKey) ?? '';

    contentHistory = _prefs.getStringList(_historyKey) ?? [];
    if (contentHistory.isEmpty) {
      contentHistory = history
          .map((content) => content.parts.first is TextPart
              ? (content.parts.first as TextPart).text
              : '')
          .toList();
    } else {
      history = List.generate(
        contentHistory.length,
        (index) => index % 2 != 0
            ? Content.model([TextPart(contentHistory[index])])
            : Content.text(contentHistory[index]),
      );
    }
    notifyListeners();
  }

  // Save novel methods
  Future<void> loadSavedNovels() async {
    final savedNovelsList = _prefs.getStringList(_savedNovelsKey) ?? [];
    savedNovels = savedNovelsList
        .map((novelJson) => SavedNovel.fromJson(novelJson))
        .toList();
    savedNovels.sort((a, b) => b.lastVisited.compareTo(a.lastVisited));
    notifyListeners();
  }

  Future<void> saveCurrentNovel() async {
    if (urlController.text.isEmpty) return;

    // Try to extract a title from the content or use the URL as fallback
    String title = currentNovelTitle.isNotEmpty
        ? currentNovelTitle
        : _extractTitleFromContent() ?? 'Novel ${savedNovels.length + 1}';

    final novel = SavedNovel(
      title: title,
      url: urlController.text,
      lastVisited: DateTime.now(),
    );

    // Check if novel with same URL already exists
    final existingIndex = savedNovels.indexWhere((n) => n.url == novel.url);
    if (existingIndex >= 0) {
      // Update existing entry with new timestamp
      savedNovels[existingIndex] = SavedNovel(
          title: novel.title, url: novel.url, lastVisited: DateTime.now());
    } else {
      // Add new novel
      savedNovels.add(novel);
    }

    await saveSavedNovelsList();
    notifyListeners();
  }

  Future<void> deleteNovel(String url) async {
    savedNovels.removeWhere((novel) => novel.url == url);
    await saveSavedNovelsList();
    notifyListeners();
  }

  Future<void> saveSavedNovelsList() async {
    final novelJsonList = savedNovels.map((novel) => novel.toJson()).toList();
    await _prefs.setStringList(_savedNovelsKey, novelJsonList);
  }

  void loadNovel(String url) {
    urlController.text = url;
    fetchAndExtractContent();

    // Update the last visited timestamp
    final index = savedNovels.indexWhere((novel) => novel.url == url);
    if (index >= 0) {
      final novel = savedNovels[index];
      savedNovels[index] = SavedNovel(
        title: novel.title,
        url: novel.url,
        lastVisited: DateTime.now(),
      );
      saveSavedNovelsList();
    }
  }

  // Helper for extracting title from content
  String? _extractTitleFromContent() {
    if (extractedContent.isEmpty) return null;

    // Try to get the first line which is often the title
    final lines = extractedContent.split('\n');
    if (lines.isNotEmpty && lines[0].trim().isNotEmpty) {
      return lines[0].trim();
    }
    return null;
  }

  void setCurrentNovelTitle(String title) {
    currentNovelTitle = title;
    notifyListeners();
  }

  Future<void> fetchAndExtractContent() async {
    if (urlController.text.isEmpty) {
      setError('Please enter a URL');
      return;
    }
    isTranslating = false;
    notifyListeners();
    setLoadingState(true);

    try {
      // Determine which site we're dealing with
      if (urlController.text.contains('88haoshu.com')) {
        await _fetch88HaoshuContent();
      } else if (urlController.text.contains('44xw.com')) {
        await _fetch44xwContent();
      } else {
        // Default to 44xw.com method if site isn't recognized
        await _fetch44xwContent();
      }

      // Save this novel in history after successful fetch
      await saveCurrentNovel();
    } catch (error) {
      setError(error.toString());
    } finally {
      setLoadingState(false);
    }
  }

  // Methods for 44xw.com
  Future<void> _fetch44xwContent() async {
    final response = await http.get(Uri.parse(urlController.text));
    if (response.statusCode == 200) {
      await _process44xwResponse(response.body);
    } else {
      throw Exception('Failed to load webpage');
    }
  }

  Future<void> _process44xwResponse(String responseBody) async {
    final document = parse(responseBody);
    final extractedText = _extract44xwContent(document, responseBody);
    final nextPageUrl = _extract44xwNextPageUrl(document);

    // Try to extract title
    final titleElement = document.querySelector('strong');
    if (titleElement != null && titleElement.text.isNotEmpty) {
      setCurrentNovelTitle(titleElement.text);
    }

    await updateContent(extractedText, nextPageUrl);
  }

  String _extract44xwContent(dynamic document, String responseBody) {
    final buffer = StringBuffer();
    final titleElement = document.querySelector('strong');
    final title = titleElement?.text ?? '';
    buffer.writeln(title);

    List<String> lines = responseBody.split('<br>');
    if (lines.length > 3) {
      lines = lines.sublist(1, lines.length - 2)
        ..removeWhere((line) =>
            line.trim().isEmpty ||
            line.trim().startsWith('<div') ||
            line.trim().startsWith('<img'));
    }

    for (var line in lines) {
      String trimmed = line.trim();
      if (trimmed.length > 13) {
        buffer.writeln(trimmed.substring(13));
      } else {
        buffer.writeln(trimmed);
      }
    }
    return buffer.toString();
  }

  String _extract44xwNextPageUrl(dynamic document) {
    final navElements = document.querySelectorAll('nav');
    if (navElements.isNotEmpty && navElements.first.children.length >= 3) {
      final thirdAnchor = navElements.first.children[2];
      final thirdAnchorHref = thirdAnchor.attributes['href'] ?? '';
      final lastSlashIndex = urlController.text.lastIndexOf('/');
      final baseUrl = lastSlashIndex != -1
          ? urlController.text.substring(0, lastSlashIndex)
          : urlController.text;
      return '$baseUrl/$thirdAnchorHref';
    }
    return urlController.text;
  }

  // Methods for 88haoshu.com
  Future<void> _fetch88HaoshuContent() async {
    displayTransactions = false;

    final builder = StringBuffer();
    for (int i = 0; i < 1; i++) {
      final response = await http.get(Uri.parse(urlController.text));
      if (response.statusCode == 200) {
        final (extractedText, nextPageUrl) =
            await _process88HaoshuResponse(response.body);
        builder.writeAll([extractedText, '\n']);
      } else {
        throw Exception('Failed to load webpage');
      }
    }

    await updateContent(builder.toString(), urlController.text);
  }

  Future<(String, String)> _process88HaoshuResponse(String responseBody) async {
    final document = parse(responseBody);
    final nextPageUrl = _extract88HaoshuNextPageUrl(document);

    // Try to extract title
    final titleElement = document.querySelector('article h1');
    if (titleElement != null && titleElement.text.isNotEmpty) {
      setCurrentNovelTitle(titleElement.text);
    }

    urlController.text = nextPageUrl;
    return (_extract88HaoshuText(document, responseBody), nextPageUrl);
  }

  String _extract88HaoshuText(dynamic document, String responseBody) {
    final builder = StringBuffer();
    final contentElement = document.querySelector('article');
    final content = contentElement?.text;

    builder.writeAll([content]);

    return builder.toString();
  }

  String _extract88HaoshuNextPageUrl(dynamic document) {
    final brElements = document.getElementById('next_url');
    if (brElements == null || !brElements.attributes.containsKey('href')) {
      return urlController.text; // Return current URL if next page not found
    }

    final thirdATagHref = brElements.attributes['href'] as String;
    final indexOfLastSlashForNext = thirdATagHref.lastIndexOf('/');
    final indexOfLastSlash = urlController.text.lastIndexOf('/');
    final baseUrl = urlController.text.substring(0, indexOfLastSlash);
    return '$baseUrl/${thirdATagHref.substring(indexOfLastSlashForNext + 1)}';
  }

  Future<void> updateContent(String content, String nextPageUrl) async {
    urlController.text = nextPageUrl;
    await _prefs.setString(_urlKey, nextPageUrl);

    extractedContent = content;
    await _prefs.setString(_contentKey, content);
    notifyListeners();
  }

  void setLoadingState(bool loading) {
    isLoading = loading;
    if (loading) {
      errorMessage = '';
      extractedContent = '';
    }
    notifyListeners();
  }

  void setError(String message) {
    errorMessage = message;
    isLoading = false;
    notifyListeners();
  }

  Future<void> translateContentToEnglish() async {
    if (extractedContent.isEmpty) return;

    isTranslating = true;
    notifyListeners();
    translationBuffer.clear();

    history = List.generate(
      contentHistory.length,
      (index) => index % 2 != 0
          ? Content.model([TextPart(contentHistory[index])])
          : Content.text(contentHistory[index]),
    );

    history.add(Content.text(extractedContent));

    _generativeModel.generateContentStream(history).listen((event) {
      translationBuffer.write('${event.text}\n');
      aiStreamController.add(translationBuffer.toString());
    }).onDone(() {
      history.add(Content.model([TextPart(translationBuffer.toString())]));
      if (history.length == 12) {
        history.removeAt(0);
        history.removeAt(0);
      }

      contentHistory = history
          .map((content) => content.parts.first is TextPart
              ? (content.parts.first as TextPart).text
              : '')
          .toList();

      unawaited(_prefs.setStringList(_historyKey, contentHistory));
    });
  }

  @override
  void dispose() {
    aiStreamController.close();
    urlController.dispose();
    super.dispose();
  }
}
