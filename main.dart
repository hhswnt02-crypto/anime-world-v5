
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const api = 'https://api.jikan.moe/v4';

void main() => runApp(const AnimeWorldApp());

class Anime {
  final int id;
  final String title, image, synopsis, type;
  final int? episodes;
  final double? score;

  const Anime({
    required this.id,
    required this.title,
    required this.image,
    required this.synopsis,
    required this.type,
    this.episodes,
    this.score,
  });

  factory Anime.fromJson(Map<String, dynamic> j) {
    final jpg = j['images']?['jpg'];
    return Anime(
      id: (j['mal_id'] as num?)?.toInt() ?? 0,
      title: '${j['title'] ?? 'بدون عنوان'}',
      image: '${jpg?['large_image_url'] ?? jpg?['image_url'] ?? ''}',
      synopsis: '${j['synopsis'] ?? 'لا يوجد وصف متاح.'}',
      type: '${j['type'] ?? 'Anime'}',
      episodes: (j['episodes'] as num?)?.toInt(),
      score: (j['score'] as num?)?.toDouble(),
    );
  }
}

class Episode {
  final int season, number;
  final String title, url;

  const Episode({
    required this.season,
    required this.number,
    required this.title,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
    'season': season,
    'number': number,
    'title': title,
    'url': url,
  };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
    season: (j['season'] as num?)?.toInt() ?? 1,
    number: (j['number'] as num?)?.toInt() ?? 1,
    title: '${j['title'] ?? 'الحلقة'}',
    url: '${j['url'] ?? ''}',
  );
}

class LocalStore {
  static const episodesKey = 'episodes_v5';
  static const favoritesKey = 'favorites_v5';

  static Future<Map<int, List<Episode>>> episodes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(episodesKey);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map;
      return m.map((k, v) => MapEntry(
        int.tryParse('$k') ?? 0,
        (v as List).map((e) => Episode.fromJson(Map<String, dynamic>.from(e))).toList(),
      ));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveEpisodes(Map<int, List<Episode>> data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(episodesKey, jsonEncode(
      data.map((k, v) => MapEntry('$k', v.map((e) => e.toJson()).toList())),
    ));
  }

  static Future<Set<int>> favorites() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(favoritesKey) ?? [])
        .map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> saveFavorites(Set<int> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(favoritesKey, ids.map('$').toList());
  }
}

class Api {
  static Future<List<Anime>> list(String path) async {
    final r = await http.get(Uri.parse('$api$path')).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('تعذر تحميل البيانات');
    final data = jsonDecode(r.body)['data'];
    if (data is! List) return [];
    return data.whereType<Map>()
        .map((e) => Anime.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<List<Anime>> top() => list('/top/anime?limit=24&page=1');
  static Future<List<Anime>> movies() =>
      list('/anime?type=movie&order_by=score&sort=desc&limit=24');
  static Future<List<Anime>> search(String q) =>
      list('/anime?q=${Uri.encodeQueryComponent(q)}&limit=24&sfw=true');
}

class AnimeWorldApp extends StatelessWidget {
  const AnimeWorldApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Anime World',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff070a10),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool loading = true;
  String? error;
  String query = '';
  List<Anime> anime = [], movies = [], results = [];
  Set<int> favorites = {};
  Map<int, List<Episode>> episodes = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final values = await Future.wait([
        Api.top(), Api.movies(), LocalStore.favorites(), LocalStore.episodes()
      ]);
      if (!mounted) return;
      setState(() {
        anime = values[0] as List<Anime>;
        movies = values[1] as List<Anime>;
        favorites = values[2] as Set<int>;
        episodes = values[3] as Map<int, List<Episode>>;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = '$e'; });
    }
  }

  Future<void> search(String q) async {
    setState(() => query = q);
    if (q.trim().isEmpty) {
      setState(() => results = []);
      return;
    }
    try {
      final r = await Api.search(q);
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل البحث: $e')));
    }
  }

  Future<void> toggleFavorite(int id) async {
    setState(() => favorites.contains(id)
        ? favorites.remove(id) : favorites.add(id));
    await LocalStore.saveFavorites(favorites);
  }

