/// @intent 구글맵 장소 카드(장소명, 별점, 리뷰수, 액션 버튼) 및 가로 스크롤 사진 뷰어와 '사진 모두 보기 [전체보기]' 오버레이 카드를 제공하는 공용 위젯
/// @agent Gemini/manager-develop
/// @branch feat/lazy-google-photos
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import '../../services/google_places_service.dart';
import '../sheets/place_all_photos_sheet.dart';
import '../theme/app_theme.dart';
import 'photo_gallery_view.dart';

class PlacePhotoPreviewCard extends StatefulWidget {
  final String title;
  final String locationUrl;
  final double? lat;
  final double? lng;
  final String address;
  final List<String> personalPhotos;
  final bool showHeader;
  final VoidCallback? onFocusMap;

  const PlacePhotoPreviewCard({
    super.key,
    required this.title,
    this.locationUrl = '',
    this.lat,
    this.lng,
    this.address = '',
    this.personalPhotos = const [],
    this.showHeader = true,
    this.onFocusMap,
  });

  @override
  State<PlacePhotoPreviewCard> createState() => _PlacePhotoPreviewCardState();
}

class _PlacePhotoPreviewCardState extends State<PlacePhotoPreviewCard> {
  PlaceInfoResult? _placeInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchInfoIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PlacePhotoPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.locationUrl != widget.locationUrl ||
        oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng) {
      _fetchInfoIfNeeded();
    }
  }

  Future<void> _fetchInfoIfNeeded() async {
    final queryName = widget.title.trim().isNotEmpty ? widget.title.trim() : widget.address.trim();
    if (queryName.isEmpty && widget.lat == null && widget.locationUrl.isEmpty) {
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final info = await GooglePlacesService.fetchPlaceInfo(
        placeName: queryName,
        locationUrl: widget.locationUrl,
        lat: widget.lat,
        lng: widget.lng,
        maxPhotos: 10,
      );

      if (mounted) {
        setState(() {
          _placeInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[PlacePhotoPreviewCard] _fetchInfoIfNeeded error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openAllPhotos(List<String> combinedPhotos) {
    PlaceAllPhotosSheet.show(
      context,
      placeName: _placeInfo?.name.isNotEmpty == true ? _placeInfo!.name : widget.title,
      locationUrl: widget.locationUrl,
      lat: widget.lat ?? _placeInfo?.lat,
      lng: widget.lng ?? _placeInfo?.lng,
      initialPhotos: combinedPhotos,
    );
  }

  @override
  Widget build(BuildContext context) {
    final googlePhotos = _placeInfo?.photos ?? const [];
    final combined = <String>[...widget.personalPhotos];
    for (final p in googlePhotos) {
      if (!combined.contains(p)) {
        combined.add(p);
      }
    }

    // 사진이 전혀 없고 로딩 중도 아닌 경우 표시하지 않음
    if (combined.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 헤더: 장소명 및 액션 버튼 (Image 1 스타일)
          if (widget.showHeader) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 장소명
                  Text(
                    _placeInfo?.name.isNotEmpty == true ? _placeInfo!.name : widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // 액션 알약 버튼 (지도에서 보기, 사진 전체보기)
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (widget.onFocusMap != null) ...[
                          _buildActionButton(
                            icon: Icons.navigation_outlined,
                            label: '지도에서 보기',
                            isPrimary: true,
                            onTap: widget.onFocusMap!,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _buildActionButton(
                          icon: Icons.photo_library_outlined,
                          label: '사진 전체보기',
                          isPrimary: widget.onFocusMap == null,
                          onTap: () => _openAllPhotos(combined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 2. 가로 스크롤 사진 목록 및 마지막 '사진 모두 보기' 오버레이 카드 (Image 1 & 2 스타일)
          if (_isLoading && combined.isEmpty) ...[
            Container(
              height: 170,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '구글맵 사진을 불러오는 중...',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (combined.isNotEmpty) ...[
            SizedBox(
              height: 175,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: combined.length + 1, // 마지막 카드: Image 2 오버레이 카드
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  // 마지막 카드: Image 2 오버레이 카드 ("사진 모두 보기 / 전체보기")
                  if (index == combined.length) {
                    final bgPhoto = combined.isNotEmpty ? combined.last : '';
                    return _buildAllPhotosOverlayCard(context, bgPhoto, combined);
                  }

                  final photo = combined[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => PhotoGalleryView.showImageDialog(context, photo, combined),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 195,
                        height: 175,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: PhotoGalleryView.buildImageWidget(
                          photo,
                          width: 195,
                          height: 175,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 알약 스타일 액션 버튼 (Image 1 스타일)
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isPrimary ? const Color(0xFF1A73E8) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isPrimary ? const Color(0xFF1A73E8) : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isPrimary ? Colors.white : const Color(0xFF334155),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 마지막 오버레이 카드 (Image 2 스타일: 어두운 반투명 오버레이 + "사진 모두 보기" + [전체보기] 버튼)
  Widget _buildAllPhotosOverlayCard(
    BuildContext context,
    String backgroundPhoto,
    List<String> combinedPhotos,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openAllPhotos(combinedPhotos),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 175,
          height: 175,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 배경 이미지
              if (backgroundPhoto.isNotEmpty)
                PhotoGalleryView.buildImageWidget(
                  backgroundPhoto,
                  fit: BoxFit.cover,
                ),

              // 어두운 반투명 오버레이 레이어
              Container(
                color: const Color(0x9E000000),
              ),

              // 중앙 텍스트 및 [전체보기] 테두리 버튼
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      size: 26,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '사진 모두 보기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.4),
                      ),
                      child: const Text(
                        '전체보기',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
