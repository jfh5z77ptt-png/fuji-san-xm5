import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain/recipe.dart';
import 'film_icon.dart';
import 'recipe_photos.dart';
import 'recipe_references.dart';

// A published recipe bundled with the app (assets/builtin_recipes.json, built by
// tool/build_builtin_recipes.py). It only enters the library when the user adds it.
class BuiltinRecipe {
  BuiltinRecipe(this.recipe, this.creator, this.camera, this.sensor, this.url);
  final Recipe recipe;
  final String creator, camera, sensor;
  final Uri url;
}

List<BuiltinRecipe> parseBuiltinRecipes(String source) {
  final json = jsonDecode(source) as Map<String, dynamic>;
  if (json['format'] != 'fuji-san-builtin' || json['version'] != 1) {
    throw const FormatException('내장 레시피 파일 형식이 아닙니다.');
  }
  final list = (json['recipes'] as List).cast<Map<String, dynamic>>();
  return [
    for (var i = 0; i < list.length; i++)
      BuiltinRecipe(
        Recipe.fromJson({...list[i], 'id': 'builtin-$i'}),
        list[i]['creator'] as String,
        list[i]['camera'] as String,
        list[i]['sensor'] as String,
        Uri.parse(list[i]['url'] as String),
      ),
  ];
}

Future<List<BuiltinRecipe>> loadBuiltinRecipes() async => parseBuiltinRecipes(
  await rootBundle.loadString('assets/builtin_recipes.json'),
);

class BuiltinCatalog extends StatefulWidget {
  const BuiltinCatalog({
    super.key,
    required this.onAdd,
    this.load,
    this.loadPhotos,
    this.imageBuilder,
    this.showPhotosInitially = true,
  });
  final Future<void> Function(Recipe recipe) onAdd;
  final Future<List<BuiltinRecipe>> Function()? load;
  final Future<List<RecipePhoto>> Function(Uri)? loadPhotos;
  final ReferenceImageBuilder? imageBuilder;
  final bool showPhotosInitially;
  @override
  State<BuiltinCatalog> createState() => _BuiltinCatalogState();
}

class _BuiltinCatalogState extends State<BuiltinCatalog> {
  late final Future<List<BuiltinRecipe>> items =
      (widget.load ?? loadBuiltinRecipes)();
  final added = <String>{};
  String query = '';
  int? film;
  final dr = <int>{}, cc = <int>{}, fx = <int>{};
  int sort = 0;
  bool descending = false;
  late bool photoView = widget.showPhotosInitially;
  bool weeklyOnly = false;
  late bool photosOnly = widget.showPhotosInitially;
  final photos = RecipePhotoRepository();

  Future<List<RecipePhoto>> loadPhotos(Uri uri) =>
      (widget.loadPhotos ?? photos.load)(uri);

  void notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> add(BuiltinRecipe item) async {
    try {
      await widget.onAdd(item.recipe);
      if (mounted) setState(() => added.add(item.recipe.id));
      notify('${item.recipe.name} 라이브러리에 추가됨');
    } catch (e) {
      notify('추가하지 못했습니다: $e');
    }
  }

  Future<void> openArticle(BuiltinRecipe item) async {
    try {
      if (!await launchUrl(item.url, mode: LaunchMode.externalApplication)) {
        notify('원문을 열 수 없습니다: ${item.url}');
      }
    } catch (e) {
      notify('원문을 열 수 없습니다: $e');
    }
  }

