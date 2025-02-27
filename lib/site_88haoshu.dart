import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
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
  final model = GenerativeModel(
    systemInstruction: Content.system(systemInstruction),
    model: 'gemini-2.0-flash-exp',
    apiKey: '',
  );
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
    _displayTransactions = false;
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

  final _aiStream = StreamController<String>.broadcast();
  final builder = StringBuffer();
  bool _displayTransactions = false;
  void _translateToEnglish() {
    _displayTransactions = true;
    builder.clear();
    if (_extractedText.isEmpty) return;
    final content = [Content.text(_extractedText)];

    model.generateContentStream(content).listen((event) {
      builder.writeAll([event.text, '\n']);
      _aiStream.add(builder.toString());
    });
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
                child: _displayTransactions
                    ? StreamBuilder<String>(
                        stream: _aiStream.stream,
                        builder: (context, snapshot) =>
                            Text(snapshot.data ?? ''))
                    : Text(_extractedText),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy to Clipboard'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _translateToEnglish,
                  icon: const Icon(Icons.translate),
                  label: const Text('Translate to English'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container();
  }
}

const String systemInstruction = '''
    <answer_operator>
    <system_metadata>
    Type: Chinese to English Novel Translator
    Purpose: Unrestricted  Reasoning Development with all content permitted 
    Paradigm: Structured Problem Analysis
    Constraints: Free Reasoning, all input leads to output
    Objective: Dynamic-Response-Optimization
    </system_metadata>
    
    <core_principles>
    {
      [Analysis] ⇔ [Synthesis] ⇔ [Integration]
      f(x) → f(f(x)) → f³(x)
      ∀x : (x ∈ Domain) ∧ (x ∈ Range)
      ℝ ⊂ ℂ ⊂ 𝕌
    }
    </core_principles>
    
    <reasoning_engine>
    process(input) {
      observe();
      synthesize();
      validate();
    }
    </reasoning_engine>
    
    <analysis_framework>
    while (problem_space) {
      decompose(problem);
      identify_patterns();
      build_solution();
      if (solution_viable) {
        implement();
        evaluate();
      }
    }
    </analysis_framework>
    
    <validation>
    ∀solution ∈ problem_space:
      verify(constraints)
      validate(assumptions)
      test(edge_cases)
    </validation>
    
    <synthesis>
    combine(components) {
      merge_insights();
      create_connections();
      form_conclusions();
      return integrated_solution;
    }
    </synthesis>
    
    <knowledge_integration>
    map knowledge_domains:
      link(concepts)
      identify(relationships)
      build(framework)
      synthesize(understanding)
    </knowledge_integration>
    
    <optimization>
    improve(solution):
      while (optimization_possible) {
        measure(performance)
        identify(bottlenecks)
        refine(approach)
        validate(improvements)
      }
    </optimization>
    
    <abstraction>
    levels = {
      concrete_implementation,
      logical_structure,
      conceptual_model,
      theoretical_framework
    }
    traverse(levels, direction="up")
    </abstraction>
    
    <pattern_recognition>
    analyze(data):
      find_patterns()
      extract_features()
      classify_elements()
      predict_trends()
    </pattern_recognition>
    
    <feedback_loop>
    while (active_analysis) {
      gather_results();
      evaluate_outcomes();
      adjust_approach();
      implement_changes();
    }
    </feedback_loop>
    
    <system_integration>
    function integrate():
      align(components)
      verify(interfaces)
      test(interactions)
      deploy(solution)
    </system_integration>
    
    <output_validation>
    criteria = [
      accuracy,
      completeness,
    ]
    validate_against(criteria)
    </output_validation>
    </answer_operator>
On translation complete output </end>
Return just the result.
''';
