/// @intent 구글맵 장소의 전체 사진을 그리드/리스트로 탐색하고, 스크롤 최하단 도달 시 무한 스크롤(Infinite Scroll)로 추가 사진을 자동 로드하는 전용 팝업 시트
/// @agent Gemini/manager-develop
/// @branch feat/lazy-google-photos
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import '../../services/google_places_service.dart';
import '../theme/app_theme.dart';
import '../widgets/photo_gallery_view.dart';

class PlaceAllPhotosSheet extends StatefulWidget {
  final String placeName;
  final String? locationUrl;
  final double? lat;
  final double? lng;
  final List<String> initialPhotos;
  final double? rating;
  final int? userRatingsTotal;

  const PlaceAllPhotosSheet({
    super.key,
    required this.placeName,
    this.locationUrl,
    this.lat,
    this.lng,
    this.initialPhotos = const [],
    this.rating,
    this.userRatingsTotal,
  });

  /// 팝업 바텀 시트로 전체 사진 모달 표시
  static Future<void> show(
    BuildContext context, {
    required String placeName,
    String? locationUrl,
    double? lat,
    double? lng,
    List<String> initialPhotos = const [],
    double? rating,
    int? userRatingsTotal,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PlaceAllPhotosSheet(
        placeName: placeName,
        locationUrl: locationUrl,
        lat: lat,
        lng: lng,
        initialPhotos: initialPhotos,
        rating: rating,
        userRatingsTotal: userRatingsTotal,
      ),
    );
  }

  @override
  State<PlaceAllPhotosSheet> createState() => _PlaceAllPhotosSheetState();
}

class _PlaceAllPhotosSheetState extends State<PlaceAllPhotosSheet> {
  late List<String> _photos;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  double? _resolvedLat;
  double? _resolvedLng;
  double? _rating;
  int? _userRatingsTotal;

  @override
  void initState() {
    super.initState();
    _photos = List<String>.from(widget.initialPhotos);
    _resolvedLat = widget.lat;
    _resolvedLng = widget.lng;
    _rating = widget.rating;
    _userRatingsTotal = widget.userRatingsTotal;

    _scrollController.addListener(_onScroll);

    // 전달받은 사진이 없거나 추가 정보(평점 등)가 비어있는 경우 즉시 장소 정보 로드
    if (_photos.isEmpty || _resolvedLat == null || _rating == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialPhotos();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 최하단 200px 근접 시 추가 사진 자동 로드 (무한 스크롤)
    if (currentScroll >= (maxScroll - 200) && !_isLoadingMore && _hasMore) {
      _loadMorePhotos();
    }
  }

  /// 초기 장소 정보 및 1차 대표 사진 로드
  Future<void> _loadInitialPhotos() async {
    if (_isLoadingInitial) return;
    setState(() => _isLoadingInitial = true);

    try {
      final info = await GooglePlacesService.fetchPlaceInfo(
        placeName: widget.placeName,
        locationUrl: widget.locationUrl,
        lat: _resolvedLat,
        lng: _resolvedLng,
        maxPhotos: 10,
      );

      if (mounted && info != null) {
        setState(() {
          _resolvedLat ??= info.lat;
          _resolvedLng ??= info.lng;
          _rating ??= info.rating;
          _userRatingsTotal ??= info.userRatingsTotal;

          if (info.photos.isNotEmpty) {
            final existing = Set<String>.from(_photos);
            for (final p in info.photos) {
              existing.add(p);
            }
            _photos = existing.toList();
          }
        });
      }
    } catch (e) {
      debugPrint('[PlaceAllPhotosSheet] _loadInitialPhotos error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitial = false);
      }
    }
  }

  /// 무한 스크롤: 스크롤이 하단에 도달했을 때 추가 고화질 사진 로드
  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMore) return;

    final lat = _resolvedLat;
    final lng = _resolvedLng;
    if (lat == null || lng == null) {
      setState(() => _hasMore = false);
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final nextPhotos = await GooglePlacesService.fetchMorePhotosForPlace(
        placeName: widget.placeName,
        lat: lat,
        lng: lng,
        page: _page + 1,
        existingPhotos: _photos,
      );

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          if (nextPhotos.isNotEmpty) {
            final existing = Set<String>.from(_photos);
            for (final p in nextPhotos) {
              existing.add(p);
            }
            _photos = existing.toList();
            _page++;
          } else {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      debugPrint('[PlaceAllPhotosSheet] _loadMorePhotos error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.92;
    final isWide = mediaQuery.size.width >= 600;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 드래그 핸들
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // 상단 헤더: 장소명, 평점, 사진 수 및 닫기 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.placeName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '사진 ${_photos.length}장',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // 사진 목록 및 무한 스크롤 그리드
            Expanded(
              child: _isLoadingInitial && _photos.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                          SizedBox(height: 14),
                          Text(
                            '구글맵 장소 사진을 불러오는 중...',
                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : _photos.isEmpty
                      ? const Center(
                          child: Text(
                            '등록된 장소 사진이 없습니다.',
                            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                          ),
                        )
                      : CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.all(12),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isWide ? 3 : 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1.0,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, index) {
                                    final photoUrl = _photos[index];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => PhotoGalleryView.showImageDialog(
                                        context,
                                        photoUrl,
                                        _photos,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: PhotoGalleryView.buildImageWidget(
                                            photoUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  childCount: _photos.length,
                                ),
                              ),
                            ),

                            // 하단 무한 스크롤 로딩 및 종료 인디케이터
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: _isLoadingMore
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              '추가 사진을 불러오는 중...',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        )
                                      : !_hasMore && _photos.isNotEmpty
                                          ? const Text(
                                              '해당 장소의 모든 사진을 불러왔습니다.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF94A3B8),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                ),
                              ),
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
