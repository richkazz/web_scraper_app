import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(WebScraperApp());
}

class WebScraperApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Scraper',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: WebScraperHomePage(),
    );
  }
}

class WebScraperHomePage extends StatefulWidget {
  @override
  _WebScraperHomePageState createState() => _WebScraperHomePageState();
}

class _WebScraperHomePageState extends State<WebScraperHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _extractedText = '';
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _fetchAndExtractText() async {
    // Reset previous state
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _extractedText = '';
    });

    try {
      // Validate URL
      if (_urlController.text.isEmpty) {
        throw Exception('Please enter a URL');
      }

      // Fetch the webpage
      final response = await http.get(Uri.parse(_urlController.text));

      if (response.statusCode == 200) {
        var split = response.body.split('<br>');
        split = split.sublist(1, split.length - 2)
          ..removeWhere((element) => element.trim().isEmpty)
          ..removeWhere((element) =>
              element.trim().startsWith('<div') ||
              element.trim().startsWith('<img'));

        final builder = StringBuffer();
        for (var element in split) {
          builder.writeAll([element.trim().substring(13), '\n']);
        }

        setState(() {
          _extractedText = builder.toString();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load webpage');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_extractedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _extractedText));

      // Show a snackbar to confirm copying
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Scraper'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
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
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAndExtractText,
              child: const Text('Fetch and Extract'),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage.isNotEmpty)
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              )
            else if (_extractedText.isNotEmpty) ...[
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
          ],
        ),
      ),
    );
  }
}
