/*
 * @intent 새 일정 추가/수정 바텀시트 모달 - 6대 카테고리 3x2 그리드, Search-First 장소 검색, 지도 기반 핀 미세조정, 현재 일차 자동 배정 및 대안 플랜(후보) 등록 지원
 * @agent  Gemini/manager-develop
 * @branch feat/flutter-travel-app
 * @author @developer_name
 * @date   2026-09-30
 */
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/trip_item.dart';
import '../../providers/trip_provider.dart';
import '../../services/geocoding_service.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/thousands_separator_input_formatter.dart';
import 'package:url_launcher/url_launcher.dart';

class ItemEditDialog extends StatefulWidget {
  final TripItem? item;
  final TripItem? baseItem;
  final bool isCandidateMode;
  final VoidCallback? onOpenMapPicker;

  const ItemEditDialog({
    super.key,
    this.item,
    this.baseItem,
    this.isCandidateMode = false,
    this.onOpenMapPicker,
  });

  /// 바텀시트 모달을 띄우는 네이티브 헬퍼 메서드
  static Future<void> show(
    BuildContext context, {
    TripItem? item,
    VoidCallback? onOpenMapPicker,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemEditDialog(
        item: item,
        onOpenMapPicker: onOpenMapPicker,
      ),
    );
  }

  /// 특정 일정에 대한 대안 플랜(후보) 등록 전용 모달 헬퍼
  static Future<void> showCandidate(
    BuildContext context, {
    required TripItem baseItem,
    VoidCallback? onOpenMapPicker,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemEditDialog(
        baseItem: baseItem,
        isCandidateMode: true,
        onOpenMapPicker: onOpenMapPicker,
      ),
    );
  }

