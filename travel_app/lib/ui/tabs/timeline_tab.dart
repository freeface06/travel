/// @intent 여행 일정 타임라인 탭 - 일차별/전체 일정 카드 뷰 및 빈 일정 화면 내 직관적 일정 추가 버튼 완비
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trip_item.dart';
import '../../providers/trip_provider.dart';
import '../../services/expense_calculator.dart';
import '../dialogs/item_edit_dialog.dart';
import '../sheets/item_detail_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_menu_divider.dart';
import '../widgets/app_toast.dart';
import '../widgets/place_photo_preview_card.dart';

class TimelineTab extends StatefulWidget {
  final ScrollController? scrollController;
  final void Function(TripItem item)? onItemTap;

  const TimelineTab({super.key, this.scrollController, this.onItemTap});

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  String? _lastSelectedItemId;

  void _showItemDetail(BuildContext context, TripItem item) {
    final provider = context.read<TripProvider>();
    ItemDetailSheet.show(
      context,
      item: item,
      onFocusMap: () {
        provider.setSelectedItemId(item.id);
        if (item.hasCoordinates) {
          provider.setActiveTab('map');
          if (widget.onItemTap != null) {
            widget.onItemTap!(item);
          }
        }
      },
      onEdit: () {
        _editItem(context, item);
      },
    );
  }

  void _editItem(BuildContext context, TripItem item) {
    ItemEditDialog.show(context, item: item);
  }

  void _deleteItem(BuildContext context, TripItem item) async {
    final confirmed = await AppDialog.confirm(
      context,
      type: AppDialogType.danger,
      icon: Icons.delete_outline_rounded,
      title: '일정 삭제',
      message: '\'${item.title}\' 일정을 삭제하시겠습니까?\n삭제된 일정은 복구할 수 없습니다.',
      confirmText: '삭제',
    );

    if (confirmed == true && context.mounted) {
      final title = item.title;
      context.read<TripProvider>().deleteItem(item.id);
      AppToast.success(context, '\'$title\' 일정이 삭제되었습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final items = provider.itemsForSelectedDay;

    // 마커 탭 또는 외부 선택에 의한 자동 스크롤 연동
    final selectedId = provider.selectedItemId;
    if (selectedId != null && selectedId != _lastSelectedItemId) {
      _lastSelectedItemId = selectedId;
      final targetIndex = items.indexWhere((i) => i.id == selectedId);
      if (targetIndex != -1 && widget.scrollController != null && widget.scrollController!.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.scrollController == null || !widget.scrollController!.hasClients) return;
          final targetOffset = (targetIndex * 135.0).clamp(0.0, widget.scrollController!.position.maxScrollExtent);
          widget.scrollController!.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        });
      }
    }

