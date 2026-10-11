import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/builtin_recipes.dart';
import 'package:fuji_san/domain/recipe.dart';
import 'package:fuji_san/recipe_photos.dart';
import 'package:fuji_san/recipe_references.dart';

final article = Uri.parse('https://fujixweekly.com/2022/11/27/sample-recipe/');
String document(String content, {Uri? source}) =>
    jsonEncode({'URL': (source ?? article).toString(), 'content': content});
String figure(String file, String caption, {String host = 'i0.wp.com'}) =>
    '<figure><img src="https://$host/fujixweekly.com/wp-content/uploads/$file?resize=799%2C534&amp;ssl=1">'
    '<figcaption>$caption</figcaption></figure>';

void main() {
  test(
    'only the exact recipe article supplies captioned reference photographs',
    () {
      final all = parseWeeklyPhotos(
        article,
        document(
          figure(
                'train.jpg',
                '<em>Short Train</em> &ndash; Fujifilm X-T5 &#8217;',
              ) +
              figure('train.jpg', 'Duplicate — Fujifilm X-T5') +
              figure('app.jpg', 'Download the app') +
              figure('unrelated.jpg', 'Fujifilm X-T5', host: 'example.com') +
              figure('street.jpg', 'Street&nbsp;— Fujifilm X-T5'),
        ),
      );
      expect(all, hasLength(2));
      expect(all.first.url.queryParameters['ssl'], '1');
      expect(all.first.caption, contains('Short Train'));
      expect(all.first.caption, contains('’'));
      expect(all.last.caption, 'Street — Fujifilm X-T5');
      expect(
        () => parseWeeklyPhotos(
          article,
          document(
            '',
            source: Uri.parse(
              'https://fujixweekly.com/2022/11/27/another-recipe/',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'captioned images are bounded, support single quotes and exclude third-party proxies',
    () {
      final html = [
        '<figure><img src=\'https://fujixweekly.files.wordpress.com/photo.jpg\'><figcaption>Fujifilm X-T5</figcaption></figure>',
        for (var i = 0; i < 110; i++) figure('$i.jpg', 'Fujifilm X-M5'),
      ].join();
      expect(parseWeeklyPhotos(article, document(html)), hasLength(100));
      expect(
        parseWeeklyPhotos(
          article,
          document(
            figure('photo.jpg', 'Fujifilm X-T5', host: 'i0.wp.com.evil.test'),
          ),
        ),
        isEmpty,
      );
    },
  );

  test('classic WordPress captions and modern figures retain article order', () {
    final html =
        '<div id="attachment_13792" class="wp-caption aligncenter">'
        '<a href="https://fujixweekly.com/full.jpg"><img data-src="https://example.com/ad.jpg" '
        'src="https://i0.wp.com/fujixweekly.com/wp-content/uploads/2020/03/reeds.jpg?resize=799%2C533&#038;ssl=1" /></a>'
        '<p class="wp-caption-text"><em>Winter Reeds</em> &#8211; Fujifilm X-T30</p></div>'
        '${figure('modern.jpg', 'Modern — Fujifilm X-T5')}'
        "<div class='aligncenter wp-caption'><img src='https://fujixweekly.files.wordpress.com/couch.jpg'>"
        "<p class='wp-caption-text'>Yellow Couch &amp; Pillow — Fujifilm X-T30</p></div>"
        '<div class="wp-caption"><img src="https://i0.wp.com/fujixweekly.com/app.jpg">'
        '<p class="wp-caption-text">Download the app</p></div>';
    final all = parseWeeklyPhotos(article, document(html));
    expect(all.map((p) => p.caption), [
      'Winter Reeds – Fujifilm X-T30',
      'Modern — Fujifilm X-T5',
      'Yellow Couch & Pillow — Fujifilm X-T30',
    ]);
    expect(all.first.url.queryParameters['ssl'], '1');
    expect(all.first.url.path, endsWith('/reeds.jpg'));
    expect(all.last.url.path, '/couch.jpg');
  });

  test(
    'Film Recipes excludes settings cards and recommendations, including legacy posts',
    () {
      final film = Uri.parse(
        'https://film.recipes/2023/12/27/123-123-year-end-story-mode/',
      );
      expect(hasRecipePhotos(film), isTrue);
      expect(recipePhotoEndpoint(film).path, contains('/sites/film.recipes/'));
      final modern = parseRecipePhotos(
        film,
        document(
          '<img src="/wp-content/uploads/settings.jpg" alt="123-123 film recipe">'
          '<img src="/wp-content/uploads/photo.jpg" alt="123-123 film recipe sample photo">'
          '<img src="https://i0.wp.com/film.recipes/wp-content/uploads/photo.jpg?resize=900" alt="123-123 film recipe sample photo">'
          '<h2>Similar Recipes</h2><img src="/wp-content/uploads/other.jpg" alt="Other film recipe sample photo">',
          source: film,
        ),
      );
      expect(modern, hasLength(1));
      expect(modern.single.url.path, endsWith('photo.jpg'));
      final legacy = parseRecipePhotos(
        film,
        document(
          '<figure><img class="wp-image-12" src="https://filmrecipes239715696.files.wordpress.com/old.jpg" alt=""><figcaption>Soft Autumn tones</figcaption></figure>'
          '<h2>Marcel&#8217;s other recipes</h2><figure><img class="wp-image-13" src="/unrelated.jpg"><figcaption>Another recipe</figcaption></figure>',
          source: film,
        ),
      );
      expect(legacy.single.caption, 'Soft Autumn tones');
    },
  );

  test(
    'Piot uses only owned gallery photos and checks exact article identity',
    () {
      final piot = Uri.parse(
        'https://piotrecipes.wordpress.com/barely-negative-x-trans-iv/',
      );
      final all = parseRecipePhotos(
        piot,
        document(
          '<img class="wp-image-1" src="https://piotrecipes.files.wordpress.com/gallery.jpg">'
          '<img class="wp-image-2" src="https://example.com/foreign.jpg">'
          '<img src="https://piotrecipes.files.wordpress.com/banner.jpg">',
          source: piot,
        ),
      );
      expect(all, hasLength(1));
      expect(
        () => parseRecipePhotos(piot, document('', source: article)),
        throwsFormatException,
      );
    },
  );

  test('unsupported article sources never make network requests', () async {
    var calls = 0;
    final repo = RecipePhotoRepository(
      fetch: (_) async {
        calls++;
        return '{}';
      },
    );
    for (final url in [
      'http://fujixweekly.com/2022/11/27/sample-recipe/',
      'https://fujixweekly.com/recipes/',
      'https://film.recipes/sample',
      'https://fujixweekly.com.evil.test/2022/11/27/sample-recipe/',
    ]) {
      expect(await repo.load(Uri.parse(url)), isEmpty);
    }
    expect(calls, 0);
    expect(weeklyPhotoEndpoint(article).host, 'public-api.wordpress.com');
    expect(
      weeklyPhotoEndpoint(article).queryParameters['fields'],
      'URL,content',
    );
  });

  test(
    'repeated requests share one fetch and failed photos can be retried',
    () async {
      var calls = 0;
      final repo = RecipePhotoRepository(
        fetch: (_) async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return document(figure('photo.jpg', 'Fujifilm X-T5'));
        },
      );
      await expectLater(repo.load(article), throwsStateError);
      repo.retry(article);
      final first = repo.load(article), second = repo.load(article);
      expect(identical(first, second), isTrue);
      expect(await first, hasLength(1));
      expect(calls, 2);
    },
  );

  test(
    'scrolling queues requests with at most three article downloads',
    () async {
      final pending = <Completer<String>>[];
      final repo = RecipePhotoRepository(
        fetch: (_) {
          final c = Completer<String>();
          pending.add(c);
          return c.future;
        },
      );
      final urls = List.generate(
        5,
        (i) => article.replace(path: '/2022/11/27/recipe-$i/'),
      );
      final work = [for (final url in urls) repo.load(url)];
      expect(pending, hasLength(3));
      pending[0].complete(document('', source: urls[0]));
      await work[0];
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(4));
      pending[1].complete(document('', source: urls[1]));
      await work[1];
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(5));
      for (var i = 2; i < pending.length; i++) {
        pending[i].complete(document('', source: urls[i]));
      }
      await Future.wait(work);
    },
  );

  final weekly = BuiltinRecipe(
    Recipe.fresh(),
    'Ritchie Roesch',
    'X-T5',
    'X-Trans V',
    article,
  );
  final other = BuiltinRecipe(
    Recipe.fresh(),
    'Another author',
    'X-M5',
    'X-Trans IV',
    Uri.parse('https://film.recipes/other/'),
  );
  final samples = [
    RecipePhoto(
      Uri.parse('https://i0.wp.com/fujixweekly.com/photo.jpg'),
      'Train — Fujifilm X-T5',
    ),
    RecipePhoto(
      Uri.parse('https://i0.wp.com/fujixweekly.com/street.jpg'),
      'Street — Fujifilm X-T5',
    ),
  ];
  Widget image(RecipePhoto photo) => ColoredBox(
    color: Colors.blueGrey,
    child: Center(child: Text(photo.caption)),
  );

  testWidgets(
    'photo catalog opens several reference photos and adds exact recipe values',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final added = <Recipe>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BuiltinCatalog(
            onAdd: (r) async => added.add(r),
            load: () async => [weekly, other],
            loadPhotos: (_) async => samples,
            imageBuilder: image,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecipePhotoThumbnail), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('카드 다음 작례'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.drag(
        find.byType(RecipePhotoThumbnail),
        const Offset(350, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.text(weekly.recipe.name).first);
      await tester.pumpAndSettle();
      expect(find.text('작례 1 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('다음 작례'));
      await tester.pumpAndSettle();
      expect(find.text('작례 2 / 2'), findsOneWidget);
      expect(find.text('원문 보기'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '라이브러리에 추가'));
      await tester.pumpAndSettle();
      expect(added.single.values, weekly.recipe.values);
      await tester.tap(find.widgetWithText(ChoiceChip, '설정 목록'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported cards open the original without making a photo request',
    (tester) async {
      var requests = 0, opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 240,
              child: RecipePhotoThumbnail(
                article: Uri.parse('https://www.youtube.com/watch?v=sample'),
                load: (_) async {
                  requests++;
                  return samples;
                },
                onRetry: () {},
                onOpenArticle: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.text('영상 원문에서 작례를 확인하세요.'), findsOneWidget);
      expect(find.text('사진 다시 불러오기'), findsNothing);
      await tester.tap(find.text('원문 보기'));
      expect(opened, 1);
    },
  );

  testWidgets('supported photo catalog includes Film Recipes by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final film = BuiltinRecipe(
      Recipe.fresh(),
      'Justin Gould',
      'X-S10',
      'X-Trans IV',
      Uri.parse('https://film.recipes/2023/12/27/123-123-year-end-story-mode/'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BuiltinCatalog(
          onAdd: (_) async {},
          load: () async => [weekly, film, other],
          loadPhotos: (_) async => samples,
          imageBuilder: image,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RecipePhotoThumbnail), findsNWidgets(2));
    expect(find.text('사진 © Film Recipes'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Fuji X Weekly만'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipePhotoThumbnail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card retry restores photos and navigation on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0, retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 240,
              child: RecipePhotoThumbnail(
                article: article,
                load: (_) async {
                  calls++;
                  if (calls == 1) {
                    throw StateError('temporary connection error');
                  }
                  return samples;
                },
                onRetry: () => retries++,
                imageBuilder: image,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('원문 연결에 실패했어요.'), findsOneWidget);
    await tester.tap(find.text('사진 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(retries, 1);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('카드 이전 작례'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing photos still allow recipe selection on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final added = <Recipe>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BuiltinCatalog(
            onAdd: (r) async => added.add(r),
            load: () async => [weekly],
            loadPhotos: (_) async => throw StateError('offline'),
            imageBuilder: image,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('원문 연결에 실패했어요.'), findsOneWidget);
      await tester.ensureVisible(find.text(weekly.recipe.name));
      await tester.tap(find.text(weekly.recipe.name));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(RecipePhotoGallery),
          matching: find.text('사진 다시 불러오기'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, '라이브러리에 추가'));
      await tester.pumpAndSettle();
      expect(added.single.values, weekly.recipe.values);
      expect(tester.takeException(), isNull);
    },
  );
}