  @override
  State<ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<ItemEditDialog> {
  final GeocodingService _geocodingService = GeocodingService();

  late String _category;
  late TextEditingController _titleController;
  late int _day;
  late TextEditingController _timeController;
  late TextEditingController _costController;
  late String _currency;
  late String _payer;
  late TextEditingController _memoController;

  // 위치 (구글맵 연동)
  late TextEditingController _coordPasteController;
  double? _lat;
  double? _lng;
  String _address = '';
  String _locationUrl = '';
  bool _isSearching = false;
  String? _locationStatusMessage;
  bool _isLocationStatusError = false;

  // 기존 첨부 사진 보존 (편집 시 유지)
  late List<String> _photos;

  // 특화 필드: FLIGHT
  late String _flightType;
  late TextEditingController _airlineController;
  late TextEditingController _flightNoController;
  late TextEditingController _airportController;
  late TextEditingController _terminalGateController;
  late TextEditingController _seatController;
  late TextEditingController _bookingRefController;

  // 특화 필드: AIRPORT
  late TextEditingController _baggageClaimController;
  late TextEditingController _transitToCityController;
  late TextEditingController _pickupInfoController;
  late TextEditingController _customsMemoController;

  // 특화 필드: HOTEL
  late TextEditingController _checkOutTimeController;
  late TextEditingController _voucherNoController;
  late TextEditingController _passcodeController;
  late TextEditingController _luggageStorageController;

  // 특화 필드: ATTRACTION
  late TextEditingController _openingHoursController;
  late TextEditingController _bookingStatusController;
  late TextEditingController _ticketCostController;
  late TextEditingController _tipsController;

  // 특화 필드: DINING
  late String _mealType;
  late String _paymentMethod;
  late TextEditingController _reservedForController;
  late TextEditingController _menuRecommendationController;

  // 특화 필드: TRANSIT
  late String _transitMode;
  late TextEditingController _departureStationController;
  late TextEditingController _arrivalStationController;
  late TextEditingController _transitLineController;
  late TextEditingController _ticketOrSeatController;
  late TextEditingController _transferMemoController;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final base = widget.baseItem;
    final meta = context.read<TripProvider>().currentTrip.metadata;
    final currentDay = context.read<TripProvider>().selectedDay;
    final defaultDay = (currentDay == 'all' ? 1 : (currentDay is int ? currentDay : 1));

    _category = item?.category ?? base?.category ?? 'ATTRACTION';
    _titleController = TextEditingController(text: item?.title ?? '');
    _day = item?.day ?? base?.day ?? defaultDay;
    _timeController = TextEditingController(text: item?.time ?? base?.time ?? '');
    final initialCost = item != null && item.cost > 0
        ? (item.cost % 1 == 0
            ? NumberFormat('#,###').format(item.cost.toInt())
            : NumberFormat('#,###.##').format(item.cost))
        : '';
    _costController = TextEditingController(text: initialCost);
    _currency = item?.currency.isNotEmpty == true ? item!.currency : meta.baseCurrency;
    _payer = item?.payer.isNotEmpty == true ? item!.payer : (meta.participants.isNotEmpty ? meta.participants.first : '공통');
    _memoController = TextEditingController(text: item?.memo ?? '');
    _photos = item != null ? List<String>.from(item.photos) : [];
    _locationUrl = item?.locationUrl ?? '';

    _lat = item?.lat;
    _lng = item?.lng;
    _address = item?.address ?? '';
    _coordPasteController = TextEditingController(
      text: _lat != null && _lng != null ? '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}' : '',
    );

    // FLIGHT
    _flightType = item?.flightType.isNotEmpty == true ? item!.flightType : 'DEPARTURE';
    _airlineController = TextEditingController(text: item?.airline ?? '');
    _flightNoController = TextEditingController(text: item?.flightNo ?? '');
    _airportController = TextEditingController(text: item?.airport ?? '');
    _terminalGateController = TextEditingController(text: item?.terminalGate ?? '');
    _seatController = TextEditingController(text: item?.seat ?? '');
    _bookingRefController = TextEditingController(text: item?.bookingRef ?? '');

    // AIRPORT
    _baggageClaimController = TextEditingController(text: item?.baggageClaim ?? '');
    _transitToCityController = TextEditingController(text: item?.transitToCity ?? '');
    _pickupInfoController = TextEditingController(text: item?.pickupInfo ?? '');
    _customsMemoController = TextEditingController(text: item?.customsMemo ?? '');

    // HOTEL
    _checkOutTimeController = TextEditingController(text: item?.checkOutTime ?? '');
    _voucherNoController = TextEditingController(text: item?.voucherNo ?? '');
    _passcodeController = TextEditingController(text: item?.passcode ?? '');
    _luggageStorageController = TextEditingController(text: item?.luggageStorage ?? '');

    // ATTRACTION
    _openingHoursController = TextEditingController(text: item?.openingHours ?? '');
    _bookingStatusController = TextEditingController(text: item?.bookingStatus ?? '');
    final initialTicketCost = item != null && item.ticketCostPerPerson > 0
        ? (item.ticketCostPerPerson % 1 == 0
            ? NumberFormat('#,###').format(item.ticketCostPerPerson.toInt())
            : NumberFormat('#,###.##').format(item.ticketCostPerPerson))
        : '';
    _ticketCostController = TextEditingController(text: initialTicketCost);
    _tipsController = TextEditingController(text: item?.tips ?? '');

    // DINING
    _mealType = item?.mealType.isNotEmpty == true ? item!.mealType : '조식';
    _paymentMethod = item?.paymentMethod.isNotEmpty == true ? item!.paymentMethod : '카드';
    _reservedForController = TextEditingController(text: item?.reservedFor ?? '');
    _menuRecommendationController = TextEditingController(text: item?.menuRecommendation ?? '');

    // TRANSIT
    _transitMode = item?.transitMode.isNotEmpty == true ? item!.transitMode : '전철/지하철';
    _departureStationController = TextEditingController(text: item?.departureStation ?? '');
    _arrivalStationController = TextEditingController(text: item?.arrivalStation ?? '');
    _transitLineController = TextEditingController(text: item?.transitLine ?? '');
    _ticketOrSeatController = TextEditingController(text: item?.ticketOrSeat ?? '');
    _transferMemoController = TextEditingController(text: item?.transferMemo ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    _costController.dispose();
    _memoController.dispose();
    _coordPasteController.dispose();

    _airlineController.dispose();
    _flightNoController.dispose();
    _airportController.dispose();
    _terminalGateController.dispose();
    _seatController.dispose();
    _bookingRefController.dispose();

    _baggageClaimController.dispose();
    _transitToCityController.dispose();
    _pickupInfoController.dispose();
    _customsMemoController.dispose();

    _checkOutTimeController.dispose();
    _voucherNoController.dispose();
    _passcodeController.dispose();
    _luggageStorageController.dispose();

    _openingHoursController.dispose();
    _bookingStatusController.dispose();
    _ticketCostController.dispose();
    _tipsController.dispose();

    _reservedForController.dispose();
    _menuRecommendationController.dispose();

    _departureStationController.dispose();
    _arrivalStationController.dispose();
    _transitLineController.dispose();
    _ticketOrSeatController.dispose();
    _transferMemoController.dispose();
    super.dispose();
  }

  void _onTitleChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.contains('maps.app.goo.gl') ||
        trimmed.contains('goo.gl/maps') ||
        trimmed.contains('google.com/maps') ||
        trimmed.contains('maps.google.com')) {
      debugPrint('[ItemEditDialog] Detected Google Maps link pasted into title field: "$trimmed"');
      _locationUrl = trimmed;
      _coordPasteController.text = trimmed;
      _applyCoordPaste();
    }
  }

  Future<bool> _processLocationInput(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.startsWith('http') || trimmed.contains('maps') || trimmed.contains('goo.gl')) {
      _locationUrl = trimmed;
    }

    debugPrint('[ItemEditDialog] _processLocationInput processing: "$trimmed"');
    setState(() {
      _isSearching = true;
      _locationStatusMessage = '구글맵 위치 및 좌표를 불러오는 중입니다...';
      _isLocationStatusError = false;
    });

    try {
      final resolved = await _geocodingService.resolveLocation(trimmed);
      debugPrint('[ItemEditDialog] resolveLocation result: $resolved');

      if (resolved != null) {
        String placeName = resolved.name ?? '';
        String placeAddress = resolved.address ?? '';

        // 역지오코딩으로 추가 정보 보완 (이름이나 주소가 비어있는 경우)
        if (placeName.isEmpty || placeAddress.isEmpty) {
          try {
            final rev = await _geocodingService.reverseGeocode(resolved.lat, resolved.lng);
            if (placeName.isEmpty) {
              placeName = rev?.name ?? _titleController.text.trim();
            }
            if (placeAddress.isEmpty) {
              placeAddress = rev?.displayName ?? '${resolved.lat.toStringAsFixed(5)}, ${resolved.lng.toStringAsFixed(5)}';
            }
          } catch (e) {
            debugPrint('[ItemEditDialog] Reverse geocoding error: $e');
          }
        }

        if (mounted) {
          setState(() {
            _lat = resolved.lat;
            _lng = resolved.lng;
            _coordPasteController.text = '${resolved.lat.toStringAsFixed(6)}, ${resolved.lng.toStringAsFixed(6)}';

            final currentTitle = _titleController.text.trim();
            if (placeName.isNotEmpty) {
              if (currentTitle.isEmpty ||
                  currentTitle == '새 일정' ||
                  currentTitle.contains('http://') ||
                  currentTitle.contains('https://') ||
                  currentTitle.contains('maps.app.goo.gl')) {
                _titleController.text = placeName;
              }
            }
            _address = placeAddress;
            _isSearching = false;
            _locationStatusMessage = '\'${placeName.isNotEmpty ? placeName : "장소"}\' 구글맵 좌표(${resolved.lat.toStringAsFixed(4)}, ${resolved.lng.toStringAsFixed(4)})가 등록되었습니다.';
            _isLocationStatusError = false;
          });

          AppToast.success(context, '\'${placeName.isNotEmpty ? placeName : '선택 장소'}\' 구글맵 좌표가 등록되었습니다.');
        }
        return true;
      } else {
        if (mounted) {
          setState(() {
            _isSearching = false;
            _locationStatusMessage = '링크에서 유효한 위치 좌표를 찾지 못했습니다. 구글맵에서 링크를 다시 복사해 주세요.';
            _isLocationStatusError = true;
          });
        }
        return false;
      }
    } catch (e, st) {
      debugPrint('[ItemEditDialog] _processLocationInput error: $e\n$st');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _locationStatusMessage = '오류 발생: $e';
          _isLocationStatusError = true;
        });
      }
      return false;
    }
  }

  Future<void> _pasteFromClipboard() async {
    debugPrint('[ItemEditDialog] _pasteFromClipboard clicked');
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      debugPrint('[ItemEditDialog] Clipboard text: "$text"');

      if (text == null || text.isEmpty) {
        if (mounted) {
          setState(() {
            _locationStatusMessage = '클립보드에 복사된 내용이 없습니다.';
            _isLocationStatusError = true;
          });
          AppToast.warning(context, '클립보드에 복사된 내용이 없습니다.');
        }
        return;
      }

      _coordPasteController.text = text;
      await _applyCoordPaste();
    } catch (e) {
      debugPrint('[ItemEditDialog] Clipboard read error: $e');
      if (mounted) {
        setState(() {
          _locationStatusMessage = '클립보드를 불러오는 중 오류가 발생했습니다: $e';
          _isLocationStatusError = true;
        });
      }
    }
  }

  Future<void> _applyCoordPaste() async {
    String text = _coordPasteController.text.trim();
    debugPrint('[ItemEditDialog] _applyCoordPaste called with text: "$text", title: "${_titleController.text}"');

    // 사용자가 '일정 / 장소명' 란에 링크나 좌표를 입력한 경우 자동 감지 및 대체
    if (text.isEmpty && _titleController.text.trim().isNotEmpty) {
      final titleText = _titleController.text.trim();
      if (titleText.contains('http') ||
          titleText.contains('maps') ||
          titleText.contains(',') ||
          titleText.contains('goo.gl')) {
        text = titleText;
        _coordPasteController.text = text;
        debugPrint('[ItemEditDialog] Used title text as fallback input: "$text"');
      }
    }

    if (text.isEmpty) {
      setState(() {
        _locationStatusMessage = '구글맵 링크 또는 좌표(위도, 경도)를 입력해 주세요.';
        _isLocationStatusError = true;
      });
      AppToast.warning(context, '구글맵 링크 또는 위도, 경도 좌표를 입력해 주세요.');
      return;
    }

    if (text.startsWith('http') || text.contains('maps') || text.contains('goo.gl')) {
      _locationUrl = text;
    }

    setState(() {
      _locationStatusMessage = '구글맵 위치 정보 분석 중...';
      _isLocationStatusError = false;
    });

    final success = await _processLocationInput(text);
    if (!success && mounted) {
      setState(() {
        _locationStatusMessage = '위치 정보를 확인할 수 없습니다. 구글맵 링크를 확인해 주세요.';
        _isLocationStatusError = true;
      });
    }
  }

  Future<void> _openInGoogleMaps() async {
    final title = _titleController.text.trim();
    final queryText = title.isNotEmpty && title != '새 일정' ? title : '';

    Uri uri;
    if (_lat != null && _lng != null) {
      if (queryText.isNotEmpty) {
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(queryText)}&center=$_lat,$_lng&hl=ko');
      } else {
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$_lat,$_lng&hl=ko');
      }
    } else if (queryText.isNotEmpty) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(queryText)}&hl=ko');
    } else {
      uri = Uri.parse('https://www.google.com/maps?hl=ko');
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, '구글맵을 열 수 없습니다.');
      }
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    if (_timeController.text.contains(':')) {
      final parts = _timeController.text.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        initial = TimeOfDay(hour: h, minute: m);
      }
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() {
        _timeController.text = '$h:$m';
      });
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppToast.warning(context, '일정 / 장소명을 입력해 주세요.');
      return;
    }

    final day = _day;
    final cost = double.tryParse(_costController.text.replaceAll(',', '').trim()) ?? 0.0;
    final ticketCost = double.tryParse(_ticketCostController.text.replaceAll(',', '').trim()) ?? 0.0;

    final provider = context.read<TripProvider>();
    final isNew = widget.item == null;

    final updated = TripItem(
      id: widget.item?.id ?? '',
      day: day,
      title: title,
      category: _category,
      lat: _lat,
      lng: _lng,
      address: _address,
      cost: cost,
      currency: _currency,
      payer: _payer,
      memo: _memoController.text.trim(),
      time: _timeController.text.trim(),
      photos: List<String>.from(_photos),
      locationUrl: _locationUrl,
      flightType: _flightType,
      airline: _airlineController.text.trim(),
      flightNo: _flightNoController.text.trim(),
      airport: _airportController.text.trim(),
      terminalGate: _terminalGateController.text.trim(),
      seat: _seatController.text.trim(),
      bookingRef: _bookingRefController.text.trim(),
      baggageClaim: _baggageClaimController.text.trim(),
      transitToCity: _transitToCityController.text.trim(),
      pickupInfo: _pickupInfoController.text.trim(),
      customsMemo: _customsMemoController.text.trim(),
      checkOutTime: _checkOutTimeController.text.trim(),
      voucherNo: _voucherNoController.text.trim(),
      passcode: _passcodeController.text.trim(),
      luggageStorage: _luggageStorageController.text.trim(),
      openingHours: _openingHoursController.text.trim(),
      bookingStatus: _bookingStatusController.text.trim(),
      ticketCostPerPerson: ticketCost,
      tips: _tipsController.text.trim(),
      mealType: _mealType,
      paymentMethod: _paymentMethod,
      reservedFor: _reservedForController.text.trim(),
      menuRecommendation: _menuRecommendationController.text.trim(),
      transitMode: _transitMode,
      departureStation: _departureStationController.text.trim(),
      arrivalStation: _arrivalStationController.text.trim(),
      transitLine: _transitLineController.text.trim(),
      ticketOrSeat: _ticketOrSeatController.text.trim(),
      transferMemo: _transferMemoController.text.trim(),
      slotGroupId: widget.item?.slotGroupId ?? '',
      candidateLabel: widget.item?.candidateLabel ?? '1',
      isSelected: widget.item?.isSelected ?? true,
    );

    if (widget.isCandidateMode && widget.baseItem != null) {
      provider.addCandidateItem(
        baseItem: widget.baseItem!,
        candidateItem: updated,
      );
      AppToast.success(context, '대안 플랜(후보)이 추가되었습니다.');
    } else if (isNew) {
      provider.addItem(updated);
    } else {
      provider.updateItem(updated.id, updated);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<TripProvider>().currentTrip.metadata;
    final isEditing = widget.item != null;
    final isCandidate = widget.isCandidateMode;
    final mediaQuery = MediaQuery.of(context);

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.90,
          maxWidth: 680,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 드래그 핸들 (손잡이)
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // 다이얼로그 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isCandidate
                              ? Icons.alt_route_rounded
                              : (isEditing ? Icons.edit_note : Icons.add_location_alt),
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCandidate
                            ? '대안 플랜(후보) 추가'
                            : (isEditing ? '일정 수정' : '새 일정 추가'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (isCandidate && widget.baseItem != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(
                            'Day $_day',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // 스크롤 본문
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1) 상단 6대 카테고리 3x2 카드 칩 그리드
                    _buildCategoryGrid3x2(),
                    const SizedBox(height: 16),

                    // 2) 핵심 정보 행: 일정명, Day, 시각 (TimePicker)
                    _buildCoreInfoSection(),
                    const SizedBox(height: 16),

                    // 3) 구글맵 연동: 원클릭 장소 검색 & 링크/좌표 붙여넣기
                    _buildGoogleMapsLocationSection(),
                    const SizedBox(height: 16),

                    // 5) 카테고리별 특화 필드
                    _buildCategorySpecificFields(),
                    const SizedBox(height: 16),

                    // 6) 비용 및 지불인 섹션
                    _buildExpenseSection(meta),
                    const SizedBox(height: 16),

                    // 상세 메모 섹션
                    _buildMemoSection(),
                  ],
                ),
              ),
            ),

            // 7) 하단 고정 스티키 저장 버튼
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isEditing ? Icons.check : Icons.add, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isEditing ? '수정 완료' : '일정에 추가하기',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1) 상단 6대 카테고리 3x2 카드 칩 그리드
  Widget _buildCategoryGrid3x2() {
    final categories = [
      'ATTRACTION',
      'DINING',
      'HOTEL',
      'FLIGHT',
      'TRANSIT',
      'AIRPORT',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '카테고리 선택',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildCategoryCard(categories[0])),
            const SizedBox(width: 8),
            Expanded(child: _buildCategoryCard(categories[1])),
            const SizedBox(width: 8),
            Expanded(child: _buildCategoryCard(categories[2])),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildCategoryCard(categories[3])),
            const SizedBox(width: 8),
            Expanded(child: _buildCategoryCard(categories[4])),
            const SizedBox(width: 8),
            Expanded(child: _buildCategoryCard(categories[5])),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String catKey) {
    final catData = AppTheme.categories[catKey];
    if (catData == null) return const SizedBox.shrink();

    final isSelected = _category == catKey;
    final themeColor = catData.color;

    return InkWell(
      onTap: () => setState(() => _category = catKey),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? themeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? themeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              catData.icon,
              size: 20,
              color: isSelected ? themeColor : AppTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              catData.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? themeColor : AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }



  /// 3) 핵심 정보 행: 일정 이름, 방문 일차 (현재 일차 자동 배정 & 원터치 칩 전환), 방문 시각
  Widget _buildCoreInfoSection() {
    final provider = context.read<TripProvider>();
    final maxDay = provider.maxDay;
    // 현재 선택 가능한 일차 목록: 1부터 max(maxDay, _day) + 1까지 제공하여 다음 일차도 쉽게 선택 가능
    final totalDaysAvailable = (_day > maxDay ? _day : maxDay) + 1;
    final dayList = List<int>.generate(totalDaysAvailable, (i) => i + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 일정 이름 (볼드)
        const Text(
          '일정 / 장소명 *',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          onChanged: _onTitleChanged,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          decoration: InputDecoration(
            hintText: '일정 / 장소명 입력',
            prefixIcon: const Icon(Icons.label_outline, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 방문 일차 선택 영역 (현재 일차 자동 배정 & 칩 전환)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '방문 일차',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.getDayColor(_day).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.getDayColor(_day).withValues(alpha: 0.3)),
              ),
              child: Text(
                'Day $_day 자동 배정',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.getDayColor(_day),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: dayList.map((d) {
              final isSelected = _day == d;
              final dayColor = AppTheme.getDayColor(d);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('Day $d'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _day = d);
                    }
                  },
                  selectedColor: dayColor,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide(
                    color: isSelected ? dayColor : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.5 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // 방문 시각
        const Text(
          '방문 시각 (선택)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _timeController,
          decoration: InputDecoration(
            hintText: '시각 선택',
            prefixIcon: const Icon(Icons.access_time, size: 18),
            suffixIcon: IconButton(
              icon: const Icon(Icons.schedule, color: AppTheme.primary, size: 20),
              tooltip: '시각 선택',
              onPressed: _pickTime,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
      ],
    );
  }

  /// 3) 구글맵 연동 장소 검색 및 좌표 등록 섹션
  Widget _buildGoogleMapsLocationSection() {
    final hasCoord = _lat != null && _lng != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasCoord ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: hasCoord ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    hasCoord ? Icons.check_circle : Icons.location_on,
                    size: 18,
                    color: hasCoord ? const Color(0xFF16A34A) : AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '위치 및 지도 좌표 (구글맵 연동)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              if (hasCoord)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '좌표 등록됨',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 2대 핵심 액션 버튼 (구글맵에서 찾기 & 클립보드 붙여넣기)
          Row(
            children: [
              // 1. 구글맵에서 장소 찾기
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.map_outlined, size: 16, color: AppTheme.primary),
                  label: const Text(
                    '구글맵에서 찾기',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 2. 클립보드 링크 붙여넣기
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 16, color: Colors.white),
                  label: const Text(
                    '클립보드 붙여넣기',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    backgroundColor: AppTheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 링크 또는 좌표 직접 입력창 + 적용 버튼
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coordPasteController,
                  style: const TextStyle(fontSize: 12),
                  onSubmitted: (_) => _applyCoordPaste(),
                  decoration: InputDecoration(
                    hintText: '구글맵 링크 또는 좌표(위도, 경도) 입력',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.link, size: 16, color: Color(0xFF64748B)),
                    suffixIcon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearching ? null : _applyCoordPaste,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('적용', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          // 인라인 상태 피드백 메시지 (적용 버튼 클릭 시 즉각적인 시각 피드백)
          if (_locationStatusMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _isLocationStatusError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isLocationStatusError ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isLocationStatusError ? Icons.info_outline : Icons.check_circle_outline,
                    size: 16,
                    color: _isLocationStatusError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationStatusMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isLocationStatusError ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 등록된 좌표 및 장소 상세 카드 (등록되어 있을 때 표시)
          if (hasCoord) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_address.isNotEmpty)
                          Text(
                            _address,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          '좌표: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: _address.isNotEmpty ? const Color(0xFF15803D) : const Color(0xFF166534),
                            fontWeight: _address.isEmpty ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '구글맵에서 확인',
                    icon: const Icon(Icons.open_in_new, size: 18, color: AppTheme.primary),
                    onPressed: _openInGoogleMaps,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: '좌표 삭제',
                    icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _lat = null;
                        _lng = null;
                        _coordPasteController.clear();
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '구글맵에서 장소를 찾은 후 [공유 -> 링크 복사]하여 붙여넣으면 장소명과 지도 좌표가 자동으로 등록됩니다.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  /// 5) 카테고리별 특화 필드 섹션
  Widget _buildCategorySpecificFields() {
    switch (_category) {
      case 'FLIGHT':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('출발편 (이륙)'),
                    selected: _flightType == 'DEPARTURE',
                    onSelected: (s) => setState(() => _flightType = 'DEPARTURE'),
                  ),
                  ChoiceChip(
                    label: const Text('도착편 (착륙)'),
                    selected: _flightType == 'ARRIVAL',
                    onSelected: (s) => setState(() => _flightType = 'ARRIVAL'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _airlineController,
                      decoration: const InputDecoration(labelText: '항공사'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _flightNoController,
                      decoration: const InputDecoration(labelText: '편명'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _airportController,
                      decoration: const InputDecoration(labelText: '공항 코드'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _terminalGateController,
                      decoration: const InputDecoration(labelText: '터미널 / 게이트'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seatController,
                      decoration: const InputDecoration(labelText: '좌석'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bookingRefController,
                      decoration: const InputDecoration(labelText: '예약번호 (PNR)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 'AIRPORT':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFEFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA5F3FC)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _baggageClaimController,
                      decoration: const InputDecoration(labelText: '수하물 수취대'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _transitToCityController,
                      decoration: const InputDecoration(labelText: '시내 이동 수단'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pickupInfoController,
                decoration: const InputDecoration(labelText: '픽업 / 탑승 위치'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customsMemoController,
                decoration: const InputDecoration(labelText: '입국 / 세관 메모'),
              ),
            ],
          ),
        );

      case 'HOTEL':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE9D5FF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkOutTimeController,
                      decoration: const InputDecoration(labelText: '체크아웃 시각'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _voucherNoController,
                      decoration: const InputDecoration(labelText: '예약 바우처 번호'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _passcodeController,
                      decoration: const InputDecoration(labelText: '도어락 비밀번호'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _luggageStorageController,
                      decoration: const InputDecoration(labelText: '짐 보관 안내'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 'ATTRACTION':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _openingHoursController,
                      decoration: const InputDecoration(labelText: '운영 시간'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bookingStatusController,
                      decoration: const InputDecoration(labelText: '예약 상태'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ticketCostController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: const InputDecoration(labelText: '1인당 입장료'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _tipsController,
                      decoration: const InputDecoration(labelText: '관람 팁'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 'DINING':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _mealType,
                      decoration: const InputDecoration(labelText: '식사 분류'),
                      items: const [
                        DropdownMenuItem(value: '조식', child: Text('조식')),
                        DropdownMenuItem(value: '중식', child: Text('중식')),
                        DropdownMenuItem(value: '석식', child: Text('석식')),
                        DropdownMenuItem(value: '카페/디저트', child: Text('카페 / 디저트')),
                        DropdownMenuItem(value: '바/주점', child: Text('바 / 이자카야')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _mealType = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(labelText: '결제 수단'),
                      items: const [
                        DropdownMenuItem(value: '카드', child: Text('신용/체크카드')),
                        DropdownMenuItem(value: '현금', child: Text('현금 (Cash)')),
                        DropdownMenuItem(value: '페이/모바일', child: Text('모바일 페이 / 교통카드')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMethod = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reservedForController,
                      decoration: const InputDecoration(labelText: '예약 정보'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _menuRecommendationController,
                      decoration: const InputDecoration(labelText: '추천 메뉴'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 'TRANSIT':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _transitMode,
                      decoration: const InputDecoration(labelText: '이동 수단'),
                      items: const [
                        DropdownMenuItem(value: '전철/지하철', child: Text('전철 / 지하철')),
                        DropdownMenuItem(value: '기차 (KTX/신칸센)', child: Text('기차 / 특급열차')),
                        DropdownMenuItem(value: '버스', child: Text('시내/고속버스')),
                        DropdownMenuItem(value: '택시', child: Text('택시 / 우버')),
                        DropdownMenuItem(value: '페리/선박', child: Text('페리 / 선박')),
                        DropdownMenuItem(value: '도보', child: Text('도보')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _transitMode = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _transitLineController,
                      decoration: const InputDecoration(labelText: '노선 / 열차명'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _departureStationController,
                      decoration: const InputDecoration(labelText: '출발지 / 출발역'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _arrivalStationController,
                      decoration: const InputDecoration(labelText: '도착지 / 도착역'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ticketOrSeatController,
                      decoration: const InputDecoration(labelText: '승차권 / 좌석'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _transferMemoController,
                      decoration: const InputDecoration(labelText: '환승 정보'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// 6) 비용 및 지불인 섹션
  Widget _buildExpenseSection(dynamic meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '경비 및 지불인',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  ThousandsSeparatorInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: '비용 (금액)',
                  prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _currency,
                decoration: InputDecoration(
                  labelText: '통화',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'KRW', child: Text('KRW')),
                  DropdownMenuItem(value: 'JPY', child: Text('JPY')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _currency = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: meta.participants.contains(_payer)
              ? _payer
              : (_payer == '공통' ? '공통' : (meta.participants.isNotEmpty ? meta.participants.first : '공통')),
          decoration: InputDecoration(
            labelText: '지불인',
            prefixIcon: const Icon(Icons.person_outline, size: 18),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
          items: [
            ...meta.participants.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))),
            const DropdownMenuItem<String>(value: '공통', child: Text('공통')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _payer = val);
          },
        ),
      ],
    );
  }

  /// 상세 메모 작성 섹션
  Widget _buildMemoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.notes_rounded, size: 16, color: AppTheme.textSecondary),
                SizedBox(width: 6),
                Text(
                  '상세 메모',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                ),
              ],
            ),
            Text(
              '안내사항, 예약 팁, 도어락 등 자유 작성',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _memoController,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: '일정에 대한 메모나 안내사항, 예약 팁, 도어락 번호 등을 자유롭게 입력하세요.',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