    if (items.isEmpty) {
      return SingleChildScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_note, size: 56, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                Text(
                  provider.selectedDay == 'all'
                      ? '등록된 일정이 없습니다.'
                      : 'Day ${provider.selectedDay}에 등록된 일정이 없습니다.',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ItemEditDialog.show(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('일정 추가'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      scrollController: widget.scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) {
        context.read<TripProvider>().reorderItems(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 6,
          color: Colors.transparent,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final catMeta = AppTheme.getCategoryMeta(item.category);
        final dayColor = AppTheme.getDayColor(item.day);
        final isSelected = provider.selectedItemId == item.id;

        return Card(
          key: ValueKey(item.id),
          margin: const EdgeInsets.only(bottom: 12),
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? AppTheme.primary : AppTheme.border,
              width: isSelected ? 2.0 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              provider.setSelectedItemId(item.id);
              _showItemDetail(context, item);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 헤더: 일차 배지, 카테고리 배지, 시간, 팝업 액션 메뉴
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: dayColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Day ${item.day}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: dayColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: catMeta.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(catMeta.icon, size: 12, color: catMeta.color),
                            const SizedBox(width: 4),
                            Text(
                              catMeta.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: catMeta.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          item.time,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      if (item.photos.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_camera, size: 12, color: AppTheme.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                '${item.photos.length}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      PopupMenuButton<String>(
                        elevation: 6,
                        shadowColor: const Color(0x1E0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        offset: const Offset(0, 36),
                        padding: EdgeInsets.zero,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: Color(0xFF475569),
                          ),
                        ),
                        onSelected: (action) {
                          if (action == 'detail') {
                            _showItemDetail(context, item);
                          } else if (action == 'edit') {
                            _editItem(context, item);
                          } else if (action == 'delete') {
                            _deleteItem(context, item);
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'detail',
                            height: 40,
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.visibility_outlined,
                                    size: 16,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '상세보기',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const AppMenuDivider(),
                          PopupMenuItem(
                            value: 'edit',
                            height: 40,
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '수정',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const AppMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            height: 40,
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '삭제',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 2),
                      ReorderableDragStartListener(
                        index: index,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: const Icon(
                            Icons.drag_indicator,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 제목
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),

                  // 주소 표시
                  if (item.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.address,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 카테고리별 특화 필드 칩들
                  const SizedBox(height: 8),
                  _buildSpecificDetailChips(item),

                  // 비용 및 지불인
                  if (item.cost > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_balance_wallet, size: 13, color: AppTheme.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                ExpenseCalculator.formatAmount(item.cost, item.currency),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              if (item.payer.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${item.payer} 결제)',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 메모
                  if (item.memo.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        item.memo,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      ),
                    ),
                  ],

                  // 사진 갤러리 및 구글맵 장소 사진 (가로 스크롤 & 전체보기 지원)
                  if (item.photos.isNotEmpty || item.locationUrl.isNotEmpty || item.hasCoordinates) ...[
                    const SizedBox(height: 10),
                    PlacePhotoPreviewCard(
                      title: item.title,
                      locationUrl: item.locationUrl,
                      lat: item.lat,
                      lng: item.lng,
                      address: item.address,
                      personalPhotos: item.photos,
                      showHeader: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpecificDetailChips(TripItem item) {
    final List<Widget> chips = [];

    void addChip(IconData icon, String label, String value) {
      if (value.isNotEmpty) {
        chips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '$label: $value',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
        );
      }
    }

    switch (item.category) {
      case 'FLIGHT':
        addChip(Icons.flight, '편명', item.flightNo);
        addChip(Icons.airline_seat_recline_extra, '좌석', item.seat);
        addChip(Icons.meeting_room, '게이트', item.terminalGate);
        addChip(Icons.confirmation_number, '예약번호', item.bookingRef);
        break;
      case 'AIRPORT':
        addChip(Icons.luggage, '수하물', item.baggageClaim);
        addChip(Icons.directions_bus, '환승', item.transitToCity);
        addChip(Icons.pin_drop, '탑승홈', item.pickupInfo);
        break;
      case 'HOTEL':
        addChip(Icons.logout, '체크아웃', item.checkOutTime);
        addChip(Icons.lock, '비밀번호', item.passcode);
        addChip(Icons.receipt, '바우처', item.voucherNo);
        addChip(Icons.work, '짐보관', item.luggageStorage);
        break;
      case 'ATTRACTION':
        addChip(Icons.schedule, '운영', item.openingHours);
        addChip(Icons.bookmark, '예약', item.bookingStatus);
        if (item.ticketCostPerPerson > 0) {
          addChip(Icons.local_activity, '입장료', ExpenseCalculator.formatAmount(item.ticketCostPerPerson, item.currency));
        }
        addChip(Icons.lightbulb, '팁', item.tips);
        break;
      case 'DINING':
        addChip(Icons.restaurant_menu, '분류', item.mealType);
        addChip(Icons.payment, '결제', item.paymentMethod);
        addChip(Icons.book_online, '예약자', item.reservedFor);
        addChip(Icons.thumb_up, '추천', item.menuRecommendation);
        break;
      case 'TRANSIT':
        addChip(Icons.commute, '수단', item.transitMode);
        addChip(Icons.subway, '노선', item.transitLine);
        if (item.departureStation.isNotEmpty && item.arrivalStation.isNotEmpty) {
          addChip(Icons.alt_route, '구간', '${item.departureStation} -> ${item.arrivalStation}');
        }
        addChip(Icons.event_seat, '좌석', item.ticketOrSeat);
        break;
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }
}
