/// @intent 첨부 사진 목록(Supabase Storage CDN 및 Base64)을 렌더링하고 전체화면 확대 뷰어를 제공하는 위젯
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'dart:convert';
import 'package:flutter/material.dart';

class PhotoGalleryView extends StatelessWidget {
  final List<String> photos;
  final double? singleImageHeight;

  const PhotoGalleryView({
    super.key,
    required this.photos,
    this.singleImageHeight = 160,
  });

  static Widget buildImageWidget(String src, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (src.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFFF1F5F9),
        child: const Icon(Icons.image_not_supported, size: 24, color: Color(0xFF94A3B8)),
      );
    }

    if (src.startsWith('data:image')) {
      try {
        final commaIdx = src.indexOf(',');
        final base64String = commaIdx != -1 ? src.substring(commaIdx + 1) : src;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => Container(
            width: width,
            height: height,
            color: const Color(0xFFF1F5F9),
            child: const Icon(Icons.broken_image, size: 24, color: Color(0xFF94A3B8)),
          ),
        );
      } catch (_) {
        return Container(
          width: width,
          height: height,
          color: const Color(0xFFF1F5F9),
          child: const Icon(Icons.broken_image, size: 24, color: Color(0xFF94A3B8)),
        );
      }
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: const Color(0xFFF1F5F9),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: const Color(0xFFF1F5F9),
          child: const Center(
            child: Icon(Icons.broken_image, size: 24, color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: const Icon(Icons.image, size: 24, color: Color(0xFF94A3B8)),
    );
  }

  /// 사진 전체화면 확대 및 복수 사진 가로 스와이프 뷰어 모달 호출
  static void showImageDialog(BuildContext context, String initialUrl, List<String> allPhotos) {
    final photoList = allPhotos.isNotEmpty ? allPhotos : (initialUrl.isNotEmpty ? [initialUrl] : const <String>[]);
    if (photoList.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _PhotoSwipeViewerDialog(
        initialUrl: initialUrl,
        allPhotos: photoList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();

    // 단일 사진인 경우
    if (photos.length == 1) {
      final photoUrl = photos.first;
      return GestureDetector(
        onTap: () => showImageDialog(context, photoUrl, photos),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            height: singleImageHeight,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: buildImageWidget(photoUrl),
          ),
        ),
      );
    }

    // 복수 사진인 경우 가로 썸네일 리스트
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final photoUrl = photos[index];
          return GestureDetector(
            onTap: () => showImageDialog(context, photoUrl, photos),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 110,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: buildImageWidget(photoUrl),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 가로 스와이프(PageView) 및 핀치 줌, 인덱스 인디케이터를 지원하는 전체화면 사진 뷰어 다이얼로그
class _PhotoSwipeViewerDialog extends StatefulWidget {
  final String initialUrl;
  final List<String> allPhotos;

  const _PhotoSwipeViewerDialog({
    required this.initialUrl,
    required this.allPhotos,
  });

  @override
  State<_PhotoSwipeViewerDialog> createState() => _PhotoSwipeViewerDialogState();
}

class _PhotoSwipeViewerDialogState extends State<_PhotoSwipeViewerDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.allPhotos.indexOf(widget.initialUrl);
    _currentIndex = initialIndex != -1 ? initialIndex : 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.allPhotos.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.allPhotos.length > 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 가로 스와이프 가능한 PageView
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.allPhotos.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final photoUrl = widget.allPhotos[index];
                return _ZoomablePhotoPage(photoUrl: photoUrl);
              },
            ),
          ),

          // 2. 상단 인덱스 배지 (사진이 여러 장일 때: 예 "2 / 10")
          if (hasMultiple)
            Positioned(
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.allPhotos.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // 3. 우측 상단 닫기 버튼
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.60),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          // 4. 이전 사진 넘기기 버튼 (왼쪽 화살표)
          if (hasMultiple && _currentIndex > 0)
            Positioned(
              left: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                  tooltip: '이전 사진',
                  onPressed: _goToPrevious,
                ),
              ),
            ),

          // 5. 다음 사진 넘기기 버튼 (오른쪽 화살표)
          if (hasMultiple && _currentIndex < widget.allPhotos.length - 1)
            Positioned(
              right: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                  tooltip: '다음 사진',
                  onPressed: _goToNext,
                ),
              ),
            ),

          // 6. 하단 미니 도트 인디케이터 (10장 이하일 때 점 표시)
          if (hasMultiple && widget.allPhotos.length <= 10)
            Positioned(
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(widget.allPhotos.length, (idx) {
                    final isCurrent = idx == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isCurrent ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 개별 사진 확대/축소 및 줌 레벨에 따른 팬/스와이프 연동 위젯
class _ZoomablePhotoPage extends StatefulWidget {
  final String photoUrl;

  const _ZoomablePhotoPage({required this.photoUrl});

  @override
  State<_ZoomablePhotoPage> createState() => _ZoomablePhotoPageState();
}

class _ZoomablePhotoPageState extends State<_ZoomablePhotoPage> {
  final TransformationController _transformationController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomedNow = scale > 1.05;
    if (isZoomedNow != _isZoomed && mounted) {
      setState(() {
        _isZoomed = isZoomedNow;
      });
    }
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        panEnabled: _isZoomed, // 줌되지 않은 기본 상태(1.0)에서는 가로 스와이프가 PageView로 전달되도록 함
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: Center(
          child: PhotoGalleryView.buildImageWidget(
            widget.photoUrl,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

