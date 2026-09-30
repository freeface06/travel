/// @intent 여행 일정 타임라인 탭 - 슬롯 그룹핑(Plan A/B, 2-1/2-2) 다중 후보 탭 스위처, 플랜 확정 및 직관적 대안 추가 완비
/// @agent Gemini/manager-develop
/// @branch feat/flutter-travel-app
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

  void _addCandidate(BuildContext context, TripItem baseItem) {
    ItemEditDialog.showCandidate(context, baseItem: baseItem);
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

    // effectiveSlotId 기준으로 일차별 아이템을 슬롯 그룹핑
    final Map<String, List<TripItem>> slotMap = {};
    for (final item in items) {
      slotMap.putIfAbsent(item.effectiveSlotId, () => []).add(item);
    }

    final slots = slotMap.entries.map((entry) {
      return _TimelineSlot(
        slotId: entry.key,
        day: entry.value.first.day,
        candidates: entry.value,
      );
    }).toList();

    // 마커 탭 또는 외부 선택에 의한 자동 스크롤 연동
    final selectedId = provider.selectedItemId;
    if (selectedId != null && selectedId != _lastSelectedItemId) {
      _lastSelectedItemId = selectedId;
      final targetSlotIndex = slots.indexWhere((s) => s.candidates.any((i) => i.id == selectedId));
      if (targetSlotIndex != -1 && widget.scrollController != null && widget.scrollController!.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.scrollController == null || !widget.scrollController!.hasClients) return;
          final targetOffset = (targetSlotIndex * 145.0).clamp(0.0, widget.scrollController!.position.maxScrollExtent);
          widget.scrollController!.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        });
      }
    }

    if (slots.isEmpty) {
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
      itemCount: slots.length,
      onReorderItem: (oldIndex, newIndex) {
        // 슬롯의 대표 아이템 위치를 기준으로 재배치
        if (oldIndex < 0 || oldIndex >= slots.length) return;
        final oldSlot = slots[oldIndex];
        final oldItemRealIndex = items.indexWhere((i) => i.id == oldSlot.activeCandidate.id);

        int newItemRealIndex;
        if (newIndex >= slots.length) {
          newItemRealIndex = items.length;
        } else {
          final targetSlot = slots[newIndex];
          newItemRealIndex = items.indexWhere((i) => i.id == targetSlot.activeCandidate.id);
        }

        if (oldItemRealIndex != -1 && newItemRealIndex != -1) {
          context.read<TripProvider>().reorderItems(oldItemRealIndex, newItemRealIndex);
        }
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
      itemBuilder: (context, slotIndex) {
        final slot = slots[slotIndex];
        final isSelectedInProvider = slot.candidates.any((i) => i.id == provider.selectedItemId);

        return _TimelineSlotCard(
          key: ValueKey(slot.slotId),
          slotIndex: slotIndex,
          slot: slot,
          isSelectedInProvider: isSelectedInProvider,
          onItemTap: widget.onItemTap,
          onShowDetail: _showItemDetail,
          onEdit: _editItem,
          onDelete: _deleteItem,
          onAddCandidate: _addCandidate,
          onSelectCandidate: (targetId) {
            context.read<TripProvider>().selectCandidate(targetId);
            final target = slot.candidates.firstWhere((c) => c.id == targetId, orElse: () => slot.activeCandidate);
            AppToast.success(context, '\'${target.title}\' 플랜으로 확정되었습니다.');
          },
        );
      },
    );
  }
}

class _TimelineSlot {
  final String slotId;
  final int day;
  final List<TripItem> candidates;

  _TimelineSlot({
    required this.slotId,
    required this.day,
    required this.candidates,
  });

  TripItem get activeCandidate =>
      candidates.firstWhere((c) => c.isSelected, orElse: () => candidates.first);
}

class _TimelineSlotCard extends StatefulWidget {
  final int slotIndex;
  final _TimelineSlot slot;
  final bool isSelectedInProvider;
  final void Function(TripItem item)? onItemTap;
  final void Function(BuildContext context, TripItem item) onShowDetail;
  final void Function(BuildContext context, TripItem item) onEdit;
  final void Function(BuildContext context, TripItem item) onDelete;
  final void Function(BuildContext context, TripItem item) onAddCandidate;
  final void Function(String targetItemId) onSelectCandidate;

  const _TimelineSlotCard({
    super.key,
    required this.slotIndex,
    required this.slot,
    required this.isSelectedInProvider,
    this.onItemTap,
    required this.onShowDetail,
    required this.onEdit,
    required this.onDelete,
    required this.onAddCandidate,
    required this.onSelectCandidate,
  });

