/// @intent 구글맵에서 감지된 장소를 확인하고 Day 및 카테고리를 선택해 원터치로 등록하는 바텀시트
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trip_item.dart';
import '../../providers/trip_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/quick_import_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

class QuickPlaceImportSheet extends StatefulWidget {
  final String rawInput;
  final int initialDay;

  const QuickPlaceImportSheet({
    super.key,
    required this.rawInput,
    this.initialDay = 1,
  });

  /// 바텀시트 팝업 네이티브 헬퍼 메서드
  static Future<void> show(
    BuildContext context, {
    required String rawInput,
    int? targetDay,
  }) {
    final validDay = (targetDay != null && targetDay > 0) ? targetDay : 1;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickPlaceImportSheet(
        rawInput: rawInput,
        initialDay: validDay,
      ),
    );
  }

  @override
  State<QuickPlaceImportSheet> createState() => _QuickPlaceImportSheetState();
}

class _QuickPlaceImportSheetState extends State<QuickPlaceImportSheet> {
  final GeocodingService _geocodingService = GeocodingService();

  late TextEditingController _titleController;
  late TextEditingController _memoController;
  late int _selectedDay;
  String _selectedCategory = 'ATTRACTION';

  bool _isLoading = true;
  String? _errorMessage;
  double? _lat;
  double? _lng;
  String _address = '';
  List<String> _photos = [];
  String _sourceUrl = '';

  final List<({String key, String label, IconData icon})> _categories = [
    (key: 'ATTRACTION', label: '관광지', icon: Icons.place_outlined),
    (key: 'DINING', label: '맛집/식당', icon: Icons.restaurant_outlined),
    (key: 'CAFE', label: '카페', icon: Icons.local_cafe_outlined),
    (key: 'HOTEL', label: '숙소', icon: Icons.hotel_outlined),
    (key: 'SHOPPING', label: '쇼핑', icon: Icons.shopping_bag_outlined),
    (key: 'TRANSIT', label: '교통/이동', icon: Icons.directions_transit_outlined),
    (key: 'ACTIVITY', label: '액티비티', icon: Icons.surfing_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay;
    _titleController = TextEditingController();
    _memoController = TextEditingController();
    _sourceUrl = QuickImportService.extractGoogleMapsUrl(widget.rawInput) ?? widget.rawInput;

    _resolvePlaceInfo();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// 구글맵 입력 텍스트 또는 URL로부터 위치 정보 및 장소명 파싱
  Future<void> _resolvePlaceInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. 텍스트에서 힌트 장소명 추출 시도
      final nameHint = QuickImportService.extractPlaceNameHint(widget.rawInput);
      if (nameHint != null && nameHint.isNotEmpty) {
        _titleController.text = nameHint;
      }

      // 2. GeocodingService로 장소 정보 정밀 분석
      final targetInput = _sourceUrl.isNotEmpty ? _sourceUrl : widget.rawInput;
      final resolved = await _geocodingService.resolveLocation(targetInput);

      if (!mounted) return;

      if (resolved != null) {
        setState(() {
          _lat = resolved.lat;
          _lng = resolved.lng;
          _address = resolved.address ?? '';
          _photos = List<String>.from(resolved.photos);

          final resolvedName = resolved.name?.trim() ?? '';
          if (resolvedName.isNotEmpty) {
            _titleController.text = resolvedName;
          } else if (_titleController.text.isEmpty) {
            _titleController.text = '새로운 장소';
          }

          _isLoading = false;
        });
      } else {
        // 정밀 분석 실패 시 힌트 또는 기본 텍스트 유지
        setState(() {
          if (_titleController.text.isEmpty) {
            _titleController.text = '장소 (직접 입력)';
          }
          _isLoading = false;
          _errorMessage = '위치 좌표를 자동으로 찾지 못했습니다. 장소명을 직접 입력해 등록할 수 있습니다.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_titleController.text.isEmpty) {
          _titleController.text = '장소 (직접 입력)';
        }
        _isLoading = false;
        _errorMessage = '장소 정보를 불러오는 중 일시적인 오류가 발생했습니다: $e';
      });
    }
  }