  void openAnime(Anime a) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(
      anime: a,
      favorite: favorites.contains(a.id),
      episodes: episodes[a.id] ?? [],
      onFavorite: () => toggleFavorite(a.id),
      onEpisodesChanged: (list) async {
        setState(() => episodes[a.id] = list);
        await LocalStore.saveEpisodes(episodes);
      },
    )));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(error!, textAlign: TextAlign.center),
        const SizedBox(height: 15),
        FilledButton(onPressed: load, child: const Text('إعادة المحاولة')),
      ],
    )));

    final pages = [
      homePage(),
      gridPage('الأنمي', query.isEmpty ? anime : results),
      gridPage('الأفلام', movies),
      favoritePage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.tv_outlined), label: 'الأنمي'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), label: 'الأفلام'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'المفضلة'),
        ],
      ),
    );
  }

  Widget homePage() => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Text('Anime World', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ),
        searchBox(),
        if (anime.isNotEmpty) heroCard(anime.first),
        section('🔥 أنميات مشهورة', anime),
        section('🎬 أفلام الأنمي', movies),
      ],
    ),
  );

  Widget searchBox() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 5, 20, 12),
    child: TextField(
      onChanged: search,
      decoration: InputDecoration(
        hintText: 'ابحث عن أنمي أو فيلم...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: const Color(0xff151a25),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    ),
  );

  Widget heroCard(Anime a) => GestureDetector(
    onTap: () => openAnime(a),
    child: Container(
      height: 240,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: const Color(0xff151a25),
        image: a.image.isEmpty ? null : DecorationImage(
          image: NetworkImage(a.image), fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(.35), BlendMode.darken),
        ),
      ),
      child: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    ),
  );

  Widget section(String title, List<Anime> list) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
      SizedBox(
        height: 285,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          itemBuilder: (_, i) => poster(list[i]),
        ),
      ),
    ],
  );

  Widget gridPage(String title, List<Anime> list) => Column(
    children: [
      Padding(padding: const EdgeInsets.all(20),
        child: Align(alignment: Alignment.centerLeft,
          child: Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: searchBox()),
      Expanded(child: list.isEmpty ? const Center(child: Text('لا توجد نتائج')) :
        GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 18, childAspectRatio: .61,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => poster(list[i]),
        )),
    ],
  );

  Widget favoritePage() {
    final all = [...anime, ...movies].where((a) => favorites.contains(a.id)).toList();
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(20), child: Align(
          alignment: Alignment.centerLeft,
          child: Text('❤️ المفضلة', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        )),
        Expanded(child: all.isEmpty ? const Center(child: Text('لا توجد مفضلات')) :
          GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 18, childAspectRatio: .61,
            ),
            itemCount: all.length,
            itemBuilder: (_, i) => poster(all[i]),
          )),
      ],
    );
  }

  Widget poster(Anime a) => GestureDetector(
    onTap: () => openAnime(a),
    child: Container(
      width: 165,
      margin: const EdgeInsets.only(right: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: a.image.isEmpty ? Container(color: const Color(0xff151a25)) :
              Image.network(a.image, width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xff151a25),
                  child: const Icon(Icons.broken_image))),
          ),
          Positioned(top: 6, right: 6, child: CircleAvatar(
            backgroundColor: Colors.black54,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => toggleFavorite(a.id),
              icon: Icon(favorites.contains(a.id) ? Icons.favorite : Icons.favorite_border,
                color: favorites.contains(a.id) ? Colors.red : Colors.white),
            ),
          )),
        ])),
        const SizedBox(height: 7),
        Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(a.score == null ? a.type : '⭐ ${a.score}', style: const TextStyle(color: Colors.white54)),
      ]),
  );
}

class DetailsPage extends StatefulWidget {
  final Anime anime;
  final bool favorite;
  final List<Episode> episodes;
  final VoidCallback onFavorite;
  final Future<void> Function(List<Episode>) onEpisodesChanged;

  const DetailsPage({
    super.key, required this.anime, required this.favorite, required this.episodes,
    required this.onFavorite, required this.onEpisodesChanged,
  });

  @override State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late List<Episode> eps;

  @override void initState() { super.initState(); eps = [...widget.episodes]; }

  Future<void> admin() async {
    final result = await Navigator.push<List<Episode>>(context, MaterialPageRoute(
      builder: (_) => EpisodeAdmin(anime: widget.anime, episodes: eps),
    ));
    if (result != null) {
      setState(() => eps = result);
      await widget.onEpisodesChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = <int, List<Episode>>{};
    for (final e in eps) seasons.putIfAbsent(e.season, () => []).add(e);
    for (final l in seasons.values) l.sort((a,b) => a.number.compareTo(b.number));

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 330, pinned: true,
          actions: [
            IconButton(onPressed: widget.onFavorite,
              icon: Icon(widget.favorite ? Icons.favorite : Icons.favorite_border,
                color: widget.favorite ? Colors.red : null)),
            IconButton(onPressed: admin, icon: const Icon(Icons.admin_panel_settings)),
          ],
          flexibleSpace: FlexibleSpaceBar(
            title: Text(widget.anime.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            background: widget.anime.image.isEmpty ? null : Image.network(widget.anime.image, fit: BoxFit.cover),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              Chip(label: Text(widget.anime.type)),
              if (widget.anime.score != null) Chip(label: Text('⭐ ${widget.anime.score}')),
              if (widget.anime.episodes != null) Chip(label: Text('${widget.anime.episodes} حلقة')),
            ]),
            const SizedBox(height: 14),
            const Text('الوصف', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.anime.synopsis, style: const TextStyle(color: Colors.white70, height: 1.6)),
            const SizedBox(height: 24),
            if (seasons.isEmpty) Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xff151a25), borderRadius: BorderRadius.circular(16)),
              child: const Text('لا توجد حلقات مضافة. أضف روابط HLS المرخصة من زر الإدارة.'),
            ),
            ...seasons.entries.map((entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                Text('الموسم ${entry.key}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ...entry.value.asMap().entries.map((x) {
                  final i = x.key;
                  final e = x.value;
                  final next = i + 1 < entry.value.length ? entry.value[i + 1] : null;
                  return Card(child: ListTile(
                    leading: CircleAvatar(child: Text('${e.number}')),
                    title: Text(e.title),
                    subtitle: const Text('مشاهدة داخل التطبيق'),
                    trailing: const Icon(Icons.play_circle_fill),
                    onTap: e.url.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlayerPage(
                        title: '${widget.anime.title} - ${e.title}',
                        url: e.url,
                        nextEpisode: next,
                      ),
                    )),
                  ));
                }),
              ],
            )),
          ]),
        )),
      ]),
    );
  }
}

