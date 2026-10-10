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
        for (var i = 0; i < 20; i++) figure('$i.jpg', 'Fujifilm X-M5'),
      ].join();
      expect(parseWeeklyPhotos(article, document(html)), hasLength(12));
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
      expect(find.text('작례는 원문에서 확인'), findsOneWidget);
      await tester.ensureVisible(find.text(weekly.recipe.name));
      await tester.tap(find.text(weekly.recipe.name));
      await tester.pumpAndSettle();
      expect(find.text('사진 다시 불러오기'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '라이브러리에 추가'));
      await tester.pumpAndSettle();
      expect(added.single.values, weekly.recipe.values);
      expect(tester.takeException(), isNull);
    },
  );
}
