import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';

class WebScraperHomePage88haoshu extends StatefulWidget {
  const WebScraperHomePage88haoshu({required this.currentIndex, super.key});
  final int currentIndex;
  @override
  _WebScraperHomePageState createState() => _WebScraperHomePageState();
}

class _WebScraperHomePageState extends State<WebScraperHomePage88haoshu> {
  final TextEditingController _urlController = TextEditingController();
  String _extractedText = '';
  bool _isLoading = false;
  String _errorMessage = '';
  late SharedPreferences prefs;

  static String urlKey = 'url_key';
  static String contentKey = 'content_key';

  @override
  void initState() {
    super.initState();
    urlKey = 'url_key${widget.currentIndex}';
    contentKey = 'content_key${widget.currentIndex}';
    _initiate();
  }

  Future<void> _initiate() async {
    prefs = await SharedPreferences.getInstance();
    _loadSavedData();
  }

  void _loadSavedData() {
    final url = prefs.getString(urlKey);
    _urlController.text = url ?? '';
    final content = prefs.getString(contentKey);
    setState(() {
      _extractedText = content ?? '';
    });
  }

  Future<void> _fetchAndExtractText() async {
    if (_urlController.text.isEmpty) {
      _setError('Please enter a URL');
      return;
    }

    _setLoadingState(true);

    try {
      final builder = StringBuffer();
      for (int i = 0; i < 2; i++) {
        final response = await http.get(Uri.parse(_urlController.text));
        if (response.statusCode == 200) {
          final (extractedText, nextPageUrl) =
              await _processResponse(response.body);
          builder.writeAll([extractedText, '\n']);
        } else {
          throw Exception('Failed to load webpage');
        }
      }
      await _updateStateWithExtractedData(
          builder.toString(), _urlController.text);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoadingState(false);
    }
  }

  Future<(String, String)> _processResponse(String responseBody) async {
    final document = parse(responseBody);
    final nextPageUrl = _extractNextPageUrl(document);
    _urlController.text = nextPageUrl;
    return (_extractText(document, responseBody), nextPageUrl);
  }

  String _extractText(document, String responseBody) {
    final builder = StringBuffer();
    final contentElement = document.querySelector('article');
    final content = contentElement?.text;

    builder.writeAll([content]);

    return builder.toString();
  }

  String _extractNextPageUrl(document) {
    final brElements = document.getElementById('next_url');
    final thirdATagHref = brElements.attributes['href'] as String;
    final indexOfLastSlashForNext = thirdATagHref.lastIndexOf('/');
    final indexOfLastSlash = _urlController.text.lastIndexOf('/');
    final baseUrl = _urlController.text.substring(0, indexOfLastSlash);
    return '$baseUrl/${thirdATagHref.substring(indexOfLastSlashForNext + 1)}';
  }

  Future<void> _updateStateWithExtractedData(
      String extractedText, String nextPageUrl) async {
    _urlController.text = nextPageUrl;
    await prefs.setString(urlKey, nextPageUrl);
    _extractedText = extractedText;
    await prefs.setString(contentKey, _extractedText);
  }

  void _setLoadingState(bool isLoading) {
    setState(() {
      _isLoading = isLoading;
      if (isLoading) {
        _errorMessage = '';
        _extractedText = '';
      }
    });
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  void _copyToClipboard() {
    if (_extractedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _extractedText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('88haoshu ${widget.currentIndex}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUrlTextField(),
            const SizedBox(height: 16),
            _buildFetchButton(),
            const SizedBox(height: 16),
            _buildContentDisplay(),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlTextField() {
    return TextField(
      controller: _urlController,
      decoration: InputDecoration(
        labelText: 'Enter URL',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => _urlController.clear(),
        ),
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildFetchButton() {
    return ElevatedButton(
      onPressed: _fetchAndExtractText,
      child: const Text('Fetch and Extract'),
    );
  }

  Widget _buildContentDisplay() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      return Text(
        _errorMessage,
        style: const TextStyle(color: Colors.red),
      );
    } else if (_extractedText.isNotEmpty) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Extracted Text:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_extractedText),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _copyToClipboard,
              icon: const Icon(Icons.copy),
              label: const Text('Copy to Clipboard'),
            ),
          ],
        ),
      );
    }
    return Container();
  }
}