class EpisodeAdmin extends StatefulWidget {
  final Anime anime;
  final List<Episode> episodes;
  const EpisodeAdmin({super.key, required this.anime, required this.episodes});
  @override State<EpisodeAdmin> createState() => _EpisodeAdminState();
}

class _EpisodeAdminState extends State<EpisodeAdmin> {
  late List<Episode> list;
  final season = TextEditingController(text: '1');
  final number = TextEditingController(text: '1');
  final title = TextEditingController();
  final url = TextEditingController();

  @override void initState() { super.initState(); list = [...widget.episodes]; }
  @override void dispose() { season.dispose(); number.dispose(); title.dispose(); url.dispose(); super.dispose(); }

  void add() {
    final s = int.tryParse(season.text), n = int.tryParse(number.text), u = url.text.trim();
    if (s == null || n == null || u.isEmpty || (!u.startsWith('http://') && !u.startsWith('https://'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الموسم ورقم الحلقة ورابط HTTP/HTTPS.')));
      return;
    }
    setState(() {
      list.add(Episode(season: s, number: n, title: title.text.trim().isEmpty ? 'الحلقة $n' : title.text.trim(), url: u));
      list.sort((a,b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
      title.clear(); url.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة الحلقات'),
      actions: [IconButton(onPressed: () => Navigator.pop(context, list), icon: const Icon(Icons.check))]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.anime.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 15),
      TextField(controller: season, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الموسم', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رقم الحلقة', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الحلقة', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط HLS (.m3u8)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('إضافة')),
      const SizedBox(height: 20),
      ...list.asMap().entries.map((x) => Card(child: ListTile(
        leading: CircleAvatar(child: Text('${x.value.number}')),
        title: Text('م${x.value.season} - ${x.value.title}'),
        subtitle: Text(x.value.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => list.removeAt(x.key))),
      ))),
    ]),
  );
}

class PlayerPage extends StatefulWidget {
  final String title, url;
  final Episode? nextEpisode;
  const PlayerPage({super.key, required this.title, required this.url, this.nextEpisode});
  @override State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? c;
  String? error;

  @override void initState() { super.initState(); init(); }

  Future<void> init() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      c = controller;
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تشغيل الفيديو. تحقق من الرابط والخادم.');
    }
  }

  @override void dispose() { c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Scaffold(appBar: AppBar(title: Text(widget.title)),
      body: Center(child: Padding(padding: const EdgeInsets.all(25), child: Text(error!, textAlign: TextAlign.center))));
    final controller = c;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: Colors.black,
      body: controller == null || !controller.value.isInitialized
        ? const Center(child: CircularProgressIndicator())
        : ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (_, v, __) {
            final duration = v.duration.inMilliseconds.toDouble().clamp(1, double.infinity);
            final position = v.position.inMilliseconds.toDouble().clamp(0, duration);
            return Center(child: SingleChildScrollView(child: Column(
              children: [
                AspectRatio(aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16/9, child: VideoPlayer(controller)),
                Slider(value: position, min: 0, max: duration, onChanged: (x) => controller.seekTo(Duration(milliseconds: x.round()))),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(icon: const Icon(Icons.replay_10, size: 35), onPressed: () {
                    final x = v.position - const Duration(seconds: 10);
                    controller.seekTo(x.isNegative ? Duration.zero : x);
                  }),
                  IconButton(icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 55),
                    onPressed: () => v.isPlaying ? controller.pause() : controller.play()),
                  IconButton(icon: const Icon(Icons.forward_10, size: 35), onPressed: () {
                    final x = v.position + const Duration(seconds: 10);
                    controller.seekTo(x > v.duration ? v.duration : x);
                  }),
                ]),
                if (widget.nextEpisode != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => PlayerPage(
                          title: widget.nextEpisode!.title,
                          url: widget.nextEpisode!.url,
                        ),
                      )),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('الحلقة التالية'),
                    ),
                  ),
              ],
            )));
          },
        ),
    );
  }
}
