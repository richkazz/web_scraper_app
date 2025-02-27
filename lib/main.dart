import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_scraper_app/site_88haoshu.dart';

void main() {
  runApp(const ScraperApp());
}

class ScraperApp extends StatelessWidget {
  const ScraperApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Scraper',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Tab> _tabs = const [
    Tab(text: 'Star Odyssey'),
    Tab(text: 'Page 2'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Scraper'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ScraperPage(pageIndex: 1),
          ScraperPage(pageIndex: 2),
        ],
      ),
    );
  }
}

class ScraperPage extends StatefulWidget {
  final int pageIndex;
  const ScraperPage({Key? key, required this.pageIndex}) : super(key: key);

  @override
  _ScraperPageState createState() => _ScraperPageState();
}

class _ScraperPageState extends State<ScraperPage> {
  final TextEditingController _urlController = TextEditingController();
  String _extractedContent = '';
  bool _isLoading = false;
  String _errorMessage = '';
  late SharedPreferences _prefs;

  late String _urlKey;
  late String _contentKey;
  late String _historyKey;
  List<String> _contentHistory = [];
  final GenerativeModel _generativeModel = GenerativeModel(
    systemInstruction: Content.system(systemInstruction),
    model: 'gemini-2.0-flash-exp',
    apiKey: '',
  );

  final StreamController<String> _aiStreamController =
      StreamController<String>.broadcast();
  final StringBuffer _translationBuffer = StringBuffer();
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _urlKey = 'url_key${widget.pageIndex}';
    _contentKey = 'content_key${widget.pageIndex}';
    _historyKey = 'history_key${widget.pageIndex}';

