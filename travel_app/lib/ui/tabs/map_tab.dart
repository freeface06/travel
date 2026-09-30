/// @intent 대화형 지도(flutter_map) 기반 일차별 확정 마커(activeItemsForSelectedDay), Polyline 동선, 일반/위성 세그먼트 스위처
/// @agent Gemini/manager-develop
/// @branch feat/flutter-travel-app
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import '../../models/trip_item.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_theme.dart';

class MapTab extends StatefulWidget {
  final void Function(TripItem item)? onMarkerTap;
  final String? mapStyle;
  final ValueChanged<String>? onMapStyleChanged;
  final bool showInternalStyleSwitcher;

  const MapTab({
    super.key,
    this.onMarkerTap,
    this.mapStyle,
    this.onMapStyleChanged,
    this.showInternalStyleSwitcher = false,
  });

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  String _internalMapStyle = 'google_roadmap'; // 'google_roadmap' (일반) | 'google_satellite' (위성)
  String get _mapStyle => widget.mapStyle ?? _internalMapStyle;
  String? _lastTripId;
  String? _lastSelectedItemId;

  @override
  bool get wantKeepAlive => true;

  String get _tileUrlTemplate {
    switch (_mapStyle) {
      case 'google_satellite':
        return 'https://{s}.google.com/vt/lyrs=y&hl=ko&x={x}&y={y}&z={z}';
      case 'google_roadmap':
      default:
        return 'https://{s}.google.com/vt/lyrs=m&hl=ko&x={x}&y={y}&z={z}';
    }
  }

  List<String> get _subdomains {
    return const ['mt0', 'mt1', 'mt2', 'mt3'];
  }

  bool _isMapReady = false;