  Future<void> details(BuiltinRecipe item) async {
    final values = item.recipe.values;
    final wanted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.recipe.name),
        content: SizedBox(
          width: hasRecipePhotos(item.url) ? 640 : 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.creator} · ${item.camera} (${item.sensor})',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (hasRecipePhotos(item.url))
                  RecipePhotoGallery(
                    article: item.url,
                    load: loadPhotos,
                    onRetry: () => photos.retry(item.url),
                    imageBuilder: widget.imageBuilder,
                  ),
                for (final s in settings)
                  if (applicable(s.id, values))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(s.label)),
                          Text(
                            s.display(values[s.id]!),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 12),
                Text(
                  '${item.sensor}용으로 공개된 설정값입니다. 촬영 기종에 따라 결과가 다를 수 있어요. 노출 보정·ISO 권장값과 전체 작례는 원문에서 확인하세요.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => openArticle(item),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('원문 보기'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('라이브러리에 추가'),
          ),
        ],
      ),
    );
    if (wanted == true) await add(item);
  }

  // Filter variants (ACROS + Y, Monochrome + R…) share their base film's tab.
  static int group(int film) => film >= 12 && film <= 15
      ? 12
      : film >= 6 && film <= 9
      ? 6
      : film;
  static const sorts = <int, String>{
    0: '이름',
    0xd19d: '하이라이트',
    0xd19e: '섀도',
    0xd19f: '색농도',
    0xd1a0: '샤프니스',
    0xd1a2: '클래리티',
    0xd19a: 'WB Shift Red',
    0xd19b: 'WB Shift Blue',
  };
  // -1 stands for "D-Range priority on", where the DR value does not apply.
  static int drKey(Map<int, int> v) => v[0xd191] != 0 ? -1 : v[0xd190]!;
  static String drLabel(int key) => key < 0
      ? 'DR 우선'
      : key == 65535
      ? 'DR Auto'
      : 'DR$key';

  static String signed(int id, Map<int, int> v) {
    final setting = settings.firstWhere((s) => s.id == id);
    final n = v[id]! / setting.scale;
    final text = n == n.roundToDouble() ? '${n.toInt()}' : '$n';
    return n > 0 ? '+$text' : text;
  }

  static String summary(Map<int, int> v) {
    final wb = settings.firstWhere((s) => s.id == 0xd199);
    return [
      drLabel(drKey(v)),
      if (applicable(0xd19d, v)) 'H ${signed(0xd19d, v)}',
      if (applicable(0xd19e, v)) 'S ${signed(0xd19e, v)}',
      if (applicable(0xd19f, v)) 'Color ${signed(0xd19f, v)}',
      'Sharp ${signed(0xd1a0, v)}',
      'Clarity ${signed(0xd1a2, v)}',
      'CC ${effects[v[0xd196]]}',
      'FX Blue ${effects[v[0xd197]]}',
      'WB ${v[0xd199] == 32775 ? '${v[0xd19c]}K' : wb.display(v[0xd199]!)} '
          'R${signed(0xd19a, v)} B${signed(0xd19b, v)}',
    ].join(' · ');
  }

  bool matches(BuiltinRecipe b, {bool tab = true}) {
    final v = b.recipe.values;
    return (!photoView || !photosOnly || hasRecipePhotos(b.url)) &&
        (!weeklyOnly || hasWeeklyPhotos(b.url)) &&
        (!tab || film == null || group(v[0xd192]!) == film) &&
        (dr.isEmpty || dr.contains(drKey(v))) &&
        (cc.isEmpty || cc.contains(v[0xd196])) &&
        (fx.isEmpty || fx.contains(v[0xd197])) &&
        '${b.recipe.name} ${b.recipe.film} ${b.creator}'.toLowerCase().contains(
          query.toLowerCase(),
        );
  }

  int compare(BuiltinRecipe a, BuiltinRecipe b) {
    final byName = a.recipe.name.toLowerCase().compareTo(
      b.recipe.name.toLowerCase(),
    );
    if (sort == 0) return descending ? -byName : byName;
    // Recipes where the setting does not apply stay at the end either way.
    final x = applicable(sort, a.recipe.values) ? a.recipe.values[sort] : null;
    final y = applicable(sort, b.recipe.values) ? b.recipe.values[sort] : null;
    if (x == null || y == null) {
      return x == y
          ? byName
          : x == null
          ? 1
          : -1;
    }
    final byValue = descending ? y.compareTo(x) : x.compareTo(y);
    return byValue != 0 ? byValue : byName;
  }

  Widget tags(
    String title,
    Set<int> selected,
    List<int> options,
    String Function(int) label,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        for (final option in options)
          FilterChip(
            label: Text(label(option)),
            labelStyle: const TextStyle(fontSize: 12),
            visualDensity: VisualDensity.compact,
            selected: selected.contains(option),
            onSelected: (on) => setState(
              () => on ? selected.add(option) : selected.remove(option),
            ),
          ),
      ],
    ),
  );

  Widget controls(List<BuiltinRecipe> all, int shown) {
    List<int> present(int Function(Map<int, int>) key) =>
        (all.map((b) => key(b.recipe.values)).toSet().toList()..sort());
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('작례 사진'),
                selected: photoView,
                onSelected: (_) => setState(() {
                  photoView = true;
                  photosOnly = true;
                }),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.list, size: 18),
                label: const Text('설정 목록'),
                selected: !photoView,
                onSelected: (_) => setState(() {
                  photoView = false;
                  weeklyOnly = false;
                }),
              ),
              if (photoView)
                FilterChip(
                  label: const Text('작례 지원 원문만'),
                  selected: photosOnly,
                  onSelected: (v) => setState(() => photosOnly = v),
                ),
              FilterChip(
                label: const Text('Fuji X Weekly만'),
                selected: weeklyOnly,
                onSelected: (v) => setState(() => weeklyOnly = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          tags('DR', dr, present(drKey), drLabel),
          tags(
            '컬러 크롬',
            cc,
            present((v) => v[0xd196]!),
            (o) => 'CC ${effects[o]}',
          ),
          tags(
            'FX Blue',
            fx,
            present((v) => v[0xd197]!),
            (o) => 'FX Blue ${effects[o]}',
          ),
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text(
                  '정렬',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              DropdownButton<int>(
                key: const ValueKey('builtin-sort'),
                value: sort,
                isDense: true,
                items: [
                  for (final e in sorts.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => sort = v!),
              ),
              IconButton(
                tooltip: descending ? '내림차순' : '오름차순',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  descending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 18,
                ),
                onPressed: () => setState(() => descending = !descending),
              ),
              const Spacer(),
              if (dr.isNotEmpty || cc.isNotEmpty || fx.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    dr.clear();
                    cc.clear();
                    fx.clear();
                  }),
                  child: const Text('필터 지우기'),
                ),
            ],
          ),
          Text(
            '$shown개 · ${photoView ? '카드의 화살표나 좌우 드래그로 작례를 넘겨 보세요. 사진을 누르면 설정을 확인할 수 있어요. 사진은 인터넷으로 원문에서 불러옵니다. ' : '눌러서 설정과 원문을 확인하고 라이브러리에 추가하세요. '}'
            '목록 출처: Fujifilm Film Simulation Recipes Database (Henri-Pierre Chavaz)',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<BuiltinRecipe>>(
    future: items,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('내장 레시피')),
          body: Center(
            child: snapshot.hasError
                ? Text('내장 레시피를 읽지 못했습니다: ${snapshot.error}')
                : const CircularProgressIndicator(),
          ),
        );
      }
      final all = snapshot.data!;
      // Tab counts follow the search and tag filters, not the selected tab.
      final counts = <int, int>{};
      for (final b in all.where((b) => matches(b, tab: false))) {
        final g = group(b.recipe.values[0xd192]!);
        counts[g] = (counts[g] ?? 0) + 1;
      }
      final films = [
        for (final id in filmNames.keys)
          if (all.any((b) => group(b.recipe.values[0xd192]!) == id)) id,
      ];
      final shown = all.where(matches).toList()..sort(compare);
      return DefaultTabController(
        length: films.length + 1,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('내장 레시피'),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (i) => setState(() => film = i == 0 ? null : films[i - 1]),
              tabs: [
                Tab(text: '전체 ${counts.values.fold(0, (a, b) => a + b)}'),
                for (final id in films)
                  Tab(text: '${filmNames[id]} ${counts[id] ?? 0}'),
              ],
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: photoView ? 1120 : 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '이름, 필름 시뮬레이션 또는 제작자 검색',
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 3
                            : constraints.maxWidth >= 540
                            ? 2
                            : 1;
                        final cardWidth =
                            (constraints.maxWidth - 24 - (columns - 1) * 12) /
                            columns;
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: controls(all, shown.length),
                            ),
                            if (shown.isEmpty)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    '조건에 맞는 레시피가 없어요. 검색이나 필터를 바꿔 보세요.',
                                  ),
                                ),
                              ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              sliver: photoView
                                  ? SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: columns,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                            mainAxisExtent:
                                                cardWidth * 2 / 3 +
                                                130 *
                                                    MediaQuery.textScalerOf(
                                                      context,
                                                    ).scale(1),
                                          ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) => photoCard(shown[i]),
                                        childCount: shown.length,
                                      ),
                                    )
                                  : SliverList.builder(
                                      itemCount: shown.length,
                                      itemBuilder: (context, i) =>
                                          recipeRow(shown[i]),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget recipeRow(BuiltinRecipe item) {
    final done = added.contains(item.recipe.id);
    return ListTile(
      onTap: () => details(item),
      leading: FilmIcon(item.recipe.values[0xd192]!, size: 26),
      title: Text(item.recipe.name),
      subtitle: Text(
        '${item.recipe.film} · ${item.creator} · ${item.camera}\n${summary(item.recipe.values)}',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: done ? '한 번 더 추가' : '라이브러리에 추가',
        icon: Icon(done ? Icons.check : Icons.add),
        onPressed: () => add(item),
      ),
    );
  }

  Widget photoCard(BuiltinRecipe item) {
    final done = added.contains(item.recipe.id);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => details(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RecipePhotoThumbnail(
                key: ValueKey(item.recipe.id),
                onRetry: () => photos.retry(item.url),
                onOpenArticle: () => openArticle(item),
                article: item.url,
                load: loadPhotos,
                imageBuilder: widget.imageBuilder,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.recipe.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.recipe.film} · ${item.camera}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasRecipePhotos(item.url)
                              ? '사진 © ${recipePhotoSource(item.url)}'
                              : item.creator,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: done ? '한 번 더 추가' : '라이브러리에 추가',
                        icon: Icon(done ? Icons.check : Icons.add),
                        onPressed: () => add(item),
                      ),
                    ],
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