    _initializePreferences();
  }

  Future<void> _initializePreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedData();
  }

  void _loadSavedData() {
    final savedUrl = _prefs.getString(_urlKey);
    _urlController.text = savedUrl ?? '';
    final savedContent = _prefs.getString(_contentKey);
    setState(() {
      _extractedContent = savedContent ?? '';
    });
    _contentHistory = _prefs.getStringList(_historyKey) ?? [];
    _contentHistory = _contentHistory.isEmpty
        ? history
            .map((content) => content.parts.first is TextPart
                ? (content.parts.first as TextPart).text
                : '')
            .toList()
        : _contentHistory;
  }

  Future<void> _fetchAndExtractContent() async {
    if (_urlController.text.isEmpty) {
      _setError('Please enter a URL');
      return;
    }
    _setLoadingState(true);

    try {
      final response = await http.get(Uri.parse(_urlController.text));
      if (response.statusCode == 200) {
        await _processResponse(response.body);
      } else {
        throw Exception('Failed to load webpage');
      }
    } catch (error) {
      _setError(error.toString());
    } finally {
      _setLoadingState(false);
    }
  }

  Future<void> _processResponse(String responseBody) async {
    final document = parse(responseBody);
    final extractedContent = _extractContent(document, responseBody);
    final nextPageUrl = _extractNextPageUrl(document);

    await _updateContent(extractedContent, nextPageUrl);
  }

  String _extractContent(document, String responseBody) {
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

  String _extractNextPageUrl(document) {
    final navElements = document.querySelectorAll('nav');
    if (navElements.isNotEmpty && navElements.first.children.length >= 3) {
      final thirdAnchor = navElements.first.children[2];
      final thirdAnchorHref = thirdAnchor.attributes['href'] ?? '';
      final lastSlashIndex = _urlController.text.lastIndexOf('/');
      final baseUrl = lastSlashIndex != -1
          ? _urlController.text.substring(0, lastSlashIndex)
          : _urlController.text;
      return '$baseUrl/$thirdAnchorHref';
    }
    return _urlController.text;
  }

  Future<void> _updateContent(String content, String nextPageUrl) async {
    _urlController.text = nextPageUrl;
    await _prefs.setString(_urlKey, nextPageUrl);
    setState(() {
      _extractedContent = content;
    });
    await _prefs.setString(_contentKey, content);
  }

  void _setLoadingState(bool isLoading) {
    setState(() {
      _isLoading = isLoading;
      if (isLoading) {
        _errorMessage = '';
        _extractedContent = '';
      }
    });
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  void _copyContentToClipboard() {
    if (_extractedContent.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _extractedContent));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content copied to clipboard!')),
      );
    }
  }

  void _translateContentToEnglish() {
    history = List.generate(
        _contentHistory.length,
        (index) => index % 2 != 0
            ? Content.model([TextPart(_contentHistory[index])])
            : Content.text(_contentHistory[index]));
    if (_extractedContent.isEmpty) return;
    setState(() {
      _isTranslating = true;
    });
    _translationBuffer.clear();
    history.add(Content.text(_extractedContent));
    _generativeModel.generateContentStream(history).listen((event) {
      _translationBuffer.write('${event.text}\n');
      _aiStreamController.add(_translationBuffer.toString());
    }).onDone(() {
      history.add(Content.model([TextPart(_translationBuffer.toString())]));
      if (history.length == 12) {
        history.removeAt(0);
        history.removeAt(0);
      }
      _contentHistory = history
          .map((content) => content.parts.first is TextPart
              ? (content.parts.first as TextPart).text
              : '')
          .toList();
      unawaited(_prefs.setStringList(_historyKey, _contentHistory));
    });
  }

  @override
  void dispose() {
    _aiStreamController.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildUrlInputField(),
          const SizedBox(height: 16),
          _buildActionButtons(),
          const SizedBox(height: 16),
          Expanded(child: _buildContentDisplay()),
        ],
      ),
    );
  }

  Widget _buildUrlInputField() {
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

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: IconButton(
            onPressed: _fetchAndExtractContent,
            icon: const Icon(Icons.navigate_next),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: IconButton(
            onPressed: _copyContentToClipboard,
            icon: const Icon(Icons.copy),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: IconButton(
            onPressed: _translateContentToEnglish,
            icon: const Icon(Icons.translate),
          ),
        ),
      ],
    );
  }

  Widget _buildContentDisplay() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
      );
    } else if (_extractedContent.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Extracted Content:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: _isTranslating
                  ? StreamBuilder<String>(
                      stream: _aiStreamController.stream,
                      builder: (context, snapshot) {
                        return Text(snapshot.data ?? '');
                      },
                    )
                  : Text(_extractedContent),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

List<Content> history = [
  Content('user', [
    TextPart('''
“你们的意识，无法吞噬？”

    黑无神苦涩：“绝对不可能吞噬，若非自愿，陆主你也不可能得到她的意识，没有她的意识，我。”

    他也不知道是恨白无神还是恨自己倒霉，如果不是白无神的意识，他是可以逃走的，但当初在意识宇宙，他能不死也多亏了白无神。


X

    到底怎么回事？

    白无神为什么对陆隐那么在乎？

    他永远也想不通人类的情感。

    正如白无神自己都想不通，为什么会被明嫣的情感所累，导致现在的局面。

    陆隐放下手。

    黑无神松口气：“多谢陆主不杀之恩。”

    陆隐居高临下看着黑无神：“谁说，不杀？”

    黑无神一愣，还没反应过来，眼前，一颗星球爆裂，天星功伴随着生物极限的力量将黑无神身体在一刹那撕成碎片，原地，意识轰然扩散，发出黑无神怨毒憎恨的声音：“陆隐，你不得好死，终有一天，你会死在灵化宇宙和意识宇宙手下，你不得好死，不得好死。”

    陆隐身后，意识席卷而出，朝着黑无神的意识冲去。

    黑无神意识疯狂逃窜，想逃离。

    但根本不可能，意识星球降临，如旋涡，将黑无神的意识不断吞噬。

    黑无神骇然：“意识宇宙生命的意识不应该被吞噬，你却例外，陆隐，你是意识宇宙最大的敌人，比灵化宇宙的威胁更大，陆隐，你总有一天会被意识摧毁，你会死，不得好死--”

    黑无神声音逐渐削弱，他的意识被意识星球吞噬。

    属于意识的生命，思维，在意识被吞噬的刹那烟消云散，最终只剩下属于陆隐的最纯粹的意识。

    杀黑无神，不仅仅因为立场不同，也因为陆隐想尝试一下，看能不能抢夺意识宇宙生命的意识。

    结果来看，可以。

    白无神的奉献给了陆隐一个可能，一个无限增强意识的可能。

    陆隐可以通过抢夺意识宇宙生命来增强意识，对于意识宇宙来说，他才是最大的敌人，因为灵化宇宙只能摧毁，而无法吞噬。

    当黑无神完全消散，陆隐屹立星空，看着意识星球。

    这颗星球变大了不少。

    真可怕啊，他的意识现在膨胀了很多很多，完全属于始境层次的意识，不，应该说，渡苦厄层次，放在意识星球就是星空级。

    本人没达到渡苦厄层次，甚至连始境都不是，意识却提前一步达到了。

    这才是捷径。

    意识宇宙可以给自己无限的意识，灵化宇宙可以给自己无限的序列规则。

    这两个宇宙如今仿佛都成了自己的补品。

    回望，唯一真神不断被始祖所伤，距离死亡越来越近，他根本没有反抗能力了。

    另一边，青王被陆源一拳打落，手中还提着炎刚，周边，虫子几乎都被消灭干净。

    这种层次的战场，虫子再多也没用。

    炎刚咳血，尽管被青王保护着，稍微一点点余威也足以杀死他。

    他右腿没了，刚刚被余威擦中，鲜血不断流淌，痛入骨髓。

    他后悔，极度后悔，应该把虫巢上交的。

    心有所感，他看向远方，这一刻，陆隐也在看着他。

    时间仿佛倒退百年，那时候，他们都在地球，那时候，炎刚带着优越感，俯视陆隐，将陆隐当做土著，一个可以被轻易碾死的土著。

    百年岁月匆匆而过，炎刚怎么也不可能想到百年后会以这种方式相见。

    他看着陆隐，眼中尽是哀求，他想活下去，不想死。

    陆隐也看着炎刚，地球上发生的一幕幕闪过，百年如此，千年呢？万年呢？十万年，百万年，亿万年后，这宇宙星空会怎么样？

    他终究会成为传说，离别，会经历的太多。

    砰

    青王被红颜梅比斯砸中脑袋，一口血吐在炎刚脸上，炙热的血液将炎刚脸皮都融化，炎刚哀嚎：“杀了我，快杀了我。”

    他不是不怕死，而是这种痛苦让他宁愿死。

    青王随手拍碎了炎刚的脑袋，此人已经没有价值，连唯一真神都要结束了。

    眼前，陆源，红颜梅比斯冲来。

    青王目光一松：“我要买自己一条命。”

    陆源与红颜梅比斯下意识停手，将他围住。

    “买命？”

    青王转头看向陆隐，缓缓开口：“我知道你们敌视我们，但我们从头到尾都没打算与你们为敌，虫子的繁衍是本能，如果你们不愿意，我可以让虫子全部死亡，虫巢也可以交给你。”

    陆隐挑眉：“你还真想活下去。”

    融入过毛球青仙体内，陆隐知道青仙最重要的就是活下去，不仅仅是本能，更是仙主的命令。

    仙主将虫巢打入天元宇宙的一刻，下过的唯一命令就是活下去。

    青仙忠实执行仙主的命令。

    青王恭敬：“还请陆主给我一个活下去的机会，我愿为陆主效力，终生侍奉。”

    “我有秘密，可以换自己一条命。”

    陆隐好笑：“你的秘密对我没什么价值，不止你一个青仙想活下去，杀了他。”

    超大巨人之祖自后方出现，他右臂粉碎，左手抓向青王，要抹杀青王。

    陆隐没工夫跟青王废话，始祖那边就要结束，他打算对天狗出手，这只狗真能撑，居然还不死，不愧是人类文明之前的生物。

    青王躲避超大巨人之祖的攻击，急忙喊道：“以陆主的能力，不管青仙多厉害都逃不掉，陆主能得到其它青仙很正常，但我这个秘密的价值超越了所有青仙，陆主若愿意，我可以告诉你，还请陆主给我一个机会。”

    陆隐没理他，一掌打向天狗。

    青王大喊：“唯一真神不在这。”

    陆隐动作一顿，惊愕看向青王：“你说什么？”

    忽然的，青王体内，神力沸腾，他面色大变，望向唯一真神。

    唯一真神眼底冰寒彻骨。

    他没想到自己的秘密竟被一只虫子看穿，而刚刚他也看到青王杀死炎刚的一幕，没想到这么久以来，他居然被骗了。

    这只虫子根本不会被炎刚控制，不仅如此，他竟还发现了自己的秘密。

    青王压抑神力，低吼：“陆主救我，唯一真神不在这。”

    陆隐急忙出现在青王身旁，一手按住他要吸收神力。

    但却晚了。

    神力自青王体内爆开，不仅粉碎了青王，也将陆隐震伤。

    陆隐倒退数步，望向远处的唯一真神。

    始祖惊异：“什么意思？永恒，你做了什么？”

    唯一真神摇头：“没想到一只虫子居然能看穿我，你们对虫巢的忌惮是正确的，小心，这虫子很有可能反客为主，威胁比灵化宇宙还大。”

    始祖盯着唯一真神，他没有看错，唯一真神就在这，不可能是假的，可他现在说的话是什么意思？承认了那只虫子说的？

    陆隐望着唯一真神，思虑急转，脱口而出：“天赐的灵种。”

    唯一真神赞叹：“聪明，陆隐，天元宇宙就给你了，我在这败给了你一次，我们灵化宇宙见。”

X


    说完，他看向始祖：“太初，打到现在，你没发现我的神力根本不存在吗？”

    始祖盯着唯一真神，他确实没发现，唯一真神即便不使用神力，实力也绝顶强大，以至于他们都忽略了。

    唯一真神的神力不在这具身体里，他本人随同天赐的灵种，在不知道什么时候去了灵化宇宙。

    可他怎么去？

    梦桑。

    陆隐握拳，是梦桑，可他怎么做到的？梦桑自己知不知道。


    从头到尾，唯一真神都带着黑无神他们逃避辰祖的追踪，但事实上不管是忘墟神还是辰祖，都是唯一真神转移所有人注意力的诱饵罢了，他让陆隐等人以为与忘墟神在一起，事实上也确实在一起，否则无法发现辰祖的追踪。

    但他本身以神力带着天赐的浊宝灵种，不知道什么时候找到了梦桑，在梦桑自己都察觉不到的情况下，跟随梦桑离开了天元宇宙，去了灵化宇宙。

    除了梦桑，没有别人了，从灵化宇宙侵入天元宇宙后，唯有梦桑建立跳板并离开，至于梦桑是否知道，陆隐不确定。

    按理说应该知道，但以唯一真神的实力，不让梦桑察觉未必不可能。

    可眼前这个唯一真神实力绝对没错，他又是怎么将自身神力等转移？又为什么要转移？摆脱六道轮回界？

    是了，只有这个办法才能摆脱六道轮回界，并且离开天元宇宙，在所有人不知情的前提下在灵化宇宙重新修炼。

    也不算是重新修炼，他的一身神力也跟着走了，实力会提升的非常快。

    如果不是青王的提醒，没有人会知道这件事，陆隐盯着唯一真神，他确定了，梦桑绝对不知道，因为这一刻跟随他离开的唯一真神很脆弱，这种状态下，唯一真神决不可能让任何人知晓。

    唯一真神深深看向陆隐：“还记得我曾经对你说过的话吗？陆道主，我们，灵化宇宙见了。”

    说完，自凝空戒取出虫巢：“这是临别送给你们的礼物。”

    虫巢在他力量加持下，朝着虚空不断闪烁，如夜空的星朝远方而去。
    ''')
  ]),
  Content('model', [
    TextPart('''
Chapter 3385: Not Here
“Conscients... can’t be devoured?”

Blackless God bitterly answered, “It’s absolutely impossible to devour us! If it wasn’t voluntary, Lord Lu, you could have never taken her consciousness. Without her consciousness, I...”

The Skygod had no idea if he should curse Whiteless God or simply curse his own bad luck. If not for Whiteless God’s consciousness, Blackless God could have escaped. However, he had only survived the Consciousness Megaverse because of her.

Just what had happened?

Why had Whiteless God cared so much about Lu Yin?

Blackless God was incapable of understanding human emotions.

This was no different from how Whiteless God herself had never been able to understand why she had been burdened by Ming Yan’s feelings. That confusion had led to the current situation.

Lu Yin lowered his hand.

Blackless God let out a sigh of relief. “Thank you, Lord Lu, for sparing me.”

Lu Yin looked down at Blackless God. “When did I say that I wouldn’t kill you?”

Blackless God froze, unable to react. At that moment, a star exploded, and the power of the Cosmic Art combined with physical strength that had reached the biological limits of the megaverse, and Blackless God’s body was torn to pieces. From the remains, his consciousness erupted, and he cursed Lu Yin, hating the human. “Lu Yin, you will die a terrible death! The day will come when you are killed by the Spirit Nidus or the Consciousness Megaverse! Your death will be miserable! Miserable...”

Lu Yin’s consciousness surged from behind him, shooting towards Blackless God.


The consciousness frantically tried to flee, but escape was impossible. The star of consciousness descended, acting like a vortex as it devoured Blackless God’s consciousness.

The Skygod was horrified. “The Consciousness Megaverse’s conscients can’t be devoured! You’re the only one, Lu Yin. You are my Consciousness Megaverse’s greatest enemy! You’re an even greater threat than the Spirit Nidus! Lu Yin, one day, you will be destroyed by us! You will die... and your death will be terrible...”

Blackless God’s voice grew weaker as his consciousness was devoured and pulled into Lu Yin’s star.

The vitality and thoughts of the consciousness were erased the moment it was fully consumed. Ultimately, only the purest consciousness remained with Lu Yin.

He had not killed Blackless God just because they had been enemies, but also because Lu Yin had wanted to test if he could devour a conscient from the Consciousness Megaverse.

The results were clear: he could.

Whiteless God’s sacrifice had granted Lu Yin a possibility; he could strengthen his own consciousness without limits by devouring others’ consciousness.

Lu Yin could improve his consciousness by devouring the Consciousness Megaverse’s conscients. To that megaverse, he would be their greatest enemy. This was because the Spirit Nidus could only destroy the conscients, not devour them.

Once Blackless God was completely gone, Lu Yin stood alone in outer space, staring at his star of consciousness.

It had grown much larger.

It was absolutely terrifying. His consciousness had been greatly strengthened, and it was clearly at the Universe level now. No, he should call it the Dukkhan level, as that was comparable to the Universe-level strength of Lu Yin’s star of consciousness.

Lu Yin was not himself a Dukkhan, or even an Ortuser, and yet his consciousness had already surpassed his own cultivation.

He had taken a shortcut.

The Consciousness Megaverse could give him endless amounts of consciousness, while the Spirit Nidus could give him endless sequence particles.

It seemed that the two megaverses had transformed into supplements for Lu Yin’s growth.

He turned and looked back, seeing that the Origin Progenitor was slowly wearing down True God. The man was being pushed closer to death, and he could do nothing to stop it.

In another direction, Lu Yuan’s fist knocked Verdant King down. The Verdant Sage was still holding Yan Gang in a hand, but almost all of the endless swarm of insects had been eliminated.

On a battlefield of this level, no matter how many insects appeared, they would all be useless.

Yan Gang coughed up blood. While he was being protected by Verdant King, even the smallest of shockwaves from this battlefield was more than enough to kill Yan Gang.

His right leg was gone, removed by a shockwave. He had not stopped bleeding, and the pain was bone-deep.

He deeply regretted his actions and not turning in his Nest.

He felt something in his heart, and he turned to look into the distance. At the moment, Lu Yin was staring straight at Yan Gang.

The man felt as though he was thrown a hundred years into the past. At that time, they had both been on Earth, and Yan Gang had looked down on Lu Yin, feeling arrogant and superior. He had treated Lu Yin as a native of Earth who could be easily crushed.

A hundred years had passed in the blink of an eye, and Yan Gang could have never imagined encountering Lu Yin in such a way after so long.

As the man stared at Lu Yin, he begged with his eyes. Yan Gant wanted to live, not die.

Lu Yin was also staring at Yan Gang and reliving his moments from Earth. A hundred years had passed so quickly... What would happen after a thousand years? 10,000? 100,000? 1 million, or even 1 billion years? What would become of his universe and megaverse?

Lu Yin was destined to become a legend, but that meant saying far too many farewells.

Boom!

Hongyan Mavis struck Verdant King’s head, and he spat out a mouthful of blood that splattered onto Yan Gang's face. The scorching blood melted the man’s skin, and he shrieked, "Kill me! Please, kill me!"

Yan Gang was not afraid, but was rather simply suffering such agony that he preferred to die.

Verdant King casually smashed Yan Gang's skull. The man no longer held any value, and even True God was about to meet his end.

In front of the insect, both Lu Yuan and Hongyan Mavis charged.

The tension left Verdant King’s face. "I want to buy my life."

Lu Yuan and Hongyan Mavis instinctively stopped attacking, though they surrounded the Verdant Sage.

"Buy your life?"

Verdant King turned to face Lu Yin and spoke slowly, "I know that you oppose us, but we never intended to be your enemies. We insects only reproduce on an instinctual level, and if you don’t want the other insects, I can have them all die. I can give you my Nest."

Lu Yin arched a brow. "You really want to live."

By Possessing the green furball Verdant Sage, Lu Yin understood that nothing mattered more to the Verdant Sages than survival. This was not merely their natural instincts, but rather the Immortal Lord’s command.

When the Immortal Lord had sent the Nests into the Tianyuan Megaverse, the only command that they had been given was to survive.

And the Verdant Sages were faithfully carrying out the Immortal Lord’s command.

Verdant King bowed respectfully. "Please, Lord Lu, grant me a chance to live. I am willing to serve you for the rest of my life.

"I know a secret, and it is worth my life."

Lu Yin laughed. "Your secrets are worthless to me. You’re not the only Verdant Sage who wants to survive. Kill him."

The ancestor of the super giants appeared behind the Verdant Sage. While the giant’s right arm had been destroyed, he was still able to use his left hand to crush Verdant King.

Lu Yin had no time to waste in talking with Verdant King. Things were about to end with the Origin Progenitor. Lu Yin planned to deal with Skydog next, who had been holding on remarkably well and was still not dead. It made sense that the dog was a creature older than humanity itself.

Verdant King dodged the giant’s attack and quickly shouted, "Lord Lu, your abilities mean that no Verdant Sage can escape, and it is only to be expected that you have obtained other Verdant Sages. However, my secret is worth more than all of them! If you are willing, I can tell you! Please, Lord Lu, give me this chance!"

Lu Yin ignored the insect and instead attacked Skydog.

Verdant King shouted, "True God is not here!"

Lu Yin froze in shock, and turned to look at Verdant King. "What was that?"

Suddenly, divine energy surged from within Verdant King. His expression changed drastically, and he looked over at True God.

The man’s eyes were unbelievably cold.

He had never expected his secret to have been discovered by an insect. On top of that, True God had seen when Verdant King had killed Yan Gang. True God could not believe that he had been deceived the entire time.

The bug had never been under Yan Gang's control. Not only that, but the Verdant Sage had even discovered True God’s secret.

Verdant King suppressed the divine energy and growled, "Lord Lu, save me! True God is not here!"

Lu Yin instantly appeared beside Verdant King, a hand stretched out to absorb the divine energy.

It was already too late.

The divine energy exploded from inside Verdant King, shattering his body and also injuring Lu Yin.

Lu Yin staggered a few steps back and turned to look at the distant True God.

The Origin Progenitor exclaimed, "What does that mean? Yong Heng, what have you done?"

True God shook his head. "I never thought that I would be seen through by a mere bug. You are right to be cautious of the Nests. Be careful—these bugs might very well turn the tables and end up being an even greater threat than the Spirit Nidus."

The Origin Progenitor continued to stare at True God. He was certain that True God was present. The Origin Progenitor was not fighting a fake, so what did those words mean? Was True God admitting that the bug had spoken the truth?

Lu Yin stared at True God as his mind raced. Suddenly he blurted, "Tian Ci’s spirit seed!"

True God was impressed. "Clever, Lu Yin. I will leave this Tianyuan Megaverse to you. I've lost to you here once. We’ll meet again in the Spirit Nidus."

The man then turned his attention back to the Origin Progenitor. "Tai Chu, have you still not realized it? My divine energy is not here."

The Origin Progenitor stared at True God. He really had failed to notice that True God had never used his divine energy during the fight. The man was incredibly powerful even without that, and his strength had led to his lack of divine energy being overlooked.

There was no divine energy in True God’s body. He, by using Tian Ci’s spirit seed, was somehow on his way to the Spirit Nidus, though no one knew when True God had left.

How had he even left?

Meng Sang.


Lu Yin clenched his fists. Meng Sang was behind this, but how had he done it? Was Meng Sang even aware of the truth?

All along, True God had been leading Blackless God and the others around as they had avoided Progenitor Chen's pursuit. However, the truth of the matter was that both Forgotten Ruins God and Progenitor Chen had never been anything more than decoys to divert their attention. True God had led Lu Yin and the others to believe that all of the surviving Aeternals were together. This had succeeded because it was true, as without True God, it would have been impossible for the Aeternals to avoid Progenitor Chen.

Yet True God himself, along with his divine energy and the spirit seed mirebound artifact that had been stolen from Tian Ci, had gone and found Meng Sang at some point in time. Possibly without Meng Sang even realizing it, True God had followed the Seraph and left the Tianyuan Megaverse, traveling to the Spirit Nidus.

There was no other option. After the invaders from the Spirit Nidus had arrived in the Tianyuan Megaverse, only Meng Sang had been able to construct a springboard and leave. As for whether or not the Seraph was aware of his company, Lu Yin could not be sure.

Logically, Meng Sang should know, but given True God’s power, it might not be impossible for Meng Sang to never have noticed his company.

Still, True God fighting against the Origin Progenitor was unmistakably powerful. How had he managed to transfer his divine energy? And why do so at all? Had this been his way of escaping from the Six Paths of Reincarnation Realm?

That had to be it. This was the only way for True God to truly break free from the Six Paths of Reincarnation Realm and escape from the Tianyuan Megaverse. He had intended to secretly recultivate in the Spirit Nidus, without anyone being aware that he was still alive.

This could not even really be considered recultivating, as True God’s divine energy had gone with him. His strength would rise rapidly.

If not for Verdant King’s warning, no one would have learned the truth. Lu Yin stared at True God, suddenly certain that Meng Sang had no idea that he was not alone. True God was in an extremely fragile state as he left the Tianyuan Megaverse, and there was no chance that he had let anyone know about this.

True God took a moment to stare at Lu Yin. "Do you remember what I just told you, Dao Monarch Lu? We’ll meet again in the Spirit Nidus."

With that, he pulled a Nest out from his cosmic ring. "Here is a parting gift for you."

Using his strength, True God sent the Nest flickering through the void. It twinkled like a star in the night sky as it flew away.
    ''')
  ]),
  Content('user', [
    TextPart('''
    陆隐等人下意识都看向虫巢。

    唯一真神周身，无尽剑影璀璨，朝着虫巢飞去相反的方向打出，而那个方向，赫然是天狗，忘墟神还有王小雨。

    无尽剑影掠过虚空，宛如时光的碎片，直接穿透斗神天尊，木神他们，却对他们没有半点伤害，同时穿透天狗，最终，将忘墟神与王小雨穿透。

    陆隐陡然回头，怔怔望着。

    斗胜天尊，木神看向自己身体，不知道发生了什么，那一瞬间没什么感觉，却就是被穿透了。

    而忘墟神与王小雨，竟缓缓消失。

    唯一真神环顾四周：“天元宇宙，我永恒族，还会再来。”说完，身体轰然爆开，所幸始祖有准备，将唯一真神爆开的威力压缩在极限范围，否则这股破坏力足以让祖境死亡，这方时空就完了。

    唯一真神这具身体死了，彻底死亡，若没有青王，所有人都会以为唯一真神死了。

    可他，并没有死，将会以另一种姿态重现，神力这种本源的力量还在，无论是真神三绝技还是浊宝，他都有，更因为天赐的浊宝，将获得灵化宇宙的力量。

    陆隐现在明白为什么唯一真神宁愿出卖天赐，被灵化宇宙敌视，也是抢走天赐的浊宝。

    天赐的浊宝对他太重要了。

    从他被六道轮回界封住那一刻，或许就想到了这点。

    唯有重生，才可以摆脱大天尊的六道轮回界。

    天赐早就被他盯上。

    还有忘墟神以及王小雨，她们又是怎么回事？陆隐看过去。

    斗胜天尊，木神，天狗都还在，唯独这两个女人消失了。

    她们绝非死亡，而是被唯一真神送走。

    可是，为什么？

    唯一真神为什么对她们那么在意？黑无神死了，天狗也会死亡，包括青王，以及永恒族之前的三擎六昊，都一一死亡，也没见唯一真神那么在意，唯独对这两个女人在意。

    这两个女人肯定有问题。

    尤其是王小雨，他们都能看出来王小雨背叛第五大陆或许有问题，王小雨自己也知道，却还跟着唯一真神他们，唯一真神也不对她出手。

    种种迹象表明，这两个女人背后有大问题。

    辰祖到来，寻找四周，没看到王小雨，急忙找到陆隐：“陆主，王小雨呢？”

    陆隐看着辰祖：“为什么突然找来？”

    “我察觉不到王淼淼的气息了。”辰祖道。

    陆隐心一沉，不仅送走了忘墟神她们，还替忘墟神将辰祖留在她身上的力量抹除，唯一真神这具身体临死前，特意以虫巢转移自己等人注意，为的就是帮忘墟神她们脱困，她们背后隐藏的秘密究竟是什么？

    不久后，虫巢被超大巨人之祖带来，他去追虫巢了。

X


    而在场，唯一真神留在天元宇宙的隐患算是解除，黑无神，青王都死，忘墟神，王小雨虽然被送走，暂时来说肯定掀不起大浪，她们代表的必然是某种秘密，这个秘密陆隐没有头绪。

    剩下的唯有--天狗。

    而之所以能找到唯一真神他们，也是因为算计了

    天狗。

    太古城一战，唯一真神他们能逃，同样因为天狗。

    这只存活比整个人类历史还久远的生物，迎来了死亡。

    天狗睁眼，它身体破破烂烂，承受了太多攻伐。

    它可以单独撑住斗胜天尊的杀伐，撑住三界六道的杀伐，却也有极限，太古城那一战，为了骨舟可以逃离，它已经到达极限，发出哀嚎，而今，面对天上宗早有准备的手段，天狗终究没能撑住。

    陆隐站在天狗面前：“你到底能不能说话？”

    天狗眼睛睁着，血丝顺着眼角流淌，目光并没有看陆隐，而是看向那个石球，露出渴望。

    荒神带着石球走来，推到天狗面前。

    天狗艰难抬头，想靠近石球。

    陆隐看向荒神。

    荒神站在石球旁，面对天狗，这一战，它同样对天狗出手，然而不管是面对他，还是面对其他天上宗高手，天狗只是一味地挡在忘墟神她们面前，即便看到荒神也没有意外。

    “混寂不可能回来，它早就死了。”荒神开口。

    天狗目光狰狞，盯向他，龇牙。

    荒神看着天狗：“当初我就问过你，为什么追随永恒，你还没回答我。”

    天狗收回目光，垂下头，就这么盯着石球。

    无论荒神说什么，天狗都没有再搭理。

    最终，天狗抱着石球死去。

    看着天狗死亡，仿佛一个时代的终结。

    遥想当初，永恒族鼎盛，七神天，三擎六昊，真神卫队，祖境尸王等等，压得人类喘不过气，而今，这些都成为了历史。

    一个个离去。

    陆隐站在星空，不知道想什么。

    始祖也回去了太古城，临走前拍了拍陆隐肩膀：“柱子，我们应该庆幸，至少知道永恒那家伙没死，还有王淼淼她们有秘密，如果不是此战，这些我们都不知道，也不会在意。”

    “你做的很好了，没有人可以将一切掌握，老祖我也没想到永恒会有这一手，忽略了他的神力，你没有做到的，想到的，总有别人能补上，不要给自己太大压力。”

    “这天元宇宙，是你救下的。”

    始祖离开后，木先生到来。

    “师父，你说，人为什么想要看到未来？”陆隐望着星空问，他也不知道自己在想什么，不甘心？倒还真没有，唯一真神活了那么多年，自己能战胜永恒族已经万幸，集合整个天元宇宙资源击溃了灵化宇宙第一波强敌，同样幸运，凭什么所有好事都被自己占着。

    但此刻，他就是迷茫。

    不管是朋友还是敌人，他们的一个个消失，都在带走属于他存活于世的烙印。

    尽管他还很年轻，却总感觉自己的存在被淡化。

    每个人出生都有使命，如果自己的使命完结了，自己，是否还会存在？

    这宇宙有因果，自己终结了因带来的果，那么自己，属于下一个因？还是已经终结的果？如果这个果终结了，自己还会存在吗？

    人类相比宇宙太过渺小，即便踏入永生境又如何，还不是生活在宇宙中？

    修炼的意义是什么？

    一个普通人死去，又一个与之相关的人会诞生，这是否就是轮回？轮回，不是生命的轮回，而是因果轮回。

    人，不过是因果轮回的一个零件，仅此而已。

    陆隐看似平静的外表下，思绪如同倒卷的海洋，不断翻腾。

    萧声传来，来自木先生，他没有回答，而是以萧声，平复了陆隐的内心。

    陆隐闭起双目，什么都不想，思维放空，感受着宇宙星空。

    木先生的萧声在这星空回荡。

    过了不知道多久，萧声停止。

    陆隐睁眼，长吐出口气：“谢谢师父。”

    木先生看着陆隐，目光复杂：“或许，永恒的不死，救了你。”

    陆隐诧异，不明白木先生这话的意思。

    木先生感慨：“你走火入魔了。”

    陆隐收回目光，是吗？是啊，自己刚刚都不知道在想什么。

    “小七，为师也曾走火入魔。”

X


    “在那最后一战，我败了，不是败给了宿敌，而是败给了那个无所不能的存在。”

    “那时候我也问过自己，自己的坚持是什么？有什么意义？到头来不过是人家的一场游戏。”

    “为师也曾迷茫过，失意过，甚至有过死去的念头。”

    木先生看向陆隐：“可为师最后还是想通了，来到这方宇宙，帮太初固定蜃域，面对这方宇宙的永生境，为师也出手救走太初，收你们为弟子，破局，助你修炼，你可曾看到为师的失意？”

    “师父如何想通？”陆隐问。

    木先生笑了，他很少笑，数都数的过来：“即便永生境，又何尝不是游戏的一份子？”

    陆隐默默看着他。

    “一局棋，光有棋子可不够，还要有棋手，棋手何尝不是棋中一员？棋手就可以摆脱棋局了？那他就不是棋手。”

    “永生境也一样，你以为他在制定游戏，其实在为师看来，他是在制定因果。”

    陆隐目光陡睁：“制定因果？”

    木先生点头：“永生境很强，无敌的强，可以杀死任何人，但为什么还要有这场游戏？无聊？或许吧，但在为师看来，更是在制定因果，在这场游戏中，永生境比我们更惨。”

    “我们是被动参与，他们却要创造游戏，主动参与，胜负两说。”

    “因为他们被因果所限，他们比我们更惨。”

    “既然比我们更惨，何必纠结这是否是一场游戏？”

    “不管是永生境创造的游戏还是这宇宙规律，又或者是因果，随它去吧，你的出生都是宇宙给你的，陪它玩一场游戏又如何？就当孝顺这宇宙规律了，你可以孝顺父母，孝顺长辈，这宇宙，岂不是最大的长辈？”

    陆隐呆呆望着木先生，还有这种说法？

    “呵呵，怎么，离经叛道？”

    陆隐深呼吸口气，笑了，笑的很开心：“师父，弟子很幸运，做您的徒弟。”


    木先生笑着点头：“为师也很幸运，能有你这么个弟子。”

    ''')
  ]),
  Content('model', [
    TextPart('''
    Chapter 3386: Games And Karma
Lu Yin and the others instinctively turned to look at the Nest.

Dazzling images of swords surrounded True God before shooting out in the opposite direction of where the Nest had vanished. This happened to be where Skydog, Forgotten Ruins God, and Wang Xiaoyu all were.

The numerous sword shadows swept through outer space, and fragments of time stabbed through Sovereign Dou Sheng, Mu Shen, and the others, though none were harmed. Skydog was also stabbed, before the swords passed through him to stab Forgotten Ruins God and Wang Xiaoyu.

Lu Yin spun around, staring blankly around him.

Sovereign Dou Sheng and Mu Shen examined their bodies, unsure of what had just happened. They hadn’t felt anything happen to them, despite being run through by swords.

On the other hand, Forgotten Ruins God and Wang Xiaoyu both started to slowly vanish.

True God glanced around and then declared, "Tianyuan Megaverse, we Aeternals will return!"

With that, his body exploded loudly. Fortunately, the Origin Progenitor was prepared, and he managed to restrict most of the damage. If not for that, the explosion would have been powerful enough to kill all the peak powerhouses and destroy the entire universe.

True God’s body was gone, completely and utterly destroyed. Without Verdant King, everyone would have thought that True God was truly dead.

But that was not the case. He would simply reappear in another form. His divine energy, the essence of his strength, still existed. His three ultimate techniques and his mirebound artifact were still with him, and with Tian Ci's mirebound artifact, True God would soon gain the Spirit Nidus’s power as well.

Lu Yin finally understood why True God had been willing to betray Tian Ci and become the Spirit Nidus’s enemy. Everything had been done in order to obtain Tian Ci’s mirebound artifact.

That particular treasure was more important than anything else to True God.


From the moment he had first been sealed by Six Paths of Reincarnation Realm, Yong Heng might have already started planning for this.

Only by being reborn could he escape from the Great Sovereign's Six Paths of Reincarnation Realm.

Tian Ci had been True God’s target for a very long time.

As for Forgotten Ruins God and Wang Xiaoyu, what was happening with them? Lu Yin looked over.

Sovereign Dou Sheng, Mu Shen, and Skydog all remained where they had been, but the two women had disappeared.

They were not dead, but rather moved elsewhere by True God.

Why?

Why did True God care so much about those two? Blackless God was dead, and Skydog was also about to die. Verdant King and Aeternus’s Three Pillars and Six Skies were all dead, but True God had never demonstrated much concern for any of them. Only the two women had received such attention.

There was undoubtedly something unusual about them.

This was especially true of Wang Xiaoyu. Everyone could see that there was likely something wrong about her supposed betrayal of the Fifth Mainland. Wang Xiaoyu was even aware that her loyalty was regarded as suspect, and yet she continued to follow True God. Yong Heng had never done anything to harm the woman.

All of the signs indicated that there was a major issue with the two women.

Progenitor Chen arrived, and he looked around. When he did not find Wang Xiaoyu, he hurried over to Lu Yin. "Lord Lu, where is Wang Xiaoyu?"

Lu Yin looked at Progenitor Chen. "Why did you come here all of a sudden?"

"I can no longer sense Wang Miaomiao," Progenitor Chen reported.

Lu Yin's heart sank. Not only had Forgotten Ruins God and Wang Xiaoyu been sent away, but True God had also erased the power that Progenitor Chen had left on Wang Miaomiao. Right before the man’s body had been destroyed, he had purposely distracted everyone with a Nest, just so that he could help Forgotten Ruins God and Wang Xiaoyu escape. What secret were they hiding?

Soon, the Nest was brought back by the ancestor of the super giants, who had chased after it.

For the moment, it seemed that every threat in the Tianyuan Megaverse that was related to True God had been resolved. Blackless God and Verdant King were both dead. Forgotten Ruins God and Wang Xiaoyu were gone, but they would not be able to cause much trouble anytime soon. They had to be protecting some great secret, but Lu Yin had no clue what it might be.

The only one still alive and present was Skydog.

The Heavens Sect had only succeeded in finding True God and his followers because they had manipulated Skydog.

True God and his followers had escaped from the battle at the Immemorial Citadel because of Skydog.

The creature had lived longer than humanity had existed for, but it was on the verge of death.

Skydog opened his eyes. His body had been shredded, torn apart by too many attacks.

He had been able to withstand Sovereign Dou Sheng’s onslaught, and he had even survived being attacked by the Three Realms and Six Daos, but even so, Skydog’s durability had its limits. He had reached the breaking point at the Immemorial Citadel, but he had allowed the Ossis Ark to escape while the dog had howled in agony. After being ambushed by a great number of the Heavens Sect’s experts, Skydog had finally been pushed too far.

Lu Yin moved to stand in front of Skydog. "Can you speak, or not?"

Skydog's eyes were open, and blood trickled from their corners. He was not looking at Lu Yin, but rather at the stone ball. The dog’s eyes revealed a powerful yearning.

Wilderness God approached, and he moved the stone sphere over in front of Skydog.

The dog struggled, but he raised his head as he tried to move closer to the stone ball.

Lu Yin looked over at Wilderness God.

He stood by the stone ball, but was looking at Skydog. Wilderness God had also targeted Skydog during the most recent battle, but no matter who from the Heavens Sect he faced, Skydog had focused solely on protecting Forgotten Ruins God and Wang Xiaoyu. Even when attacked by Wilderness God, the dog had expressed no surprise.

"Stillstorm can't come back. They’ve been dead for a long, long time," Wilderness God stated.

Hatred filled Skydog's eyes as he glared at Wilderness God and bared his teeth.

Wilderness God continued to stare at Skydog. "I asked you long ago why you followed Yong Heng. You’ve never given me an answer."

Skydog looked away and dropped his head. His attention fully returned to the stone ball.

No matter what Wilderness God said after that, Skydog ignored him.

In the end, Skydog died while clutching the stone sphere.

Ads by Pubfuture
Witnessing Skydog's death felt like witnessing the end of an era.

Considering the situation, at Aeternus’s greatest heights, the Seven Skygods, the Three Pillars and Six Skies, True God Guard, and the numerous Progenitor-level corpse kings had all suppressed humanity so badly that many had given in to despair. However, all of those Aeternals had become history.

One by one, they had disappeared.

Lu Yin stood in outer space, lost in his own thoughts.

The Origin Progenitor returned to the Immemorial Citadel, but before he left, he patted Lu Yin on the shoulder. "Pillar, we should all be grateful. At least we now know that Yong Heng isn't really dead, as well as the fact that Wang Miaomiao and the others are harboring secrets. If not for this battle, we would have never learned about these things, nor would we have even cared enough to look into them.

"You’ve done well. No one can control everything. Even I failed to anticipate that Yong Heng would pull off such a thing by hiding his divine energy. What you are unable to accomplish or foresee, someone else will compensate for. There’s no need to put too much pressure on yourself.

"The entire Tianyuan Megaverse was saved because of you."

After the Origin Progenitor left, Mister Mu arrived.

"Master, why do you think people want to see the future?" Lu Yin asked, as he stared out into outer space. He was not even aware of his own thoughts. Was he resentful? Not really. True God had lived for so many years, and it was already a miracle that Lu Yin had managed to defeat Aeternus. He had gathered the resources of the entire Tianyuan Megaverse in order to hold back the first wave of the Spirit Nidus's invasion, but even that had taken a great deal of luck. Why did he enjoy so much good fortune?

At this moment, Lu Yin felt lost.

Both his friends and foes had disappeared one by one, and each loss felt like it had taken away a part of Lu Yin’s existence.

He was still quite young, yet he felt as if his existence was diminishing.

Everyone was born with a purpose. If Lu Yin’s mission was completed, would he still exist?

The megaverse operated on karmic causes and effects. If he brought an end to all the karmic effects resulting from certain causes, would he then become the next karmic cause in the cycle, or would he embody the ultimate karmic effect? And if he truly became the final effect, would he still continue to exist?

Humanity was insignificant, especially when compared to the vast megaverse. Even if a being became an Immortal, did they not still live in the megaverse?

What was the meaning of cultivating?

When an ordinary person died, another related person would be born. Was this the cycle of reincarnation? Reincarnation did not seem to be the cycle of life, but rather the cycle of karma.

Humans were nothing more than a single cog in the wheel of the karmic cycle, nothing more.

Beneath Lu Yin's seemingly calm exterior, his thoughts churned like a stormy ocean.

The sound of a flute floated through, coming from Mister Mu. He did not answer Lu Yin’s question, but instead used music to calm Lu Yin’s mind.

Lu Yin closed his eyes, purging all thoughts from his mind as he lost himself in the vastness of the megaverse.

Mister Mu’s flute music echoed across the universe.

After an unknown length of time, the flute fell silent.

Lu Yin opened his eyes and let out a deep breath. "Thank you, Master."

Mister Mu observed Lu Yin with a complicated expression. "It’s possible that Yong Heng’s survival saved you."

Lu Yin was taken aback, and he did not understand the comment.

Mister Mu sighed. "You were on the verge of losing yourself."

Lu Yin looked away. Was that accurate? Yes. He had not even known his own thoughts a few moments ago.

"Little Seven, I once nearly lost myself as well.

"During that final battle, I lost. I lost not to my enemy, but to that invincible being.

"At that time, I also asked myself what I was holding onto. What was the meaning of it all? In the end, everything was nothing more than someone else’s game.

"I became lost and disheartened. I even considered dying.

"In the end, I came to understand things. I came to this megaverse. I helped anchor the Mirari Realm here for Tai Chu, and I fought against Aeternus here. I saved Tai Chu, accepted you and the others as my disciples, and overcame great difficulties. I’ve guided your cultivation. Tell me, have you ever seen me lose heart?"

"How did you come to understand, Master?" Lu Yin asked.

Mister Mu smiled, which was a rare occurrence. "Aren’t even Immortals just another part of the game?"

Lu Yin said nothing as he stared at his master.


"A game of chess cannot be played with just pieces—there need to be players. However, aren’t the players also part of the game? Can a player ever truly escape the chessboard? If they do, they cease to be a player.

"Immortals are the same. You think that they’ve created the game, but as far as I’m concerned, they’re weaving karma."

Lu Yin’s eyes flared. "Weaving karma?"

Mister Mu nodded. "Immortals are immensely powerful, and they can even be considered invincible, as they are capable of killing anyone. But in that case, why create this game? Boredom? That might be possible, but to me, it’s more about weaving karma. In this game, Immortals might suffer even more than us.

"We participate passively, but they need to create the game and actively play it, despite having no guarantee of the outcome.

"They are bound by karma, which makes them even worse off than us.

"If they’re worse off than us, then why bother worrying about whether or not we’re just part of a game?

"Regardless of whether this is just a game created by Immortals, the laws of the universe, or karma itself, so be it. Your birth itself was a gift from the universe, so why not accompany it in this game? Consider playing an act of filial piety to the universe. You show filial piety to your parents and elders, so why not to the universe, the greatest elder of all?"

Lu Yin stared blankly at Mister Mu. Could this really be the man’s perspective?

"Heh, what’s wrong? Is my opinion too unconventional for you?"

Lu Yin took a deep breath, and then he laughed. It was a genuine, joyful laugh. "Master, I’m truly fortunate to be your disciple!"

Mister Mu nodded with a smile. "I’m also fortunate to have a disciple like you."
    ''')
  ]),
  Content('user', [
    TextPart('''
    无边战场，大石空，这里每个人都会背负石头，因为这片时空诞生过序列规则强者，因为逆转规则，被规则抹杀，导致大石空混乱，不断有杀机降临，唯有背负的石块铭刻祖境力量，才可抵御违反规则的杀机。

    曾经的大石空人不少，而今却几乎没人了。

    永恒族战败，大石空的人都搬迁去了其它平行时空。

    没人愿意终生背着石头生活。

    行走在大石空帝宫之外，驼临擦了擦额头的汗，背上是陆隐雕像，很重：“小玉，我们到了，这里就是师父曾经来过，还背负过石头的大石空帝宫，据说师父曾在这里…”

    “师父背负过的石头？我也不知道，那要找找，放心，一定找到，师父的足迹，我们都会看到。”

    踏入帝宫，这里曾经歌舞升平，尽管那个时期大石空是无边战场之一，与永恒族死战，但帝宫却极为繁华，那时候让陆隐不解，后来陆隐才知道，那时候的大石皇已经准备装死逃离大石空了。

    大石空的一切他都可以放下。

    无人守护帝宫，驼临进入，寻找着。

    过了数日，他才找到石坑，这里正是陆隐曾经在大石皇带路下选过石头的地方。

    此刻，石坑旁有不少人围着，还有导游。

    “诸位请看，这里就是大石空的石坑，你们头上的石头皆来自这里，等会我们离开后要归还的。”导游大喊，介绍着大石空的一切。

    “陆主当初就是在这选的石头参与大石空战场？”

    “没错，就在这里。”

    “陆主用过的石头呢？给我们看看。”

    “对啊，陆主用过的石头呢？”

    “诸位稍安勿躁，陆主用过的石头早已在战争中毁掉了，以陆主的实力都护不住石头，可以想象战场之激烈，据说那场战争不仅有祖境尸王，馈之术承载体，还有真神卫队队长。”

    “废话，大石空可是无边战场情报汇总地之一，当然激烈。”

    听着导游与众人对话，驼临没有接近，他也在听，到处都能听到师父的传奇故事，这是多么美好的一件事。

    “是啊，师父过的很苦，他的每一场战斗都很艰难。”

    “什么，你想为师父写传记？太好了，我也想到了，小玉，我们真是心灵相通，想到一块了。”

    “放心吧，等他们走了我们就去看，师父在那里留下了足迹。”

    “有熟悉的气息？是你的故人吗？算了，师父的足迹要紧，是啊，我也不想找，没什么能打扰我们行走师父每一次走过的路。”

    石坑旁，于冷看向四周，奇怪，有熟悉的气息，怎么回事？

    自从虫巢被天上宗追杀，他就参与各种旅游，生怕被虫子追上，这无边战场就是他不断旅游的地方之一，他已经来过三次了，这大石空也来过两次，不过不够，依然不够。

    天上宗如日中天，他现在根本不敢孕育虫子，只能等，等天上宗以后虫子彻底没了，才是他找地方安心发展的时机。

    这个时机一定会来的，一定会。

    不久后，这群人离去。

    驼临走到石坑旁，高兴：“我们到了，小玉，你说师父会在什么位置选石头？”

    “嗯，我也觉得是这，你能感觉到师父的气息？太好了，你离师父越来越近了，放心吧，等回天上宗，师父一定会很高兴收你为弟子的，你就是三师妹，毕竟上面还有一个师兄嘛，就是慧残。”

    “别这么说，师弟有他的优点，师父看到了，我们没看到，说明我们修炼的还不够，一定要努力，你也是，大家一起努力。”

    在石坑旁待了数天，期间又有一群人旅游到这，驼临避开了，不愿与人群接触。

    等那群人走后，驼临也离去了，总感觉背上师父的雕像更沉重了。

    …

    始空间，外宇宙，地球，陆隐来了。

    这次来不仅是见见故人，也是想了解混寂的事。

    在星空修炼那么多年，除了地球，他就没看过那种形象的生物，与地球必然有关。

    尽管地球距离天上宗如此之近，陆隐却几乎没来过。

    巧合的是，章顶天，白雪都在地球。

    陆隐的到来才出乎他们预料。

    尽管每一次相见时间间隔都不长，但陆隐飞跃的太快了，快到不可思议，以至于他们都感觉与陆隐太过遥远。

    除了这几人，周山的女儿周希希还带着她的儿子，丈夫，也都来了。

    “陆主。”

    “陆主。”

    “陆叔叔。”

    众人都有些放不开，虽然知道陆隐没有高高在上，但这种地位的变化却真实存在。

    即便周山都没有以前那么放得开了。

    周希希更不用说，以前还可以对陆隐撒娇，而今却很拘谨。

    陆隐与他们聊了一段时间，众人才渐渐放开。

    陆隐还是那个陆隐。

    因与果，最终都会走向终点。

    地球，算是陆隐的起点，他不知道自己的终点在哪，或许，也是在地球吧。

    距离他们不远的中部城市内，刘少歌同样回来了，在酒吧内坐着，晃动酒杯，听着耳边喧嚣的歌声，笑了笑。

    现在谁还会记得他，曾经能与陆隐争锋的人，而今，连进入天上宗的资格都没有。

X


    不过，这样正好，正好。

    他看着手掌，真武夜王，如果你还活着，不知道会怎么样。

    陆隐与舟山他们叙旧后，便让他们帮忙查阅地球上关于混寂的传说。

    混寂，在地球的传说很多。

    陆隐没有让天上宗插手，也是不想动静太大。

    混寂应该是死了，如果没死，现在在哪？去了其它宇宙？谁也不知道。

    调查混寂也是为了心安。

    陆隐在地球彻底放松了一段时间，跟普通人一样，躺在沙滩上望着海面。

    他忽然想起白浅，她在超时空被永恒族抓走，然后就再也找不到了，应该凶多吉少。

    当初两人还在沙滩上谋划对付禾然，曾经的一幕幕不断出现，尽管只有百多年，却发生了太多事。

    如果没有这百多年，天元宇宙的历史会如何？

    一段时间后，周山他们将关于混寂的所有传说整理，告诉了陆隐。

    而这些传说大多虚无缥缈，是人为杜撰，不过有一条传说引起了陆隐注意。

    神龙摆尾，遨游星辰，遁于岁末。

    短短的十二个字，来自一个龟壳，是最古老的文字。

    “这个龟壳的历史相当久远，超越了人类已知的文明历史，据说来自上一个，甚至更久远之前的文明。”周山道。

    地球每过一段时间都会经历文明灭绝，正因如此，地隐的人才特意对其他有远古独姓的星球出手，为的就是不让地球被关注到，因为太匪夷所思了。

    然而至今为止，都没人知道文明灭绝究竟是什么原因。

    地隐的人找过陆隐，希望陆隐能帮地球。

    陆隐也让陆不争调查过，却调查不出什么原因。


    周山话里的意思就是这个龟壳，属于曾经被灭绝的文明。

    至于多久远之前的文明就不知道了。

    “这话什么意思？”陆隐问。

    周山道：“意思就是神龙在星辰间游走，最后消失于木星。”

    陆隐诧异：“木星？”

    “岁，就是木星。”

    陆隐抬头看向星空，看到了木星。

    又是木星，木星很特殊，他知道，但对于如今的他而言根本不会有秘密。

    木星能去往树之星空，也是因为存在时空间的缝隙，就跟通过神武大陆可以去往三君主时空一样，不是什么太神奇的事。

    至于木星内部的力量，则是来自地隐，来自存在过的原宝阵法，也不是什么太了不起的事。

    地隐的存在就是防止文明被灭绝，不断有人被接引离去，位置就在木星。

    木星的秘密早已被看透。

    而今居然又跟混寂联系起来，莫非，木星通往其它时空的不止树之星空，还有外方宇宙？

X


    不会吧。

    “多谢，我先走了。”说完，陆隐离开地球，一步来到木星外，随后进入木星。

    地隐的人已经回归地球，这里也被空置了。

    降临木星，陆隐来到了曾经地隐的人待过的地方，这里还有人为留下的痕迹。

    一念间，整个木星情况皆了然，以前陆隐没在乎过这里，而今，他发现了什么，身体消失。

    那是一个祭台，很普通，很古老的祭台。

    由于地球本身离天上宗很近，木星同样如此，以陆隐的实力，轻易能看穿周边，这祭台他看过，而且不止一次，却没发现什么特殊的，当初只以为是地隐的人建造。

    如今与混寂一事结合，顿时发现不同了。

    这祭台上有个空的地方，看尺寸，正好可以放下石球，而且祭台周边有四根石柱，雕刻龙形。

    记得自己第一次看到这祭台的时候，就因为龙形石柱他才没在意，因为地球上雕刻龙形的建筑太多了，正因如此他才以为是地隐建造，如今想来，未必如此。

    陆隐看向地球，随便就能找到一个地隐的人询问。

    他人在木星，声音却在地球上某一个开杂货店男子耳边响起。

    “当初为什么将地隐藏在木星内？”
    ''')
  ]),
  Content('model', [
    TextPart('''
Chapter 3387: Close Of The Age
Everyone who entered the Endless Frontier’s Big Stone Universe had to carry a stone. This was because the universe had once produced a sequence powerhouse, but when the powerhouse died, the law that they had comprehended had been reversed. As a result, the Big Stone Universe had been thrown into chaos. Dangerous phenomena constantly roamed the universe, and only stones that were inscribed with that dead powerhouse’s strength were able to protect people from the deadly phenomena.

The Big Stone Universe had once boasted a large population, but it had since become nearly deserted.

After Aeternus's defeat, the people of the Big Stone Universe had relocated to other parallel universes.

No one wanted to carry a stone for their entire lives.

Walking up to the outside of the imperial palace, Tuo Lin cleaned the sweat from his forehead. On his back, he carried a statue of Lu Yin, which was heavy and cumbersome. "Little Ruyu, we’ve made it. Master once came here, and he found a stone for this Big Stone Universe in this imperial palace. They say that he once...

"The stone that Master carried? I don’t know, but we’ll look for it. Don’t worry, we’ll find it. We’ll visit every place that Master left a mark."

He entered the imperial palace. It had once been a place of festivity and grandeur. While the Big Stone Universe had been part of the Endless Frontier and a part of the battlefield in the deadly struggle against Aeternus, the palace had been remarkably prosperous for a time. Lu Yin had not understood why back then, but he had later learned that the Stone Emperor had been preparing to fake his death and escape from the Big Stone Universe.

The Stone Emperor had been prepared to abandon everything in the Big Stone Universe.

There was no one guarding the imperial palace, so Tuo Lin entered and started searching.

Several days later, he found the stone pit. It was the same place where the Stone Emperor had once taken Lu Yin to choose his own stone.

At the moment, there were many other people gathered around the stone pit, as well as a guide.

"Ladies and gentlemen, please have a look. This is the Big Stone Universe’s stone pit. All of the stones you are carrying on your heads are from this place, and they will be returned to it after we leave," the guide shouted as they explained everything about the Big Stone Universe.


"Did Lord Lu choose his stone here so that he could fight in the Big Stone Universe?"

"Yes, it was right here."

"What about the stone that Lord Lu used? Can we see it?"

"Yeah, where’s Lord Lu’s stone?"

"Everyone, please calm down. The stone that Lord Lu used was destroyed long ago during the war. Even with his strength, he wasn’t able to protect his stone. You can only imagine how intense that battle was. It’s said that there were terrifying Progenitor-level corpse kings, bestowal art carriers, and even a True God Guard Captain present.

"Naturally, the fighting was also intense here. The Big Stone Universe was home to one of the Endless Frontier’s intelligence centers."

Tuo Lin listened to the guide and the tourists, but he did not move any closer as he continued to listen. His master’s legendary stories could be heard everywhere, which was truly wonderful.

"Yes, Master lived a hard life. Every battle he fought was a struggle.

"What? You want to write Master’s biography? That’s great! I was thinking the same thing. Little Ruyu, we’re truly on the same wavelength, aren’t we?

"Don’t worry. We’ll check things out after they leave. Master certainly left a mark here.

"You sense a familiar aura? Someone from your past? Never mind that—following Master’s path is more important. That’s right, I don’t want to look for anything else. Nothing should interrupt us as we retrace Master’s footsteps."

Standing beside the stone pit, Yu Leng glanced around in confusion. He felt a familiar aura, but what was going on?

Ever since the Heavens Sect had started hunting for Nests, he had started going on various tours, afraid of being found by homeless insects. The Endless Frontier was one of his frequent destinations, and he had already visited the Big Stone Universe twice. Even so, this was still not enough. Nothing he did ever felt like it was enough.

The Heavens Sect stood at the pinnacle of the megaverse, and Yu Leng did not dare to produce any more insects. All he could do was wait. Wait for a time in the future when the Heavens Sect no longer focused on eradicating Nests and their insects. Only then would it be his time to find a safe place to develop in peace.

That time would surely come. It just had to come.

Before long, the tourists left.

Tuo Lin excitedly walked over to the stone pit. "We’re here, Little Ruyu! Where do you think Master would have found his stone?

"Hmm, I think so too. Oh, you can feel Master’s aura? That’s wonderful! It means that you’re getting closer to Master. Don’t worry, once we return to the Heavens Sect, Master will surely be happy to accept you as one of his disciples. You’ll be our third junior sister, after Brother Huican.

"Don’t say it like that. Junior Brother has his own strengths. Master saw them, even if we can’t. That just means that we haven’t cultivated enough. We all need to work harder, and that includes you. Let’s all work together."

He remained standing by the stone pit for several days. During that time, another group of tourists arrived, but Tuo Lin avoided this group, as he was unwilling to interact with a crowd.

Once the tourists left, Tuo Lin also left. He felt as though the statue of his master that he carried was constantly growing heavier.

...

In the Origin Universe, Lu Yin arrived in the Outerverse, and he visited Earth.

His visit was not only to spend time with old acquaintances, but also to look into Stillstorm.

Despite his years of cultivating and exploring multiple universes, Lu Yin had never seen any creature that looked like Stillstorm, aside from on Earth. There had to be a connection.

While Earth was extremely close to the Heavens Sect, Lu Yin rarely visited the planet.

Coincidentally, Zhang Dingtian and Bai Xue were also on Earth at this time, and they were surprised to see Lu Yin.

While it had not been that long since they had last seen Lu Yin, his progress was so quick and so incredible that it felt like he had already moved far away from them.

In addition to the two of them, Zhou Shan’s daughter, Zhou Xixi, was also on Earth, along with her son and husband.

"Lord Lu."

"Lord Lu."

"Uncle Lu."

Everyone felt a bit awkward. While they were aware that Lu Yin was not arrogant or unapproachable, the difference in their statuses was undeniable.

Even Zhou Shan was not as relaxed as he had once been with Lu Yin.

As for Zhou Xixi, her reservations were even more evident. She had once acted playfully around Lu Yin, but this time, she was very reserved.

Lu Yin talked with everyone for a bit, and they slowly started to relax.

Lu Yin was still the same person they had always known.

Ads by Pubfuture
Cause and effect. Everything eventually led to an ending.

Earth had been Lu Yin’s starting point. He did not know where he would find his ending, but that might also end up being Earth.

Not far from them, in a major city, Liu Shaoge had also returned to Earth. He was sitting in a bar, swirling a glass while listening to the noisy music that filled the room. He smiled.

Who would remember him? He had once stood as Lu Yin’s rival, but he currently lacked the qualifications to even enter the Heavens Sect.

Even so, this was fine. It was perfect, even.

He looked at his hand, lost in his thoughts. Nightking Zhenwu, if you were still alive, I wonder what things would be like.

After spending some time catching up with Zhou Shan and the others, Lu Yin asked them to help him research Earth’s legends that might be connected to Stillstorm.

There were many legends about the ancient astral beast on Earth.

Lu Yin did not involve anyone from the Heavens Sect, as he did not want to spend too much attention on this matter.

Stillstorm was most likely already dead. If not, where had they gone? Had the creature gone to another megaverse? No one knew.

Lu Yin was only investigating Stillstorm for his own peace of mind.

He spent some time on Earth just relaxing. He laid on the beach, like an ordinary person, staring out at the sea.

He was suddenly reminded of Bai Qian, who had been captured from the Transcendent Universe by Aeternus, never to be seen again. She was most likely dead.

There had been a time when Lu Yin and Bai Qian had plotted together to deal with He Ran while meeting on a beach. Lu Yin recalled those meetings. While Lu Yin had only been around for a hundred years or so, much had happened during that time.

Without those hundred years, how would history have unfolded in the Tianyuan Megaverse?

Some time later, Zhou Shan and the others finished compiling all of Earth’s legends about Stillstorm, and they shared the results with Lu Yin.

Most of the legends were vague or had been fabricated by humans, but there was one particular legend that caught Lu Yin’s attention.

The divine dragon swings its tail, traversing the stars, vanishing at the close of the age

There were just a few words inscribed on a turtle shell, written in the oldest known form of writing.

“This turtle shell is extraordinarily ancient, and it actually predates any known human civilization. It’s said to be from the previous civilization on Earth, or even older than that,” Zhou Shan explained.

Earth had a unique cycle where all of its civilizations were destroyed every so often. Because of this cycle of destruction, the Hidden Earth Society had specifically started intervening with other planets where people had primeval surnames, just to ensure that Earth did not attract too much attention. Such a cycle was simply too unbelievable.

Even at this moment, there was no one who understood what had caused Earth’s ancient civilizations to be erased.

The Hidden Earth Society had once approached Lu Yin, hoping that he would help Earth.

Lu Yin had even had Lu Buzheng investigate the matter, but no cause could be found.

Zhou Shan was suggesting that the turtle shell had belonged to one of those destroyed civilizations.

As for how long ago the civilization had existed, no one could guess.

“What does it mean?” Lu Yin asked.

“It means that a dragon moved through outer space and eventually vanished at Jupiter,” Zhou Shan replied.

Lu Yin was caught off guard. "Jupiter?"

"Yes. 'Age' refers to Jupiter."

Lu Yin looked up at the stars and saw Jupiter.

It was Jupiter yet again. Lu Yin had already known that Jupiter was special, but to someone like him, the planet should not be able to keep any more secrets.

Jupiter’s connection to the Perennial World existed because of a spatial passage, similar to the one that connected the Three Monarchs Universe to Shenwu Continent. Such a connection was nothing extraordinary.

As for the power that had been hidden within Jupiter, that had belonged to the Hidden Earth Society. There had once been a sourcebox array, but that also had not been particularly impressive.

The Hidden Earth Society’s purpose was to prevent Earth’s civilizations from being extinguished. They were constantly relocating people away from Earth, and those efforts started at Jupiter.

Jupiter’s secrets had long been exposed to him.

However, Lu Yin was finally learning that it had also had a connection to Stillstorm. Could Jupiter be connected to other parallel universes and not just the Perennial World? Could there be a connection to another megaverse?

That was impossible.


"Thanks. I’ll head off." With that, Lu Yin left Earth, a single step delivering him to Jupiter, before he entered the planet.

The Hidden Earth Society had returned to Earth, vacating Jupiter entirely.

As Lu Yin descended upon the planet, he arrived in the place that the Hidden Earth Society had once occupied. There were still traces of the people who had left.

It only took an instant for Lu Yin to gain a picture of everything about Jupiter. In the past, he had not cared too much about the planet, but he suddenly noticed something, and he vanished.

There was an altar. It was both simple and ancient.

Earth’s proximity to the Heavens Sect meant that Jupiter was also quite close. Lu Yin’s current strength allowed him to easily see across such distances, and he had even seen this altar before on multiple occasions. He simply had not noticed anything remarkable about it, and he had assumed that the Hidden Earth Society had built it.

After learning of Stillstorm’s connection to Jupiter, Lu Yin immediately noticed something different.

There was an empty spot on the altar that seemed to perfectly fit the stone sphere. There were four stone pillars around the altar, each carved with dragons.

Lu Yin remembered when he had first seen the altar, but because of the long dragons on the pillars, he had not paid much attention to the structure. There were too many dragon images on Earth, which was why Lu Yin had just assumed that the altar had been made by the Hidden Earth Society. He was no longer so certain.

He looked towards Earth. It would not take much effort to find someone from the Hidden Earth Society and ask them.

Lu Yin remained on Jupiter, but his voice reached the ears of a grocer in his store on Earth.

"Why did the Hidden Earth Society originally choose to hide inside of Jupiter?"
    ''')
  ]),
  Content('user', [
    TextPart('''
男子起初迷茫，紧接着神色大变，站在原地恭敬行礼：“因为木星本身存在过原宝阵法，扭曲时空，第一批地隐的人进入木星后也看到了一个祭台，上面的雕刻与地球上一样，猜测那里曾经与地球有关，所以将地隐藏在木星。”

    陆隐望着面前祭台，出神的看着龙形雕刻。

    那个开杂货店的男子就这么站在原地，没有动，生怕听漏了什么。

    周围人不解，一个个指指点点。

    唯有男子本身激动，当今宇宙，能与陆隐对话的有几人？他这辈子值了。

    木星上，陆隐取出石球，放入空置的位置。

    石球震动了一下，紧接着，球体表面的雕刻竟彷如活过来一般，整个木星气流转动，第一时间被地球观测到，引来地球的注意。

    陆隐望着石球上的雕刻，这个雕刻真的活过来了，散发出古朴沧桑的气息。

    这股气息与天元宇宙相合，却又有不同，准确的说，是与他身为人的感觉不同。

    混寂存在的年月，天元宇宙没有人，在它的认知中或许都不存在人类这种生物，它的气息涵盖了天元宇宙，是一个时代的主宰。

    混寂之后才是始祖，始祖之后，是陆隐。

    当混寂气息出现的一刻，太古城地底，始祖也察觉到了，同样的木先生也察觉到。

    尽管混寂的气息并不强大，毕竟只是一个祭祀之物。

    没有人打扰陆隐。

    陆隐站在祭台前，一步步走上去，抬手，按在石球上。

    咆哮声传入耳中，他梦回远古，在苍茫星空看到了一条蔓延无边无际的神龙掠过，散发着无与伦比的强悍气息。

    神龙每一个动作都印入陆隐脑海，他仿佛听到了什么，也感受到了什么。

    这一刻，不止他，地球上所有人刹那静止，眼前都浮现了神龙的影像，就连平行时空白云城，江峰看不到任何外物，在那看不见的黑暗中，都出现了神龙影像，利爪撕破黑暗，为他接引光明。

X


    神龙的影像只出现刹那。

    陆隐却已了解，他知道地球文明不断轮回灾劫的原因了，就是因为混寂。

    地球，应该是混寂诞生之地，尽管这颗星球很小。

    混寂在地球还有木星留下了属于它的力量，通过祭祀便能得到，远比整个天元宇宙其它地域得到的更多，这也是地球人为什么天赋绝佳的原因，只要有条件，地球人修炼速度远超其他人。

    然而混寂失踪，它留下的力量会随着某些条件而启动，或许是时间，或许是地球上出现了修炼文明等等，陆隐并不了解混寂，所以也无法了解它力量的构成。

    而混寂的力量并非流于外界，而是存在于地球这颗星球本身，存在于每一个生活在地球的人体内。

    文明的轮回灾劫，既是地球的灾劫，也是可以转化修炼混寂力量的契机。

    在那古老之前，地球上还没有人类的时候，必然存在修炼混寂力量的生物，那些生物，应该都算混寂的后代。


X

    陆隐望向地球，其实这件事也一直压在他心里，没想到竟然是这个原因。

    混寂的力量吗？

    这混寂的实力不会比始祖差，曾主宰整个天元宇宙，如今究竟是死是活？如果活着，它失踪又去了哪里？虫巢内石龙为什么组合的形状与混寂那么相似？莫非，混寂与仙主遭遇过？

    站的越高，看的越远。

    曾经，陆隐看到的是物种的竞争，而今，看到了岁月文明的更替。

    他不知道混寂之前还有什么文明生物，希望不要出现，那种东西一旦出现就不好收拾了，毕竟活了那么久，不是永生也永生了。

    对了，混寂失踪后人类才出现，是巧合，还是什么？

    石球压在祭台上，就可以压下混寂的力量，地球不会再经历轮回灾劫。

    陆隐本想返回天上宗，但天上宗就在旁边，回不回去没什么意义，倒不如留在这研究混寂的力量，或许有什么启发。

    与此同时，不知道相隔多少平行时空，忘墟神带着王小雨不断寻找着什么。

    足足半年的时间，她们最终来到一个荒凉的星球上。

    王小雨不明白忘墟神要做什么，而对于之前一战中，唯一真神将她们送走，她同样不意外。

    “诶，永恒大人跑了，虫巢也完了，黑无神那个有意思的家伙都死了，灵化宇宙那些人更不用说，要么藏起来，要么被抓，要么就死光，天元宇宙越来越没意思了，你说呢？小雨？”忘墟神伸了伸懒腰，摘下了面纱，脸上，辰祖留下的花的纹身消失。

    纹身消失，代表辰祖再也无法找到她。

    王小雨平静：“来这里做什么？”

    忘墟神笑眯眯看向她：“很多有意思的事都结束了，唯独你还在。”

    王小雨与忘墟神对视，没有说话。

    忘墟神绕着王小雨走一圈，发出赞叹声：“夏殇死追着你都不走。”她来到王小雨身后，凑近，对着她耳朵吹了口气：“告诉老祖，你想得到什么？”

    王小雨面色冷漠：“你不信任我？”

    “呵呵，当然信任。”忘墟神娇笑，缓缓走到王小雨面前，盯着她双目：“为了老祖我，你背叛第五大陆，挑起第五大陆与第六大陆战争，被称作第五大陆有史以来最大的叛徒。”

    “你加入树之星空背面战场，成为十二候，破祖后加入真神卫队，成为队长，与夏殇对决的时候你也从未插手，甚至引诱夏殇去死。”

    銆愯璇嗗崄骞寸殑鑰佷功鍙嬬粰鎴戞帹鑽愮殑杩戒功app锛屽挭鍜槄璇伙紒鐪熺壒涔堝ソ鐢紝寮€杞︺€佺潯鍓嶉兘闈犺繖涓湕璇诲惉涔︽墦鍙戞椂闂达紝杩欓噷鍙互涓嬭浇  銆?/p>

    “这一桩桩，一件件，都让老祖信任你。”

    王小雨目光掠过忘墟神，看向远处，那里出现无数奇怪的虫子，并非诞生自虫巢，而是这颗星球本身的虫子，很恶心，数量极多，却并不厉害。

    那些虫子在围攻一个基地，基地来自旁边星球，那颗星球发展出了科技，在这颗星球上建立基地，与虫子厮杀，想占据这颗星球。

    “没什么可说的，我对夏殇早已没了感情，他死不死与我无关，我只效忠族内，听老祖之令。”王小雨冷漠道。

    忘墟神嘴角弯起，此刻的她，美艳无比：“真乖，可爱的后辈这么听老祖的话，老祖也不能让你失望。”

    “带你看个好东西。”

    说完，垂下目光，看


    向地底，目光一凛，星球震动。

    远处，基地内，不少人惊慌：“地震了？怎么没预测？”

    “慌什么，地震而已，又不是星球开裂。”

    “愚蠢，以我们的手段应该提前预测到地震，如果没能预测到只有一个可能，这不是地震。”

    “那是什么？”

    “你，你，你们看？”有人惊呼。

    众人望向屏幕，其实都不需要看屏幕，看向外面都能很清楚。

    一柄血色长剑自地底而出，悬浮星空，血色光芒笼罩整个星球，让那些袭击基地的虫子颤栗，不敢动弹。

    基地内，屏幕乓的一声爆碎，所有人骇然望向那柄血色长剑。

    怎么会这样？剑？那不是古代的兵器吗？怎么会出现在这？一柄剑悬浮星空，这是何等的力量？能让星球震动，即便他们的科技都办不到。

    这个宇宙怎么了？

    不止基地内的人震惊，王小雨的震惊远在他们之上。

    她呆呆望着血色长剑，是它，没错，就是这柄剑。

    第二厄域战场，陆隐杀死天封，自天封体内出现的，就是这柄剑，血色长剑。

    血色长剑缓缓降落，落入忘墟神手中。

    血色映照下，忘墟神绝美脸庞宛如盛开在深渊的血色幽兰，美丽，却又危险。

    她笑眯眯看向王小雨，做了个嘘的手势：“不要说出去哦，这可是天元宇宙最大的秘密，这是，那位大人的佩剑。”

    王小雨迷茫看向忘墟神：“哪位，大人？”

    忘墟神娇笑：“还能是哪位大人？当然是，永生境大人。”

    说完，剑锋忽然落在王小雨脖颈，横斩。

    血溅大地。

    …

    自找到唯一真神那一战至今，过去了两年多。

    这段时间，辰祖不断寻找忘墟神与王小雨的踪迹，却毫无痕迹。

    天元宇宙依然在汇聚资源，制造机甲，微阵武器等等。

    再也没有找到过虫巢，陆隐放出了毛球青仙，不断周游平行时空，一是要寻找虫巢，二就是找灵化宇宙的人。

    虫巢没找到，灵化宇宙的人倒是找了几个。

    但相比灵化宇宙逃离的人还是太少了。

    那些人都在等着灵化宇宙第二波增援。

    这么找根本没用，如今但凡没有找到的虫巢必然是隐藏起来了，之所以确定虫巢没有被完全摧毁，因为天上宗始终有祖境跟着虫子。

    虫子会寻找就近的虫巢，那些被天上宗盯上的虫子一直有目的的寻找。

    还有，于冷还没被发现。

    这个屠戮六方道场的人必须找到，陆隐下了死命令。

    如今看似整个天元宇宙都在他掌控中，却依然有不少隐患。

    这一日，命女忽然找到陆隐：“最后一粒珠子，出现了。”

    陆隐目光陡睁，收起毛球青仙，急忙带着命女去寻找。

    命运有珠链，上面有十三粒珠子，其中有两粒被送出，一粒送给了陆家，一粒送给了一个孩子。
''')
  ]),
  Content('model', [
    TextPart('''
Chapter 3388: Crimson
At first, the grocer felt confused, but then his expression changed dramatically. His feet remained planted where they were, but he bowed respectfully and replied, "Jupiter once contained a sourcebox array that warped space. The first members of the Hidden Earth Society that arrived at Jupiter discovered an altar with carvings that were identical to some on Earth. They speculated that there was a connection to Earth, so they chose to establish the Hidden Earth Society on Jupiter."

Lu Yin stared at the altar before him, studying its dragon carvings.

The grocer remained rooted in place, afraid of missing anything.

The people around him grew confused, and they pointed and whispered among themselves.

However, the man himself was ecstatic. In the current universe, how many people were able to speak with Lu Yin? This single moment made the man’s entire life worthwhile.

On Jupiter, Lu Yin removed the stone sphere from his cosmic ring and placed it in the empty place on the altar.

The sphere trembled, and the etching on its surface seemed to come alive. Jupiter’s atmosphere started to swirl, which was immediately noticed by Earth, and it drew a great deal of attention.

Lu Yin stared at the etching on the stone ball. It moved as though the dragon was truly alive, and it gave off an ancient and timeless aura.

The aura resonated with the Tianyuan Megaverse as a whole, though it was also distinct. There was something about it that was specifically different from any human perspective.

During Stillstorm’s era, there had been no humans anywhere in the Tianyuan Megaverse. It was possible that Stillstorm had not even known about humanity as a species. The aura spread across every part of the Tianyuan Megaverse, as they had been the ruler of the megaverse for an era.

After Stillstorm had come the Origin Progenitor, and after the Origin Progenitor was Lu Yin.

The moment Stillstorm’s aura appeared, the Origin Progenitor sensed it, even from deep beneath the Immemorial Citadel. Mister Mu also sensed the aura.


This aura was not particularly powerful. It merely came from a leftover sacrificial object.

No one disturbed Lu Yin.

He stood before the altar, and then he slowly stepped forward. He raised a hand and pressed it against the stone sphere.

A roar rang in his ears, and he saw a vision of an ancient era. A dragon moved through the infinite universe, radiating an aura of unparalleled power.

Every tiny movement of the dragon was etched into Lu Yin’s memory. He seemed to hear something and also feel something profound.

At this moment, Lu Yin was not the only one experiencing this. Everyone on Earth froze as they saw a vision of the dragon. Even in the parallel universe of Whitecloud City, despite the fact that Jiang Feng was capable of sensing nothing but darkness, the image of the dragon appeared in his mind. He saw its claws tearing through the darkness, guiding him towards the light.

The vision of the dragon lasted for less than a moment.

Even so, Lu Yin understood. He knew that the reason behind Earth’s cyclical destruction was Stillstorm.

Earth was likely the birthplace of Stillstorm, despite being such a small planet.

Stillstorm had left their power behind on both Earth and Jupiter. Through sacrifices, that power could be accessed, at least far more than in any other place in the Tianyuan Megaverse. This power was also why Earthlings frequently possessed innate gifts and why their cultivation potential far exceeded others, so long as they were given an opportunity.

Because Stillstorm was gone, the power that they had left behind only activated under certain conditions. It might only be after a certain amount of time, or when civilization rose on Earth. Lu Yin did not have a full understanding of Stillstorm, and he was therefore unable to fully comprehend the power that had been left behind.

Stillstorm’s remnant power did not flow or leave, but rather remained within Earth itself. It existed in the bodies of every person living on Earth.

The cyclical destruction of civilizations was both a calamity for Earth, as well as an opportunity to harness and cultivate Stillstorm’s power.

In the ancient eras, before humans lived on Earth, there had to have been other creatures that had cultivated the power of Stillstorm. Those creatures had likely been regarded as Stillstorm’s descendants.

Lu Yin turned to look at Earth. The planet’s cyclical destruction had weighed on his mind for a long time. He had never considered such a possibility to be the reason for it.

The power of Stillstorm?

Stillstorm had likely been no weaker than the Origin Progenitor himself, having once ruled over the entire Tianyuan Megaverse. Was the beast dead or alive? If they were alive, where had they disappeared to? Why did the Lithic Drakes from the Nests work together to form a shape that so closely resembled Stillstorm? Could Stillstorm have once encountered the Immortal Lord?

The higher one rose, the further one saw.

Once, Lu Yin had seen a war between different species. He was currently observing the succession of civilizations across the ages.

He did not know what other civilizations or beings might have existed before Stillstorm, but Lu Yin hoped that they would not reappear. If such beings did show up, they would be very difficult to handle. After all, given how long they must have lived for, even if they were not Immortals, they would effectively be at that same level.

Also, humanity had only appeared after Stillstorm disappeared. Was that a coincidence, or was there something more to it?

The stone sphere sitting on the altar could suppress Stillstorm’s power, which meant that Earth would no longer experience a cycle of disasters.

Lu Yin had intended to return to the Heavens Sect, but since he was already so close, returning seemed pointless. It would be better for him to stay and study Stillstorm’s power. It was possible that he might receive some sort of new inspiration.

At the same time, an unknown number of parallel universes away, Forgotten Ruins God was leading Wang Xiaoyu while searching for something.

They traveled for six months before finally arriving at a desolate planet.

Wang Xiaoyu did not know what Forgotten Ruins God was trying to do, but the woman clearly had not been surprised that True God had sent the two of them away during the previous battle.

"Ah, Lord Yong Heng has run away, and the Nests are done for. Even that amusing guy Blackless God is dead now. As for all the people from the Spirit Nidus? They’re either hiding, prisoners, or dead. This megaverse is getting more and more boring. Don’t you think so, Xiaoyu?" Forgotten Ruins God stretched lazily and then removed her veil. Her exposed face revealed the fact that the flower mark that Progenitor Chen had left on her face had disappeared.

The fact that the tattoo was gone was why Progenitor Chen could no longer track her.

Wang Xiaoyu remained calm. "Why are we here?"

Forgotten Ruins God smiled. "Many interesting things are done, but you are still here."

Wang Xiaoyu met Forgotten Ruins God’s gaze, but she said nothing.

Forgotten Ruins God circled around Wang Xiaoyu, and then she let out a sigh of admiration. "Even Xia Shang wouldn’t leave you alone and chased after you, even when it meant risking death."

She leaned in close from behind Wang Xiaoyu and whispered into the woman’s ear, "Tell me, what do you desire?"

Ads by Pubfuture
Wang Xiaoyu’s expression remained indifferent. "You don’t trust me?"

"Heh, of course, I trust you," Forgotten Ruins God said with a little giggle. She slowly walked around to stand in front of Wang Xiaoyu and stared into her eyes. "For me, you betrayed the Fifth Mainland, and you even started the war between the Fifth and Sixth Mainlands, becoming the worst traitor in the history of the Fifth Mainland.

"You fought on the Perennial World’s rear battlefield, becoming one of the Twelve Marquis. When you broke through and became a Progenitor, you joined True God Guard and became a captain. Even during all the times when we fought against Xia Shang, you never interfered. You even lured Xia Shang to what should have been his death.

"Every single thing you’ve done makes me trust you," Forgotten Ruins God stated.

Wang Xiaoyu glanced past Forgotten Ruins God to look off into the distance. Countless strange insects had appeared there. They had not spawned from a Nest, but were instead indigenous to the planet. They looked absolutely revolting, but while there were a great many of the bugs, they were not particularly powerful.

The insects were attacking a base, which belonged to the people of a neighboring planet which was home to a civilization with advanced technology. They had established the base on the planet in order to fight off the insects and lay claim to the planet.

"There’s nothing to say. I’ve long lost any feelings I once held for Xia Shang. Whether he lives or dies has nothing to do with me. I belong to Aeternus alone, and I obey my ancestor’s orders," Wang Xiaoyu coldly affirmed.

A smile spread across Forgotten Ruins God’s lips, giving her a stunningly beautiful appearance. "How obedient. You’re such a lovely junior and so devoted to your ancestor. How could I let you down?

"Let me show you something interesting."

The woman then looked down at the ground. Her eyes intensely focused, and the planet began to quake.

In the distant base, many of the people there started to panic. "An earthquake? Why wasn’t it in the forecast?"

"What are you panicking for? It’s just an earthquake. It’s not like the planet is splitting apart."

"Fools! We’re able to detect any earthquake well in advance. There’s only one explanation for why we didn’t predict this one—it isn’t an earthquake."

"Then what is it?"

"Look! Look!" someone shouted.

Everyone turned to look at a display, though there was no need to. They could have simply looked outside and seen it just as clearly.

A long, crimson sword rose up from the ground and floated into outer space. It shone with a blood-red light that enveloped the entire planet, and the attacking insects trembled and froze even while at the base.

Inside the building, the display shattered with a loud bang. Everyone stared in horror at the long, crimson sword.

What was going on? A sword? That was an ancient, primitive weapon. How could one have appeared in such a place? A sword drifting out into outer space? What kind of power could accomplish that? Not even the civilization’s most advanced technology could cause an entire planet to tremble.

What was going on?

The people in the base were not the only ones who were startled; Wang Xiaoyu was even more badly shaken.

She stared blankly at the long, crimson sword. It was unmistakable. This was the same sword.

When the Second Scourge had been attacked, after Lu Yin had killed Tian Feng, this exact same blood-red sword had emerged from Tian Feng’s body.

The sword slowly descended back down, stopping in Forgotten Ruins God’s hand.

In the blood-red light, Forgotten Ruins God’s stunning face looked like a crimson orchid blooming in the depths of an abyss; it was beautiful, but also dangerous.

She directed a sweet smile at Wang Xiaoyu while holding a finger to her lips. "Don’t tell anyone, alright? This is the Tianyuan Megaverse’s greatest secret. This sword was that lord’s own weapon."

Wang Xiaoyu stared at Forgotten Ruins God in confusion. "Which lord?"

Forgotten Ruins God chuckled. "Who else could it be? The lord Immortal, of course."

As soon as she finished speaking, the blade suddenly sliced sideways, right at Wang Xiaoyu’s neck.

Blood splattered across the ground.

...

More than two years had passed since the battle that had exposed True God’s escape to the Spirit Nidus.

During this time, Progenitor Chen had never stopped searching for even a trace of Forgotten Ruins God and Wang Xiaoyu, but he had not been able to find anything.

The Tianyuan Megaverse was still gathering resources, building mechas, constructing microarrays, and making more preparations.


No more Nests had been found. Lu Yin had released his captive Verdant Sage to travel across parallel universes, both to search for more Nests and to find people from the Spirit Nidus.

The Nests remained elusive, but several people from the Spirit Nidus were discovered.

Still, even with those who were found, far too many people from the Spirit Nidus had successfully escaped.

All of them were waiting for reinforcements to arrive from the Spirit Nidus.

Searching in such a manner was proving useless. Any undiscovered Nest had undoubtedly been hidden. The reason why Lu Yin knew for certain that not all of the Nests had been destroyed was because the Heavens Sect still had peak powerhouses following insects.

The bugs instinctively sought out the nearest Nest, and it was clear that the ones that the Heavens Sect was tracking were moving with purpose.

On top of that, Yu Leng had never been found.

The butcher of the Sixverse Academy needed to be found, and Lu Yin had issued an edict ordering it to be done.

While it appeared as if the entire Tianyuan Megaverse was under Lu Yin’s control, there were still numerous hidden dangers.

One day, Destina suddenly arrived to speak with Lu Yin. "The last pearl has appeared."

Lu Yin’s eyes went wide. He quickly grabbed the Verdant Sage and raced off with Destina to investigate.

Destiny had once had a bracelet of thirteen pearls. Two of them had been given away: one to the Lu family, and the other to a child.


  ''')
  ]),
];
