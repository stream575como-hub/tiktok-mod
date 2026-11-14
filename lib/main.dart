import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const TikTokModApp());

class TikTokModApp extends StatelessWidget {
  const TikTokModApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok Mod by Mistrzel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

const Map<String, Color> kBannerColors = {
  'red': Color(0xFFFE2C55),
  'blue': Color(0xFF1D9BF0),
  'green': Color(0xFF22C55E),
  'orange': Color(0xFFF59E0B),
  'purple': Color(0xFF8B5CF6),
};

class ModBanner {
  ModBanner({
    required this.text,
    this.color = 'red',
    this.pos = 'top',
    this.dismissible = true,
    this.enabled = true,
  });

  String text;
  String color;
  String pos;
  bool dismissible;
  bool enabled;

  factory ModBanner.fromJson(Map<String, dynamic> j) => ModBanner(
        text: (j['text'] ?? '').toString(),
        color: (j['color'] ?? 'red').toString(),
        pos: (j['pos'] ?? 'top').toString() == 'bottom' ? 'bottom' : 'top',
        dismissible: j['dismissible'] != false,
        enabled: j['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'color': color,
        'pos': pos,
        'dismissible': dismissible,
        'enabled': enabled,
      };

  String get key => '$pos|$text';

  Color get bg {
    if (color.startsWith('#') && color.length == 7) {
      final v = int.tryParse(color.substring(1), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return kBannerColors[color] ?? kBannerColors['red']!;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final WebViewController _controller;
  bool _busy = false;

  // ustawienia modow
  double _rate = 1.0;
  bool _auto = false;
  bool _mobileUa = false;

  final Map<String, Map<String, dynamic>> _infoCache = {};

  // banery
  List<ModBanner> _local = [];
  List<ModBanner> _remote = [];
  final Set<String> _dismissed = {};
  bool _devUnlocked = false;
  String _remoteUrl = '';

  static const String _iphoneUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
      'Mobile/15E148 Safari/604.1';

  // JS: znajduje link do filmu najblizej srodka ekranu
  static const String _findVideoJs = r'''
(function () {
  var links = [].slice.call(document.querySelectorAll('a[href*="/video/"]'));
  var best = null, bestDist = 1e9, cy = window.innerHeight / 2;
  links.forEach(function (a) {
    var r = a.getBoundingClientRect();
    if (r.bottom > 0 && r.top < window.innerHeight) {
      var d = Math.abs((r.top + r.bottom) / 2 - cy);
      if (d < bestDist) { bestDist = d; best = a.href; }
    }
  });
  return best || location.href;
})()
''';

  // JS: predkosc odtwarzania + auto-nastepny film
  static const String _modsJs = r'''
(function () {
  window.__mod = window.__mod || {};
  window.__mod.rate = __RATE__;
  window.__mod.auto = __AUTO__;
  if (window.__modTimer) return;
  window.__modTimer = setInterval(function () {
    var m = window.__mod;
    var vs = document.querySelectorAll('video');
    var cy = window.innerHeight / 2;
    vs.forEach(function (v) {
      if (v.playbackRate !== m.rate) v.playbackRate = m.rate;
      if (m.auto) {
        var r = v.getBoundingClientRect();
        if (r.top < cy && r.bottom > cy && v.duration > 0 &&
            v.currentTime >= v.duration - 0.35 && !v.__nexted) {
          v.__nexted = true;
          var btn = document.querySelector('[data-e2e="arrow-right"]');
          if (btn) { btn.click(); }
          else {
            document.dispatchEvent(new KeyboardEvent('keydown',
              {key: 'ArrowDown', keyCode: 40, bubbles: true}));
          }
          setTimeout(function () { v.__nexted = false; }, 2000);
        }
      }
    });
  }, 300);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _applyMods()),
      )
      ..loadRequest(Uri.parse('https://www.tiktok.com/'));
    _loadBanners();
  }

  // ---------- narzedzia ----------

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _msg('Błąd: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cleanUrl(String url) => url.split('?').first.split('#').first;

  String? _channelFromUrl(String url) =>
      RegExp(r'@([^/?#]+)').firstMatch(url)?.group(1);

  String _abs(String u) => u.startsWith('/') ? 'https://www.tikwm.com$u' : u;

  Future<String> _currentVideoUrl() async {
    final res = await _controller.runJavaScriptReturningResult(_findVideoJs);
    var s = res.toString();
    if (s.startsWith('"') && s.endsWith('"')) {
      s = jsonDecode(s) as String;
    }
    return s;
  }

  Future<String?> _videoUrlOrWarn() async {
    final url = await _currentVideoUrl();
    if (!url.contains('/video/')) {
      _msg('Otwórz film (kliknij go), potem użyj moda.');
      return null;
    }
    return url;
  }

  Future<Map<String, dynamic>> _fetchInfo(String pageUrl) async {
    final clean = _cleanUrl(pageUrl);
    final cached = _infoCache[clean];
    if (cached != null) return cached;
    final api = Uri.parse('https://www.tikwm.com/api/')
        .replace(queryParameters: {'url': clean, 'hd': '1'});
    final r = await http.get(api).timeout(const Duration(seconds: 20));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['code'] != 0) throw Exception(j['msg'] ?? 'Błąd API');
    final d = j['data'] as Map<String, dynamic>;
    _infoCache[clean] = d;
    return d;
  }

  String _author(Map<String, dynamic> d, String url) =>
      (d['author']?['unique_id'] ?? _channelFromUrl(url) ?? 'nieznany')
          .toString();

  Future<File> _saveToTemp(String url, String name, String ext) async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      throw Exception('Nie udało się pobrać pliku (${r.statusCode})');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(r.bodyBytes);
    return file;
  }

  // ---------- mody ----------

  Future<void> _applyMods() async {
    final js = _modsJs
        .replaceAll('__RATE__', _rate.toString())
        .replaceAll('__AUTO__', _auto.toString());
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _download() => _run(() async {
        final url = await _videoUrlOrWarn();
        if (url == null) return;
        final d = await _fetchInfo(url);
        final author = _author(d, url);
        final file = await _saveToTemp(
            _abs((d['hdplay'] ?? d['play']) as String), author, 'mp4');
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        await Gal.putVideo(file.path);
        _msg('Zapisano w Zdjęciach. Kanał: @$author');
      });

  Future<void> _downloadAudio() => _run(() async {
        final size = MediaQuery.of(context).size;
        final url = await _videoUrlOrWarn();
        if (url == null) return;
        final d = await _fetchInfo(url);
        final music = (d['music'] ?? '') as String;
        if (music.isEmpty) throw Exception('Ten film nie ma osobnego dźwięku');
        final file =
            await _saveToTemp(_abs(music), '${_author(d, url)}_audio', 'mp3');
        await Share.shareXFiles(
          [XFile(file.path)],
          sharePositionOrigin:
              Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1),
        );
      });

  Future<void> _showChannel() async {
    try {
      final url = await _currentVideoUrl();
      final channel = _channelFromUrl(url);
      _msg(channel != null
          ? 'Kanał: @$channel'
          : 'Nie wykryto kanału. Kliknij film, żeby go otworzyć.');
    } catch (e) {
      _msg('Błąd: $e');
    }
  }

  Future<void> _openChannel() async {
    try {
      final channel = _channelFromUrl(await _currentVideoUrl());
      if (channel == null) {
        _msg('Nie wykryto kanału. Kliknij film, żeby go otworzyć.');
        return;
      }
      await _controller
          .loadRequest(Uri.parse('https://www.tiktok.com/@$channel'));
    } catch (e) {
      _msg('Błąd: $e');
    }
  }

  Future<void> _copyLink() async {
    try {
      final url = await _videoUrlOrWarn();
      if (url == null) return;
      await Clipboard.setData(ClipboardData(text: _cleanUrl(url)));
      _msg('Skopiowano czysty link (bez śledzenia)');
    } catch (e) {
      _msg('Błąd: $e');
    }
  }

  Future<void> _copyCaption() => _run(() async {
        final url = await _videoUrlOrWarn();
        if (url == null) return;
        final d = await _fetchInfo(url);
        final title = (d['title'] ?? '').toString();
        if (title.isEmpty) throw Exception('Film nie ma opisu');
        await Clipboard.setData(ClipboardData(text: title));
        _msg('Skopiowano opis filmu');
      });

  Future<void> _addFav() async {
    try {
      final url = await _videoUrlOrWarn();
      if (url == null) return;
      final clean = _cleanUrl(url);
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('favs') ?? <String>[];
      if (list.contains(clean)) {
        _msg('Ten film już jest w ulubionych');
        return;
      }
      list.add(clean);
      await prefs.setStringList('favs', list);
      _msg('Dodano do ulubionych (${list.length})');
    } catch (e) {
      _msg('Błąd: $e');
    }
  }

  Future<void> _showFavs() async {
    final prefs = await SharedPreferences.getInstance();
    var list = List<String>.from(prefs.getStringList('favs') ?? <String>[]);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Brak ulubionych. Dodaj film z menu Mody.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final url = list[i];
                    return ListTile(
                      leading: const Icon(Icons.favorite),
                      title: Text('@${_channelFromUrl(url) ?? '?'}'),
                      subtitle: Text(url, maxLines: 1),
                      onTap: () {
                        Navigator.pop(ctx);
                        _controller.loadRequest(Uri.parse(url));
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          list.removeAt(i);
                          await prefs.setStringList('favs', list);
                          setSheet(() {});
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _setMobileUa(bool v) async {
    _mobileUa = v;
    await _controller.setUserAgent(v ? _iphoneUa : null);
    await _controller.reload();
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) await _controller.goBack();
  }

  // ---------- banery ----------

  List<ModBanner> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final l = jsonDecode(raw) as List;
      return l
          .map((e) => ModBanner.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((b) => b.text.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadBanners() async {
    final prefs = await SharedPreferences.getInstance();
    _remoteUrl = prefs.getString('remote_url') ?? '';
    _local = _decode(prefs.getString('banners'));
    _remote = _decode(prefs.getString('remote_cache'));
    if (mounted) setState(() {});
    await _refreshRemote();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'banners', jsonEncode(_local.map((b) => b.toJson()).toList()));
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote({bool announce = false}) async {
    if (_remoteUrl.isEmpty) {
      if (announce) _msg('Najpierw wpisz adres JSON');
      return;
    }
    try {
      final r = await http
          .get(Uri.parse(_remoteUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = _decode(utf8.decode(r.bodyBytes));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'remote_cache', jsonEncode(list.map((b) => b.toJson()).toList()));
      if (mounted) setState(() => _remote = list);
      if (announce) _msg('Pobrano ${list.length} banerów');
    } catch (e) {
      if (announce) _msg('Błąd: $e');
    }
  }

  Widget _bannerBar(ModBanner b) => Material(
        color: b.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  b.text,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              if (b.dismissible)
                GestureDetector(
                  onTap: () => setState(() => _dismissed.add(b.key)),
                  child: const Icon(Icons.close, size: 18, color: Colors.white),
                ),
            ],
          ),
        ),
      );

  Future<String?> _askText(String title, String hint,
      {bool obscure = false, String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: obscure,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _openDev() async {
    if (!_devUnlocked) {
      final prefs = await SharedPreferences.getInstance();
      final pin = prefs.getString('dev_pin') ?? '2513';
      final entered = await _askText('Tryb developera', 'Podaj PIN',
          obscure: true);
      if (entered == null) return;
      if (entered != pin) {
        _msg('Zły PIN');
        return;
      }
      _devUnlocked = true;
    }
    if (!mounted) return;
    _devSheet();
  }

  Future<void> _addBannerDialog() async {
    final text = TextEditingController();
    String color = 'red';
    String pos = 'top';
    bool dismissible = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nowy baner'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Treść banera'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: kBannerColors.entries
                      .map((e) => GestureDetector(
                            onTap: () => setD(() => color = e.key),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: e.value,
                              child: color == e.key
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'top', label: Text('Góra')),
                    ButtonSegment(value: 'bottom', label: Text('Dół')),
                  ],
                  selected: {pos},
                  onSelectionChanged: (s) => setD(() => pos = s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Można zamknąć'),
                  value: dismissible,
                  onChanged: (v) => setD(() => dismissible = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Anuluj')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Dodaj')),
          ],
        ),
      ),
    );
    if (ok == true && text.text.trim().isNotEmpty) {
      _local.add(ModBanner(
        text: text.text.trim(),
        color: color,
        pos: pos,
        dismissible: dismissible,
      ));
      await _saveLocal();
      _msg('Dodano baner');
    }
  }

  void _devSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) => ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Tryb developera: banery',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Dodaj baner'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _addBannerDialog();
                },
              ),
              if (_local.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Brak własnych banerów.',
                      style: TextStyle(color: Colors.white54)),
                ),
              for (var i = 0; i < _local.length; i++)
                ListTile(
                  leading: CircleAvatar(radius: 10, backgroundColor: _local[i].bg),
                  title: Text(_local[i].text,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_local[i].pos == 'top' ? 'góra' : 'dół'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _local[i].enabled,
                        onChanged: (v) async {
                          _local[i].enabled = v;
                          await _saveLocal();
                          setSheet(() {});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          _local.removeAt(i);
                          await _saveLocal();
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Kopiuj JSON banerów'),
                subtitle: const Text(
                    'Wklej do pliku na GitHubie, żeby widziały go wszystkie urządzenia'),
                onTap: () async {
                  final enc = JsonEncoder.withIndent('  ');
                  await Clipboard.setData(ClipboardData(
                      text: enc.convert(_local.map((b) => b.toJson()).toList())));
                  _msg('Skopiowano JSON');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: const Text('Adres JSON (zdalne banery)'),
                subtitle: Text(_remoteUrl.isEmpty ? 'nie ustawiono' : _remoteUrl,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final v = await _askText('Adres JSON z banerami', 'https://...',
                      initial: _remoteUrl);
                  if (v == null) return;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('remote_url', v.trim());
                  _remoteUrl = v.trim();
                  setSheet(() {});
                  await _refreshRemote(announce: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Odśwież zdalne banery'),
                onTap: () => _refreshRemote(announce: true),
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Zmień PIN'),
                onTap: () async {
                  final v = await _askText('Nowy PIN', 'min. 4 znaki',
                      obscure: true);
                  if (v == null) return;
                  if (v.length < 4) {
                    _msg('PIN musi mieć min. 4 znaki');
                    return;
                  }
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('dev_pin', v);
                  _msg('PIN zmieniony');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- menu modow ----------

  void _openMods() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget tile(IconData icon, String text, VoidCallback onTap) =>
                ListTile(
                  leading: Icon(icon),
                  title: Text(text),
                  onTap: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                );
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Mody',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('TikTok Mod by Mistrzel',
                      style: TextStyle(fontSize: 13, color: Colors.white54)),
                ),
                tile(Icons.download, 'Pobierz film (bez znaku wodnego)',
                    _download),
                tile(Icons.music_note, 'Pobierz dźwięk (MP3)', _downloadAudio),
                tile(Icons.person, 'Pokaż kanał', _showChannel),
                tile(Icons.open_in_new, 'Otwórz kanał autora', _openChannel),
                tile(Icons.link, 'Kopiuj czysty link', _copyLink),
                tile(Icons.notes, 'Kopiuj opis filmu', _copyCaption),
                tile(Icons.favorite_border, 'Dodaj do ulubionych', _addFav),
                tile(Icons.favorite, 'Moje ulubione', _showFavs),
                tile(Icons.developer_mode, 'Tryb developera', _openDev),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Prędkość'),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SegmentedButton<double>(
                          segments: const [
                            ButtonSegment(value: 0.5, label: Text('0.5x')),
                            ButtonSegment(value: 1.0, label: Text('1x')),
                            ButtonSegment(value: 1.5, label: Text('1.5x')),
                            ButtonSegment(value: 2.0, label: Text('2x')),
                          ],
                          selected: {_rate},
                          onSelectionChanged: (s) {
                            setState(() => _rate = s.first);
                            setSheet(() {});
                            _applyMods();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.skip_next),
                  title: const Text('Auto-następny film'),
                  subtitle: const Text('Przewija sam po końcu filmu'),
                  value: _auto,
                  onChanged: (v) {
                    setState(() => _auto = v);
                    setSheet(() {});
                    _applyMods();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.phone_iphone),
                  title: const Text('Wersja mobilna strony'),
                  subtitle: const Text('Układ jak na telefonie (przeładuje)'),
                  value: _mobileUa,
                  onChanged: (v) {
                    setState(() => _mobileUa = v);
                    setSheet(() {});
                    _setMobileUa(v);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text('Made by Mistrzel',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [..._remote, ..._local]
        .where((b) => b.enabled && !_dismissed.contains(b.key))
        .toList();
    final top = shown.where((b) => b.pos == 'top').toList();
    final bottom = shown.where((b) => b.pos == 'bottom').toList();
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: top.map(_bannerBar).toList(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: bottom.map(_bannerBar).toList(),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 24 + bottom.length * 44.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'back',
                    onPressed: _back,
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'mods',
                    onPressed: _openMods,
                    child: const Icon(Icons.tune),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'download',
                    onPressed: _busy ? null : _download,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Pobierz'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
