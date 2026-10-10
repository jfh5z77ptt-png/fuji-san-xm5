import 'dart:async';
import 'dart:convert';
import 'dart:io';

// References come from the exact public article linked by a bundled recipe.
// Neither photographs nor article bodies are bundled or saved to disk.
class RecipePhoto {
  const RecipePhoto(this.url, this.caption);
  final Uri url;
  final String caption;
}

bool hasWeeklyPhotos(Uri article) =>
    article.scheme == 'https' &&
    article.host == 'fujixweekly.com' &&
    RegExp(r'^/\d{4}/\d{2}/\d{2}/[^/]+/?$').hasMatch(article.path);

Uri weeklyPhotoEndpoint(Uri article) {
  if (!hasWeeklyPhotos(article)) {
    throw const FormatException('이 원문은 작례 사진 연결을 지원하지 않습니다.');
  }
  final slug = article.pathSegments.where((s) => s.isNotEmpty).last;
  return Uri.https(
    'public-api.wordpress.com',
    '/rest/v1.1/sites/fujixweekly.com/posts/slug:$slug',
    {'fields': 'URL,content'},
  );
}

String _plainText(String text) => text
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAllMapped(
      RegExp(
        r'&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp|ndash|mdash|lsquo|rsquo|ldquo|rdquo);',
        caseSensitive: false,
      ),
      (m) {
        final entity = m[1]!;
        if (entity.startsWith('#')) {
          final hex = entity.toLowerCase().startsWith('#x');
          final n = int.tryParse(
            entity.substring(hex ? 2 : 1),
            radix: hex ? 16 : 10,
          );
          if (n != null &&
              n > 0 &&
              n <= 0x10ffff &&
              !(n >= 0xd800 && n <= 0xdfff)) {
            return String.fromCharCode(n);
          }
          return '';
        }
        return const {
          'amp': '&',
          'quot': '"',
          'apos': "'",
          'lt': '<',
          'gt': '>',
          'nbsp': ' ',
          'ndash': '–',
          'mdash': '—',
          'lsquo': '‘',
          'rsquo': '’',
          'ldquo': '“',
          'rdquo': '”',
        }[entity.toLowerCase()]!;
      },
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? _attribute(String tag, String name) {
  final m = RegExp(
    '(?:^|\\s)$name\\s*=\\s*(["\u0027])(.*?)\\1',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(tag);
  return m == null ? null : _plainText(m[2]!);
}

bool _photoHost(Uri url) =>
    url.scheme == 'https' &&
    (url.host == 'fujixweekly.com' ||
        url.host == 'fujixweekly.files.wordpress.com' ||
        (RegExp(r'^i[0-3]\.wp\.com$').hasMatch(url.host) &&
            (url.path.startsWith('/fujixweekly.com/') ||
                url.path.startsWith('/fujixweekly.files.wordpress.com/'))));

List<RecipePhoto> parseWeeklyPhotos(Uri article, String body) {
  if (!hasWeeklyPhotos(article)) {
    return const [];
  }
  final json = jsonDecode(body) as Map<String, dynamic>;
  final returned = Uri.tryParse(json['URL'] as String? ?? '');
  String canonical(Uri u) =>
      '${u.host}${u.path.replaceFirst(RegExp(r'/$'), '')}';
  if (returned == null ||
      returned.scheme != 'https' ||
      canonical(returned) != canonical(article)) {
    throw const FormatException('원문 주소와 사진 출처가 일치하지 않습니다.');
  }
  final content = json['content'] as String? ?? '';
  final photos = <RecipePhoto>[];
  final seen = <String>{};
  // WordPress uses figures in newer posts and wp-caption divs in older posts.
  // Keep both in article order, excluding uncaptioned affiliate/app banners.
  for (final container in RegExp(
    r'<figure\b[^>]*>(.*?)</figure>|<div\b[^>]*\bclass\s*=\s*["\x27][^"\x27]*\bwp-caption\b[^"\x27]*["\x27][^>]*>(.*?)</div>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(content)) {
    final html = container[1] ?? container[2]!;
    final captionTag = RegExp(
      r'<figcaption\b[^>]*>(.*?)</figcaption>|<p\b[^>]*\bclass\s*=\s*["\x27][^"\x27]*\bwp-caption-text\b[^"\x27]*["\x27][^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final caption = _plainText(captionTag?[1] ?? captionTag?[2] ?? '');
    if (!RegExp(r'\bFujifilm\b', caseSensitive: false).hasMatch(caption)) {
      continue;
    }
    final image = RegExp(
      r'<img\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (image == null) {
      continue;
    }
    final url = Uri.tryParse(_attribute(image[0]!, 'src') ?? '');
    if (url == null ||
        !_photoHost(url) ||
        !seen.add('${url.host}${url.path}')) {
      continue;
    }
    photos.add(RecipePhoto(url, caption));
    if (photos.length == 100) {
      break;
    }
  }
  return List.unmodifiable(photos);
}

class RecipePhotoRepository {
  RecipePhotoRepository({Future<String> Function(Uri)? fetch})
    : _fetch = fetch ?? _download;
  final Future<String> Function(Uri) _fetch;
  final _cache = <String, Future<List<RecipePhoto>>>{};
  final _waiting = <Completer<void>>[];
  int _active = 0;

  Future<List<RecipePhoto>> load(Uri article) {
    if (!hasWeeklyPhotos(article)) {
      return Future.value(const []);
    }
    final key = article.toString();
    return _cache.putIfAbsent(key, () => _load(article));
  }

  void retry(Uri article) => _cache.remove(article.toString());

  Future<List<RecipePhoto>> _load(Uri article) async {
    if (_active >= 3) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return parseWeeklyPhotos(
        article,
        await _fetch(weeklyPhotoEndpoint(article)),
      );
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  static Future<String> _download(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.getUrl(url);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'FujiSanRecipeReferences/1.0',
        );
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('사진 출처에 연결하지 못했습니다 (${response.statusCode}).');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2000000) {
            throw const FormatException('사진 출처 응답이 너무 큽니다.');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}