  /// 일정에 등록 실행
  Future<void> _addToTrip() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppToast.error(context, '장소명을 입력해 주세요.');
      return;
    }

    final provider = context.read<TripProvider>();
    final meta = provider.currentTrip.metadata;

    final newItem = TripItem(
      id: 'item-${DateTime.now().millisecondsSinceEpoch}',
      day: _selectedDay,
      title: title,
      category: _selectedCategory,
      lat: _lat,
      lng: _lng,
      address: _address,
      cost: 0,
      currency: meta.baseCurrency,
      payer: meta.participants.isNotEmpty ? meta.participants.first : '공통',
      memo: _memoController.text.trim(),
      time: '',
      photos: _photos,
      locationUrl: _sourceUrl,
      slotGroupId: '',
      candidateLabel: '1',
      isSelected: true,
    );

    provider.addItem(newItem);

    // 중복 재감지 방지 처리
    QuickImportService.instance.markUrlProcessed(widget.rawInput);

    if (mounted) {
      AppToast.success(context, '$title이(가) Day $_selectedDay에 추가되었습니다.');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final provider = context.watch<TripProvider>();
    final meta = provider.currentTrip.metadata;

    // 현재 여행의 전체 일수 계산
    int maxDay = _selectedDay;
    for (final item in provider.currentTrip.items) {
      if (item.day > maxDay) maxDay = item.day;
    }
    if (meta.startDate.isNotEmpty && meta.endDate.isNotEmpty) {
      try {
        final start = DateTime.parse(meta.startDate);
        final end = DateTime.parse(meta.endDate);
        final days = end.difference(start).inDays + 1;
        if (days > maxDay) maxDay = days;
      } catch (_) {}
    }
    if (maxDay < 1) maxDay = 1;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 드래그 핸들
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. 상단 헤더: 구글맵 감지 배지 & 닫기 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: AppTheme.primary),
                          SizedBox(width: 5),
                          Text(
                            '구글맵에서 장소 감지됨',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        QuickImportService.instance.markUrlProcessed(widget.rawInput);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. 분석 상태 또는 장소 미리보기 카드
                if (_isLoading)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Column(
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '구글맵 장소 정보 분석 중...',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // 대표 사진 썸네일 (있을 경우)
                  if (_photos.isNotEmpty)
                    Container(
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFF1F5F9),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        _photos.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                        ),
                      ),
                    ),

                  // 장소명 입력 필드
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: '장소명',
                      labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.pin_drop, color: AppTheme.primary, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // 주소 및 좌표 정보 (파싱 성공 시)
                  if (_lat != null && _lng != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _address.isNotEmpty
                                  ? _address
                                  : '좌표: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD97706)),
                      ),
                    ),
                ],
                const SizedBox(height: 16),

                // 4. Day 일차 선택기
                const Text(
                  '추가할 Day 선택',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(maxDay, (index) {
                      final day = index + 1;
                      final isSelected = _selectedDay == day;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            'Day $day',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primary,
                          backgroundColor: const Color(0xFFF1F5F9),
                          onSelected: (val) {
                            if (val) setState(() => _selectedDay = day);
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),

                // 5. 카테고리 선택기
                const Text(
                  '카테고리 선택',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((c) {
                    final isSelected = _selectedCategory == c.key;
                    return ChoiceChip(
                      avatar: Icon(
                        c.icon,
                        size: 14,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                      label: Text(
                        c.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: const Color(0xFFF1F5F9),
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = c.key);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 6. 메모 필드 (선택 입력)
                TextField(
                  controller: _memoController,
                  decoration: InputDecoration(
                    hintText: '메모를 입력하세요 (선택 사항)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.notes_outlined, size: 18, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                // 7. 하단 [일정에 추가하기] 버튼
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addToTrip,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18, color: Colors.white),
                  label: const Text(
                    '일정에 추가하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
