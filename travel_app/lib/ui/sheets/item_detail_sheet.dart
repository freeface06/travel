/// @intent 일정 상세 정보를 카드 형식으로 완벽하게 조회할 수 있는 바텀 시트 (위치, 지도 이동, 구글맵 연동, 카테고리별 세부 스펙, 정산 내역, 메모 복사, 사진 갤러리 지원)
/// @agent Gemini/manager-develop
/// @branch feat/item-detail-sheet
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/trip_item.dart';
import '../../providers/trip_provider.dart';
import '../../services/expense_calculator.dart';
import '../dialogs/item_edit_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/place_photo_preview_card.dart';

class ItemDetailSheet extends StatefulWidget {
  final TripItem item;
  final VoidCallback? onFocusMap;
  final VoidCallback? onEdit;

  const ItemDetailSheet({
    super.key,
    required this.item,
    this.onFocusMap,
    this.onEdit,
  });

  /// 바텀 시트 모달 표시 헬퍼
  static Future<void> show(
    BuildContext context, {
    required TripItem item,
    VoidCallback? onFocusMap,
    VoidCallback? onEdit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ItemDetailSheet(
        item: item,
        onFocusMap: onFocusMap,
        onEdit: onEdit,
      ),
    );
  }

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  late TripItem _item;