  void _fitAllMarkers(List<TripItem> items) {
    if (!_isMapReady) return;
    final validPoints = items
        .where((i) => i.hasCoordinates)
        .map((i) => LatLng(i.lat!, i.lng!))
        .toList();

    if (validPoints.isEmpty) return;

    if (validPoints.length == 1) {
      _mapController.move(validPoints.first, 15.0);
      return;
    }

    double minLat = validPoints.first.latitude;
    double maxLat = validPoints.first.latitude;
    double minLng = validPoints.first.longitude;
    double maxLng = validPoints.first.longitude;

    for (final p in validPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.only(top: 80, bottom: 200, left: 40, right: 40),
      ),
    );
  }

  /// 활성화 상태가 직관적으로 드러나는 일반 / 위성 세그먼트 스위처
  Widget _buildMapStyleSwitcher() {
    final isRoadmap = _mapStyle == 'google_roadmap';
    final isSatellite = _mapStyle == 'google_satellite';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 일반 지도 버튼
          InkWell(
            onTap: () {
              if (!isRoadmap) {
                if (widget.onMapStyleChanged != null) {
                  widget.onMapStyleChanged!('google_roadmap');
                } else {
                  setState(() => _internalMapStyle = 'google_roadmap');
                }
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isRoadmap ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.map_outlined,
                    size: 14,
                    color: isRoadmap ? Colors.white : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '일반',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isRoadmap ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 위성 지도 버튼
          InkWell(
            onTap: () {
              if (!isSatellite) {
                if (widget.onMapStyleChanged != null) {
                  widget.onMapStyleChanged!('google_satellite');
                } else {
                  setState(() => _internalMapStyle = 'google_satellite');
                }
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSatellite ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.satellite_alt,
                    size: 14,
                    color: isSatellite ? Colors.white : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '위성',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSatellite ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TripProvider>();
    final items = provider.activeItemsForSelectedDay;

    // 좌표가 유효한 아이템만 필터링
    final allItemsWithCoord = items.where((i) => i.hasCoordinates).toList();

    // 초기 지도 중심점 계산
    LatLng initialCenter = const LatLng(35.6812, 139.7671); // 도쿄 기본값
    if (allItemsWithCoord.isNotEmpty) {
      initialCenter = LatLng(allItemsWithCoord.first.lat!, allItemsWithCoord.first.lng!);
    }

    // 일차별 Polyline 구성
    final Map<int, List<LatLng>> dayPolylinePoints = {};
    for (final item in items) {
      if (item.hasCoordinates) {
        dayPolylinePoints.putIfAbsent(item.day, () => []).add(LatLng(item.lat!, item.lng!));
      }
    }

    final polylines = dayPolylinePoints.entries.map((entry) {
      final day = entry.key;
      final points = entry.value;
      return Polyline(
        points: points,
        strokeWidth: 4.0,
        color: AppTheme.getDayColor(day).withValues(alpha: 0.8),
      );
    }).toList();

    // 마커 구성
    final markers = allItemsWithCoord.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      final dayColor = AppTheme.getDayColor(item.day);
      final isSelected = provider.selectedItemId == item.id;

      return Marker(
        point: LatLng(item.lat!, item.lng!),
        width: 44,
        height: 52,
        child: GestureDetector(
          onTap: () {
            provider.setSelectedItemId(item.id);
            if (provider.selectedDay != 'all' && provider.selectedDay != item.day) {
              provider.setSelectedDay(item.day);
            }
            if (widget.onMarkerTap != null) {
              widget.onMarkerTap!(item);
            }
          },
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: dayColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.yellowAccent : Colors.white,
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(10, 6),
                painter: _TrianglePainter(color: dayColor),
              ),
            ],
          ),
        ),
      );
    }).toList();

    // 현재 여행 변경 시 또는 초기 로드 시 자동으로 마커 영역 맞춤
    final tripId = provider.currentTripId;
    if (_lastTripId != tripId && allItemsWithCoord.isNotEmpty) {
      _lastTripId = tripId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAllMarkers(items);
      });
    }

    // 외부(타임라인 등)에서 선택된 일정으로 지도 이동
    final selectedId = provider.selectedItemId;
    if (_lastSelectedItemId != selectedId && selectedId != null) {
      _lastSelectedItemId = selectedId;
      final selectedItem = allItemsWithCoord.where((i) => i.id == selectedId).firstOrNull;
      if (selectedItem != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isMapReady) {
            _mapController.move(LatLng(selectedItem.lat!, selectedItem.lng!), 15.0);
          }
        });
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 13.0,
            minZoom: 2.0,
            maxZoom: 21.0,
            backgroundColor: const Color(0xFFEAEFF5),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _isMapReady = true;
              if (allItemsWithCoord.isNotEmpty) {
                _fitAllMarkers(items);
              }
            },
          ),
          children: [
            TileLayer(
              key: ValueKey(_mapStyle),
              urlTemplate: _tileUrlTemplate,
              fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: _subdomains,
              minZoom: 0.0,
              maxZoom: double.infinity,
              minNativeZoom: 1,
              maxNativeZoom: 19,
              panBuffer: 1,
              keepBuffer: 6,
              tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 100)),
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
              tileUpdateTransformer: TileUpdateTransformers.throttle(const Duration(milliseconds: 60)),
              tileProvider: NetworkTileProvider(
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
                  'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
                  'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
                },
                silenceExceptions: false,
                abortObsoleteRequests: false,
              ),
            ),
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),

        // 컨트롤 플로팅 버튼들 (상단 헤더 및 하단 바텀시트에 가려지지 않도록 우측 상단 안전 영역에 배치)
        Positioned(
          top: widget.showInternalStyleSwitcher ? 72 : 56,
          right: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showInternalStyleSwitcher) ...[
                // 1. 활성 상태가 한눈에 보이는 일반 / 위성 세그먼트 스위처
                _buildMapStyleSwitcher(),
                const SizedBox(height: 10),
              ],

              // 2. 모든 장소 한눈에 보기 버튼
              FloatingActionButton.small(
                heroTag: 'btn-fit-bounds',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.textPrimary,
                elevation: 3,
                tooltip: '모든 장소 한눈에 보기',
                onPressed: () => _fitAllMarkers(items),
                child: const Icon(Icons.center_focus_strong_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
