import 'package:flutter/material.dart';
import 'dart:convert'; // For jsonEncode
import 'package:flutter/services.dart'; // For Clipboard
import 'package:google_generative_ai/google_generative_ai.dart';

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  _TranslationScreenState createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final TextEditingController _chineseController = TextEditingController();
  final TextEditingController _englishController = TextEditingController();
  final List<Map<String, String>> _translations = [];
  final model = GenerativeModel(
    model: 'gemini-2.0-flash-exp',
    apiKey: '',
  );

  void _addTranslation() {
    final chineseText = _chineseController.text;
    final englishText = _englishController.text;

    if (chineseText.isNotEmpty && englishText.isNotEmpty) {
      setState(() {
        _translations.add({'chinese': chineseText, 'english': englishText});
        _chineseController.clear();
        _englishController.clear();
      });
    }
  }

  void _copyTranslationsToClipboard() {
    final jsonString = jsonEncode(_translations);
    Clipboard.setData(ClipboardData(text: jsonString));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Translations copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Translation Input'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _chineseController,
              decoration: InputDecoration(labelText: 'Chinese'),
            ),
            TextField(
              controller: _englishController,
              decoration: InputDecoration(labelText: 'English'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addTranslation,
              child: Text('Add to List'),
            ),
            ElevatedButton(
              onPressed: _copyTranslationsToClipboard,
              child: Text('Copy to Clipboard'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _translations.length,
                itemBuilder: (context, index) {
                  final translation = _translations[index];
                  return ListTile(
                    title: Text(translation['chinese']!),
                    subtitle: Text(translation['english']!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