  @override
  State<_TimelineSlotCard> createState() => _TimelineSlotCardState();
}

class _TimelineSlotCardState extends State<_TimelineSlotCard> {
  String? _previewItemId;

  @override
  void didUpdateWidget(covariant _TimelineSlotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.slot.candidates.any((c) => c.id == _previewItemId)) {
      _previewItemId = null;
    }
  }

  TripItem get currentItem {
    if (_previewItemId != null) {
      final found = widget.slot.candidates.firstWhere(
        (c) => c.id == _previewItemId,
        orElse: () => widget.slot.activeCandidate,
      );
      return found;
    }
    return widget.slot.activeCandidate;
  }

  /// 복수 후보 존재 시 세그먼트 알약 스위처 바 렌더링
  Widget _buildCandidateSwitcherBar(BuildContext context) {
    final candidates = widget.slot.candidates;
    if (candidates.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...candidates.map((candidate) {
              final isCurrentPreview = candidate.id == currentItem.id;
              final isConfirmed = candidate.isSelected;

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _previewItemId = candidate.id;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCurrentPreview
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isCurrentPreview
                            ? AppTheme.primary
                            : (isConfirmed ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
                        width: isCurrentPreview ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isConfirmed) ...[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '${widget.slotIndex + 1}-${candidate.candidateLabel}: ${candidate.title}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrentPreview ? FontWeight.bold : FontWeight.w600,
                            color: isCurrentPreview
                                ? AppTheme.primary
                                : (isConfirmed ? const Color(0xFF047857) : const Color(0xFF475569)),
                          ),
                        ),
                        if (isConfirmed) ...[
                          const SizedBox(width: 3),
                          const Text(
                            '(확정)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),

            // + 대안 추가 버튼
            InkWell(
              onTap: () => widget.onAddCandidate(context, currentItem),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: Color(0xFF64748B)),
                    SizedBox(width: 3),
                    Text(
                      '대안 추가',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 미확정 후보 보고 있을 때 하단 원터치 확정 버튼
  Widget _buildConfirmPlanButton(BuildContext context) {
    if (widget.slot.candidates.length <= 1 || currentItem.isSelected) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
        label: Text('이 플랜으로 확정 (Plan ${currentItem.candidateLabel})'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          widget.onSelectCandidate(currentItem.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = currentItem;
    final catMeta = AppTheme.getCategoryMeta(item.category);
    final dayColor = AppTheme.getDayColor(item.day);
    final hasMultiple = widget.slot.candidates.length > 1;
    final slotLabel = hasMultiple
        ? '${widget.slotIndex + 1}-${item.candidateLabel}'
        : '${widget.slotIndex + 1}';

    return Card(
      key: ValueKey(widget.slot.slotId),
      margin: const EdgeInsets.only(bottom: 12),
      color: widget.isSelectedInProvider ? const Color(0xFFEFF6FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isSelectedInProvider ? AppTheme.primary : AppTheme.border,
          width: widget.isSelectedInProvider ? 2.0 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.read<TripProvider>().setSelectedItemId(item.id);
          widget.onShowDetail(context, item);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 후보가 2개 이상일 때 상단 세그먼트 알약 스위처 바
              _buildCandidateSwitcherBar(context),

              // 2. 상단 헤더: 순번/일차 배지, 카테고리 배지, 시간, 팝업 액션 메뉴
              Row(
                children: [
                  // 순번 배지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: dayColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      slotLabel,
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
                  if (hasMultiple) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.isSelected ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: item.isSelected ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        item.isSelected ? '확정 플랜' : '후보 플랜',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: item.isSelected ? const Color(0xFF059669) : const Color(0xFF64748B),
                        ),
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
                        widget.onShowDetail(context, item);
                      } else if (action == 'add_candidate') {
                        widget.onAddCandidate(context, item);
                      } else if (action == 'edit') {
                        widget.onEdit(context, item);
                      } else if (action == 'delete') {
                        widget.onDelete(context, item);
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
                        value: 'add_candidate',
                        height: 40,
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.alt_route_rounded,
                                size: 16,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              '대안(플랜 B) 추가',
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
                    index: widget.slotIndex,
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

              // 3. 제목
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),

              // 4. 주소 표시
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

              // 5. 카테고리별 특화 필드 칩들
              const SizedBox(height: 8),
              _buildSpecificDetailChips(item),

              // 6. 비용 및 지불인
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

              // 7. 메모
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

              // 8. 사진 갤러리 및 구글맵 장소 사진
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

              // 9. 미확정 후보일 때 하단 원터치 확정 버튼
              _buildConfirmPlanButton(context),
            ],
          ),
        ),
      ),
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
