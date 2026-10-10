import 'package:flutter/material.dart';
import 'recipe_references.dart';

typedef ReferenceImageBuilder = Widget Function(RecipePhoto photo);

class RecipeReferenceImage extends StatelessWidget {
  const RecipeReferenceImage({super.key, required this.photo});
  final RecipePhoto photo;

  @override
  Widget build(BuildContext context) => Image.network(
    photo.url.toString(),
    fit: BoxFit.contain,
    semanticLabel: photo.caption,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    errorBuilder: (context, error, stack) => const Center(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '사진을 불러오지 못했어요. 원문 보기로 확인하세요.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class RecipePhotoThumbnail extends StatelessWidget {
  const RecipePhotoThumbnail({
    super.key,
    required this.article,
    required this.load,
    this.imageBuilder,
  });
  final Uri article;
  final Future<List<RecipePhoto>> Function(Uri) load;
  final ReferenceImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff0f1f3),
    child: FutureBuilder<List<RecipePhoto>>(
      future: load(article),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final photos = snapshot.data ?? const <RecipePhoto>[];
        if (photos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_outlined, color: Colors.black38),
                SizedBox(height: 6),
                Text('작례는 원문에서 확인', style: TextStyle(color: Colors.black54)),
              ],
            ),
          );
        }
        return (imageBuilder ?? (p) => RecipeReferenceImage(photo: p))(
          photos.first,
        );
      },
    ),
  );
}

class RecipePhotoGallery extends StatefulWidget {
  const RecipePhotoGallery({
    super.key,
    required this.article,
    required this.load,
    required this.onRetry,
    this.imageBuilder,
  });
  final Uri article;
  final Future<List<RecipePhoto>> Function(Uri) load;
  final VoidCallback onRetry;
  final ReferenceImageBuilder? imageBuilder;

  @override
  State<RecipePhotoGallery> createState() => _RecipePhotoGalleryState();
}

class _RecipePhotoGalleryState extends State<RecipePhotoGallery> {
  late Future<List<RecipePhoto>> photos = widget.load(widget.article);
  final pages = PageController();
  int index = 0;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> enlarge(RecipePhoto photo) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 1000,
        height: MediaQuery.sizeOf(ctx).height * .8,
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: SizedBox.expand(
                  child:
                      (widget.imageBuilder ??
                      (p) => RecipeReferenceImage(photo: p))(photo),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(photo.caption),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RecipePhoto>>(
    future: photos,
    builder: (context, snapshot) {
      final all = snapshot.data ?? const <RecipePhoto>[];
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (all.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const Text('작례 사진을 불러오지 못했어요. 원문 보기로 확인할 수 있어요.'),
              TextButton.icon(
                onPressed: () {
                  widget.onRetry();
                  setState(() => photos = widget.load(widget.article));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('사진 다시 불러오기'),
              ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: ColoredBox(
              color: const Color(0xfff0f1f3),
              child: PageView.builder(
                controller: pages,
                itemCount: all.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (context, i) =>
                    (widget.imageBuilder ??
                    (p) => RecipeReferenceImage(photo: p))(all[i]),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '이전 작례',
                onPressed: index == 0
                    ? null
                    : () => pages.previousPage(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('작례 ${index + 1} / ${all.length}'),
              IconButton(
                tooltip: '다음 작례',
                onPressed: index == all.length - 1
                    ? null
                    : () => pages.nextPage(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: '작례 크게 보기',
                onPressed: () => enlarge(all[index]),
                icon: const Icon(Icons.zoom_in),
              ),
            ],
          ),
          Text(all[index].caption, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
            '사진 © Fuji X Weekly · 원문 저자\n원문의 작례입니다. 촬영 조건과 기종에 따라 결과는 달라질 수 있어요.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
