import 'dart:ui' show PointerDeviceKind;

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

class RecipePhotoThumbnail extends StatefulWidget {
  const RecipePhotoThumbnail({
    super.key,
    required this.article,
    required this.load,
    required this.onRetry,
    this.imageBuilder,
    this.onOpenArticle,
  });
  final VoidCallback? onOpenArticle;
  final Uri article;
  final Future<List<RecipePhoto>> Function(Uri) load;
  final VoidCallback onRetry;
  final ReferenceImageBuilder? imageBuilder;

  @override
  State<RecipePhotoThumbnail> createState() => _RecipePhotoThumbnailState();
}

class _RecipePhotoThumbnailState extends State<RecipePhotoThumbnail> {
  late Future<List<RecipePhoto>> photos = hasRecipePhotos(widget.article)
      ? widget.load(widget.article)
      : Future.value(const []);
  final pages = PageController();
  int index = 0;

  @override
  void didUpdateWidget(RecipePhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article != widget.article) {
      photos = hasRecipePhotos(widget.article)
          ? widget.load(widget.article)
          : Future.value(const []);
      index = 0;
      if (pages.hasClients) pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void retry() {
    widget.onRetry();
    setState(() {
      index = 0;
      photos = widget.load(widget.article);
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff0f1f3),
    child: FutureBuilder<List<RecipePhoto>>(
      future: photos,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final all = snapshot.data ?? const <RecipePhoto>[];
        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_outlined, color: Colors.black38),
                const SizedBox(height: 6),
                Text(
                  !hasRecipePhotos(widget.article)
                      ? unsupportedPhotoMessage(widget.article)
                      : snapshot.hasError
                      ? '원문 연결에 실패했어요.'
                      : '이 원문에서 작례 사진을 찾지 못했어요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                if (widget.onOpenArticle != null)
                  TextButton.icon(
                    onPressed: widget.onOpenArticle,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('원문 보기'),
                  ),
                if (hasRecipePhotos(widget.article))
                  TextButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('사진 다시 불러오기'),
                  ),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
              ),
              child: PageView.builder(
                controller: pages,
                itemCount: all.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (context, i) =>
                    (widget.imageBuilder ??
                    (p) => RecipeReferenceImage(photo: p))(all[i]),
              ),
            ),
            if (all.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton.filledTonal(
                  tooltip: '카드 이전 작례',
                  onPressed: index == 0
                      ? null
                      : () => pages.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filledTonal(
                  tooltip: '카드 다음 작례',
                  onPressed: index == all.length - 1
                      ? null
                      : () => pages.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ],
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    child: Text(
                      '${index + 1} / ${all.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
              Text(
                snapshot.hasError
                    ? '원문 연결에 실패했어요. 원문 보기로 확인할 수 있어요.'
                    : '이 원문에서 작례 사진을 찾지 못했어요. 원문 보기로 확인할 수 있어요.',
              ),
              TextButton.icon(
                onPressed: () {
                  widget.onRetry();
                  setState(() {
                    index = 0;
                    photos = widget.load(widget.article);
                  });
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
          Text(
            '사진 © ${recipePhotoSource(widget.article)} · 원문 저자\n원문의 작례입니다. 촬영 조건과 기종에 따라 결과는 달라질 수 있어요.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