  TripItem get item => _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _openDirections(BuildContext context) async {
    Uri? uri;
    if (item.hasCoordinates) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${item.lat},${item.lng}&hl=ko');
    } else if (item.address.isNotEmpty) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(item.address)}&hl=ko');
    } else if (item.title.isNotEmpty) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(item.title)}&hl=ko');
    }

    if (uri != null) {
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await launchUrl(uri);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.error(context, '길찾기를 실행할 수 없습니다.');
        }
      }
    } else {
      if (context.mounted) {
        AppToast.warning(context, '위치 정보가 없습니다.');
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, '$label이(가) 클립보드에 복사되었습니다.');
  }

  Future<void> _openGoogleMaps(BuildContext context) async {
    Uri? uri;
    if (item.hasCoordinates) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}&hl=ko');
    } else if (item.address.isNotEmpty) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(item.address)}&hl=ko');
    } else if (item.title.isNotEmpty) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(item.title)}&hl=ko');
    }

    if (uri != null) {
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await launchUrl(uri);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.error(context, '구글맵 앱을 실행할 수 없습니다.');
        }
      }
    } else {
      if (context.mounted) {
        AppToast.warning(context, '위치 정보가 없습니다.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final baseCurrency = provider.currentTrip.metadata.baseCurrency;
    final customRates = provider.currentTrip.metadata.customRates;

    final catMeta = AppTheme.getCategoryMeta(item.category);
    final dayColor = AppTheme.getDayColor(item.day);
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

            // 상단 헤더 바 (뱃지 및 닫기 버튼)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  // Day 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: dayColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Day ${item.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: dayColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 카테고리 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: catMeta.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(catMeta.icon, size: 14, color: catMeta.color),
                        const SizedBox(width: 5),
                        Text(
                          catMeta.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: catMeta.color,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 시간 뱃지
                  if (item.time.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded, size: 13, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            item.time,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // 닫기 버튼
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

            // 일정 제목
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                  height: 1.3,
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // 스크롤 가능한 본문 상세 내역
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 구글맵 장소 카드 & 고화질 사진 갤러리 (Image 1 & 2 스타일)
                    if (item.title.isNotEmpty || item.locationUrl.isNotEmpty || item.hasCoordinates || item.photos.isNotEmpty) ...[
                      PlacePhotoPreviewCard(
                        title: item.title,
                        locationUrl: item.locationUrl,
                        lat: item.lat,
                        lng: item.lng,
                        address: item.address,
                        personalPhotos: item.photos,
                        showHeader: true,
                        onDirections: () => _openDirections(context),
                        onFocusMap: widget.onFocusMap != null
                            ? () {
                                Navigator.of(context).pop();
                                widget.onFocusMap!();
                              }
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 2. 위치 및 지도 연동 카드
                    if (item.address.isNotEmpty || item.hasCoordinates) ...[
                      _buildLocationCard(context),
                      const SizedBox(height: 16),
                    ],

                    // 3. 카테고리별 특화 상세 정보 카드
                    if (_hasCategoryDetails()) ...[
                      _buildCategorySpecificCard(context, catMeta),
                      const SizedBox(height: 16),
                    ],

                    // 4. 지출 및 정산 내역 카드
                    if (item.cost > 0) ...[
                      _buildExpenseCard(baseCurrency, customRates),
                      const SizedBox(height: 16),
                    ],

                    // 5. 상세 메모 카드
                    if (item.memo.isNotEmpty) ...[
                      _buildMemoCard(context),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // 하단 고정 액션 버튼 바
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  // 수정 버튼
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onEdit != null) {
                          widget.onEdit!();
                        } else {
                          ItemEditDialog.show(context, item: _item);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('일정 수정'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.2),
                        backgroundColor: const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 닫기 버튼
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('확인'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF1E293B),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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

  /// 위치 및 지도 연동 섹션
  Widget _buildLocationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '위치 및 장소',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      item.address.isNotEmpty ? item.address : '좌표 등록 위치',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                    if (item.hasCoordinates) ...[
                      const SizedBox(height: 3),
                      Text(
                        '좌표: ${item.lat!.toStringAsFixed(5)}, ${item.lng!.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 지도 이동 & 구글맵 앱 버튼 바
          Row(
            children: [
              // 앱 내 지도에서 보기
              if (item.hasCoordinates)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onFocusMap?.call();
                    },
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('지도에서 보기'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              if (item.hasCoordinates) const SizedBox(width: 8),

              // 구글맵 앱에서 열기
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openGoogleMaps(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('구글맵 앱'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 카테고리별 특화 정보 존재 여부 판별
  bool _hasCategoryDetails() {
    switch (item.category) {
      case 'FLIGHT':
        return item.airline.isNotEmpty ||
            item.flightNo.isNotEmpty ||
            item.terminalGate.isNotEmpty ||
            item.seat.isNotEmpty ||
            item.bookingRef.isNotEmpty ||
            item.airport.isNotEmpty;
      case 'AIRPORT':
        return item.baggageClaim.isNotEmpty ||
            item.transitToCity.isNotEmpty ||
            item.pickupInfo.isNotEmpty ||
            item.customsMemo.isNotEmpty;
      case 'HOTEL':
        return item.checkOutTime.isNotEmpty ||
            item.voucherNo.isNotEmpty ||
            item.passcode.isNotEmpty ||
            item.luggageStorage.isNotEmpty;
      case 'ATTRACTION':
        return item.openingHours.isNotEmpty ||
            item.bookingStatus.isNotEmpty ||
            item.ticketCostPerPerson > 0 ||
            item.tips.isNotEmpty;
      case 'DINING':
        return item.mealType.isNotEmpty ||
            item.paymentMethod.isNotEmpty ||
            item.reservedFor.isNotEmpty ||
            item.menuRecommendation.isNotEmpty;
      case 'TRANSIT':
        return item.transitMode.isNotEmpty ||
            item.departureStation.isNotEmpty ||
            item.arrivalStation.isNotEmpty ||
            item.transitLine.isNotEmpty ||
            item.ticketOrSeat.isNotEmpty ||
            item.transferMemo.isNotEmpty;
      default:
        return false;
    }
  }

  /// 카테고리별 세부 스펙 카드 빌더
  Widget _buildCategorySpecificCard(BuildContext context, CategoryMeta catMeta) {
    final List<Widget> detailRows = [];

    switch (item.category) {
      case 'FLIGHT':
        if (item.flightType.isNotEmpty) {
          detailRows.add(_buildInfoRow('항공편 구분', item.flightType == 'DEPARTURE' ? '출발편' : '도착편'));
        }
        if (item.airline.isNotEmpty || item.flightNo.isNotEmpty) {
          detailRows.add(_buildInfoRow('항공사 / 편명', '${item.airline} ${item.flightNo}'.trim()));
        }
        if (item.airport.isNotEmpty) {
          detailRows.add(_buildInfoRow('공항', item.airport));
        }
        if (item.terminalGate.isNotEmpty) {
          detailRows.add(_buildInfoRow('터미널 / 탑승구', item.terminalGate));
        }
        if (item.seat.isNotEmpty) {
          detailRows.add(_buildInfoRow('좌석 번호', item.seat));
        }
        if (item.bookingRef.isNotEmpty) {
          detailRows.add(_buildCopyableRow(context, '예약 번호(PNR)', item.bookingRef));
        }
        break;

      case 'AIRPORT':
        if (item.baggageClaim.isNotEmpty) {
          detailRows.add(_buildInfoRow('수하물 수취대', item.baggageClaim));
        }
        if (item.transitToCity.isNotEmpty) {
          detailRows.add(_buildInfoRow('시내 이동 경로', item.transitToCity));
        }
        if (item.pickupInfo.isNotEmpty) {
          detailRows.add(_buildInfoRow('픽업 / 미팅 안내', item.pickupInfo));
        }
        if (item.customsMemo.isNotEmpty) {
          detailRows.add(_buildInfoRow('입국 / 세관 유의사항', item.customsMemo));
        }
        break;

      case 'HOTEL':
        if (item.checkOutTime.isNotEmpty) {
          detailRows.add(_buildInfoRow('체크아웃 시간', item.checkOutTime));
        }
        if (item.voucherNo.isNotEmpty) {
          detailRows.add(_buildCopyableRow(context, '예약/바우처 번호', item.voucherNo));
        }
        if (item.passcode.isNotEmpty) {
          detailRows.add(_buildHighlightedPasscodeCard(context, item.passcode));
        }
        if (item.luggageStorage.isNotEmpty) {
          detailRows.add(_buildInfoRow('짐 보관(Luggage)', item.luggageStorage));
        }
        break;

      case 'ATTRACTION':
        if (item.openingHours.isNotEmpty) {
          detailRows.add(_buildInfoRow('운영 시간', item.openingHours));
        }
        if (item.bookingStatus.isNotEmpty) {
          detailRows.add(_buildInfoRow('예약 상태', item.bookingStatus));
        }
        if (item.ticketCostPerPerson > 0) {
          detailRows.add(_buildInfoRow(
            '1인당 티켓 요금',
            ExpenseCalculator.formatAmount(item.ticketCostPerPerson, item.currency),
          ));
        }
        if (item.tips.isNotEmpty) {
          detailRows.add(_buildInfoRow('방문 꿀팁 / 가이드', item.tips));
        }
        break;

      case 'DINING':
        if (item.mealType.isNotEmpty) {
          detailRows.add(_buildInfoRow('식사 구분', item.mealType));
        }
        if (item.reservedFor.isNotEmpty) {
          detailRows.add(_buildInfoRow('예약자 명의', item.reservedFor));
        }
        if (item.paymentMethod.isNotEmpty) {
          detailRows.add(_buildInfoRow('결제 방식', item.paymentMethod));
        }
        if (item.menuRecommendation.isNotEmpty) {
          detailRows.add(_buildInfoRow('추천 메뉴 / 시그니처', item.menuRecommendation));
        }
        break;

      case 'TRANSIT':
        if (item.transitMode.isNotEmpty) {
          detailRows.add(_buildInfoRow('교통 수단', item.transitMode));
        }
        if (item.departureStation.isNotEmpty || item.arrivalStation.isNotEmpty) {
          detailRows.add(_buildInfoRow(
            '이동 구간',
            '${item.departureStation.isEmpty ? '-' : item.departureStation} → ${item.arrivalStation.isEmpty ? '-' : item.arrivalStation}',
          ));
        }
        if (item.transitLine.isNotEmpty) {
          detailRows.add(_buildInfoRow('노선 / 열차 번호', item.transitLine));
        }
        if (item.ticketOrSeat.isNotEmpty) {
          detailRows.add(_buildInfoRow('탑승권 / 좌석 번호', item.ticketOrSeat));
        }
        if (item.transferMemo.isNotEmpty) {
          detailRows.add(_buildInfoRow('환승 / 하차 안내', item.transferMemo));
        }
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: catMeta.color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(catMeta.icon, size: 16, color: catMeta.color),
              const SizedBox(width: 6),
              Text(
                '${catMeta.label} 상세 내역',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: catMeta.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...detailRows,
        ],
      ),
    );
  }

  /// 도어락/비밀번호 강조 하이라이트 카드 (원터치 복사 지원)
  Widget _buildHighlightedPasscodeCard(BuildContext context, String passcode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_rounded, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          const Text(
            '도어락 비밀번호',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF92400E),
            ),
          ),
          const Spacer(),
          Text(
            passcode,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
              color: Color(0xFF78350F),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFFB45309)),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _copyToClipboard(context, passcode, '도어락 비밀번호'),
          ),
        ],
      ),
    );
  }

  /// 복사 버튼이 포함된 정보 행
  Widget _buildCopyableRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF64748B)),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: EdgeInsets.zero,
            onPressed: () => _copyToClipboard(context, value, label),
          ),
        ],
      ),
    );
  }

  /// 표준 정보 행
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 지출 및 결제자 내역 카드
  Widget _buildExpenseCard(String baseCurrency, Map<String, double> customRates) {
    final originalFormatted = ExpenseCalculator.formatAmount(item.cost, item.currency);
    String? convertedFormatted;

    if (item.currency.toUpperCase() != baseCurrency.toUpperCase()) {
      final converted = ExpenseCalculator.convertCurrency(
        item.cost,
        fromCurrency: item.currency,
        toCurrency: baseCurrency,
        customRates: customRates,
      );
      convertedFormatted = '약 ${ExpenseCalculator.formatAmount(converted, baseCurrency)}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payments_outlined, color: Color(0xFF059669), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지출 금액 및 결제자',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      originalFormatted,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (convertedFormatted != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '($convertedFormatted)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.payer.isEmpty ? '공통' : item.payer,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 상세 메모 카드 (원터치 복사 지원)
  Widget _buildMemoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              const Text(
                '상세 메모',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF64748B)),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
                onPressed: () => _copyToClipboard(context, item.memo, '메모'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            item.memo,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
