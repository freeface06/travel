/*
 * @intent 다중 여행 계획 관리(목록/전환/생성/복제/삭제/초기화) 및 계획 한눈에 비교 UI/UX 개선 모달 다이얼로그
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-30
 */
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trip.dart';
import '../../models/trip_item.dart';
import '../../models/trip_metadata.dart';
import '../../providers/trip_provider.dart';
import '../../services/expense_calculator.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_menu_divider.dart';

class TripManagerDialog extends StatefulWidget {
  const TripManagerDialog({super.key});

  @override
  State<TripManagerDialog> createState() => _TripManagerDialogState();
}

class _TripManagerDialogState extends State<TripManagerDialog> {
  int _selectedSegment = 0; // 0: 계획 목록, 1: 계획 비교

  void _createNewTrip(BuildContext context) async {
    final title = await AppDialog.prompt(
      context,
      type: AppDialogType.primary,
      icon: Icons.add_circle_outline_rounded,
      title: '새 여행 계획 생성',
      message: '새로운 여행 계획의 제목을 입력해 주세요.',
      initialValue: '새로운 여행 계획',
      hintText: '여행 제목 입력',
      confirmText: '생성',
    );

    if (title != null && title.isNotEmpty && context.mounted) {
      context.read<TripProvider>().createTrip(
            metadata: TripMetadata(
              id: '',
              title: title,
              startDate: '',
              endDate: '',
            ),
          );
    }
  }

  void _confirmClearItems(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context,
      type: AppDialogType.danger,
      icon: Icons.warning_amber_rounded,
      title: '일정 전체 비우기',
      message: '현재 활성화된 여행의 모든 일정을 삭제하고 빈 상태로 만드시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
      confirmText: '일정 비우기',
    );

    if (confirmed == true && context.mounted) {
      context.read<TripProvider>().clearCurrentTripItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final trips = provider.trips;
    final currentTripId = provider.currentTripId;
    final mediaQuery = MediaQuery.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: mediaQuery.size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 다이얼로그 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.folder_copy_outlined, color: AppTheme.primary, size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: Text(
                            '여행 계획 관리 및 비교',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. 상단 세련된 세그먼트 컨트롤 탭 (계획 목록 vs 계획 비교)
              _buildSegmentControl(trips.length),
              const SizedBox(height: 14),

              // 3. 본문 내용부 (탭별 전환)
              Expanded(
                child: _selectedSegment == 0
                    ? _buildTripListTab(context, trips, currentTripId)
                    : _buildTripComparisonTab(trips, currentTripId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 상단 세련된 세그먼트 컨트롤 탭 (고대비 가독성 보장)
  Widget _buildSegmentControl(int tripCount) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // 탭 1: 계획 목록
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() => _selectedSegment = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _selectedSegment == 0 ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _selectedSegment == 0
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.format_list_bulleted,
                        size: 17,
                        color: _selectedSegment == 0 ? Colors.white : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '계획 목록',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _selectedSegment == 0 ? FontWeight.bold : FontWeight.w600,
                          color: _selectedSegment == 0 ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _selectedSegment == 0
                              ? Colors.white.withValues(alpha: 0.25)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$tripCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _selectedSegment == 0 ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 탭 2: 계획 한눈에 비교
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() => _selectedSegment = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _selectedSegment == 1 ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _selectedSegment == 1
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.compare_arrows,
                        size: 17,
                        color: _selectedSegment == 1 ? Colors.white : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '계획 한눈에 비교',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _selectedSegment == 1 ? FontWeight.bold : FontWeight.w600,
                            color: _selectedSegment == 1 ? Colors.white : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1) 계획 목록 탭
  Widget _buildTripListTab(BuildContext context, List<Trip> trips, String currentTripId) {
    return Column(
      children: [
        // 상단 액션 바 (화면 너비에 유연하게 반응하는 Wrap)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => _createNewTrip(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('새 계획 만들기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmClearItems(context),
              icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.redAccent),
              label: const Text('현재 일정 모두 비우기', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 계획 카드 리스트
        Expanded(
          child: ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final trip = trips[index];
              final isCurrent = trip.metadata.id == currentTripId;
              final summary = ExpenseCalculator.calculateExpenseSummary(
                trip.items,
                trip.metadata.participants,
                baseCurrency: trip.metadata.baseCurrency,
                customRates: trip.metadata.customRates,
              );

              final placeCount = trip.items.where((i) => i.hasCoordinates).length;
              int maxD = 1;
              for (final i in trip.items) {
                if (i.day > maxD) maxD = i.day;
              }

              final participantCount = trip.metadata.participants.isNotEmpty
                  ? trip.metadata.participants.length
                  : 1;
              final perPersonCost = (summary.totalInBase / participantCount).roundToDouble();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFFEEF2FF) : Colors.white,
                  border: Border.all(
                    color: isCurrent ? AppTheme.primary : AppTheme.border,
                    width: isCurrent ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: isCurrent
                          ? AppTheme.primary.withValues(alpha: 0.18)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: isCurrent ? 12 : 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상단 헤더: 현재 사용 중 배지, 타이틀, 팝업 액션 메뉴
                    Row(
                      children: [
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 12, color: Colors.white),
                                SizedBox(width: 3),
                                Text(
                                  '현재 사용 중',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: Text(
                            trip.metadata.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          offset: const Offset(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          elevation: 6,
                          shadowColor: const Color(0x1E0F172A),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.more_vert,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          onSelected: (action) async {
                            if (action == 'switch') {
                              context.read<TripProvider>().switchTrip(trip.metadata.id);
                            } else if (action == 'duplicate') {
                              context.read<TripProvider>().duplicateTrip(trip.metadata.id);
                            } else if (action == 'delete') {
                              final confirmed = await AppDialog.confirm(
                                context,
                                type: AppDialogType.danger,
                                icon: Icons.folder_delete_outlined,
                                title: '여행 계획 삭제',
                                message: '\'${trip.metadata.title}\' 계획을 삭제하시겠습니까?\n포함된 모든 일정과 경비 내역이 영구 삭제됩니다.',
                                confirmText: '삭제',
                              );
                              if (confirmed == true && context.mounted) {
                                context.read<TripProvider>().deleteTrip(trip.metadata.id);
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (!isCurrent) ...[
                              PopupMenuItem(
                                value: 'switch',
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 16,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      '이 계획으로 전환',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const AppMenuDivider(),
                            ],
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.content_copy_rounded,
                                    size: 16,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '사본 만들기 (복제)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (trips.length > 1) ...[
                            const AppMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    '삭제',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 4대 핵심 메트릭 칩 그리드 (기간, 장소, 총 경비 및 1인당 금액, 인원)
                    _buildMetricGrid4(
                      trip: trip,
                      placeCount: placeCount,
                      maxD: maxD,
                      totalCost: summary.totalInBase,
                      perPersonCost: perPersonCost,
                      participantCount: participantCount,
                    ),

                    // 비활성 계획일 때 하단 빠른 전환 바
                    if (!isCurrent) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            context.read<TripProvider>().switchTrip(trip.metadata.id);
                          },
                          icon: const Icon(Icons.arrow_circle_right_outlined, size: 16),
                          label: const Text('이 계획으로 전환하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 4대 핵심 메트릭 칩 그리드
  Widget _buildMetricGrid4({
    required Trip trip,
    required int placeCount,
    required int maxD,
    required double totalCost,
    required double perPersonCost,
    required int participantCount,
  }) {
    final durationStr = trip.metadata.startDate.isNotEmpty && trip.metadata.endDate.isNotEmpty
        ? '${trip.metadata.startDate} ~ ${trip.metadata.endDate}'
        : '기간 미지정';

    final participantsStr = trip.metadata.participants.isNotEmpty
        ? '${trip.metadata.participants.length}명 (${trip.metadata.participants.join(', ')})'
        : '인원 미지정';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.calendar_today_outlined,
                label: '기간',
                value: durationStr,
                iconColor: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.place_outlined,
                label: '장소 및 일정',
                value: '장소 $placeCount곳 • 총 ${trip.items.length}개 ($maxD일차)',
                iconColor: const Color(0xFF059669),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.account_balance_wallet_outlined,
                label: '총 경비 (1인당)',
                value: '${ExpenseCalculator.formatAmount(totalCost, trip.metadata.baseCurrency)} (${ExpenseCalculator.formatAmount(perPersonCost, trip.metadata.baseCurrency)})',
                iconColor: const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.people_outline,
                label: '참여 인원',
                value: participantsStr,
                iconColor: const Color(0xFFD97706),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2) 계획 한눈에 비교 탭
  Widget _buildTripComparisonTab(List<Trip> trips, String currentTripId) {
    if (trips.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.compare_arrows, size: 54, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              const Text(
                '비교할 여행 계획이 부족합니다.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '새 계획을 추가하거나 기존 계획을 복제하면 상호 경비 및 일차별 동선을 비교할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _createNewTrip(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('새 계획 만들기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '계획별 핵심 지표 및 동선 비교',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          '각 계획의 총 경비, 1인당 분담금 및 일차별 연결 동선을 가로로 스크롤하며 비교하세요.',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, idx) {
              final t = trips[idx];
              final isCurrent = t.metadata.id == currentTripId;
              final summary = ExpenseCalculator.calculateExpenseSummary(
                t.items,
                t.metadata.participants,
                baseCurrency: t.metadata.baseCurrency,
                customRates: t.metadata.customRates,
              );
              final placeCount = t.items.where((i) => i.hasCoordinates).length;
              final participantCount = t.metadata.participants.isNotEmpty
                  ? t.metadata.participants.length
                  : 1;
              final perPerson = (summary.totalInBase / participantCount).roundToDouble();

              return Container(
                width: 270,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFFEFF6FF) : Colors.white,
                  border: Border.all(
                    color: isCurrent ? AppTheme.primary : AppTheme.border,
                    width: isCurrent ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isCurrent
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더: 타이틀 & 활성 배지
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.metadata.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '사용 중',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 16),

                    // 2x2 핵심 지표 카드
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildCompareRow('총 예상 경비', ExpenseCalculator.formatAmount(summary.totalInBase, t.metadata.baseCurrency), isHighlight: true),
                          const Divider(height: 10, color: Color(0xFFF1F5F9)),
                          _buildCompareRow('1인 평균 경비', ExpenseCalculator.formatAmount(perPerson, t.metadata.baseCurrency)),
                          const Divider(height: 10, color: Color(0xFFF1F5F9)),
                          _buildCompareRow('일정 / 장소', '${t.items.length}개 / $placeCount곳'),
                          const Divider(height: 10, color: Color(0xFFF1F5F9)),
                          _buildCompareRow('참여 인원', '$participantCount명'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 일차별 동선 화살표 연결선 타임라인
                    const Row(
                      children: [
                        Icon(Icons.timeline, size: 14, color: AppTheme.primary),
                        SizedBox(width: 4),
                        Text(
                          '일차별 동선 스루라인',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildRouteTimelineList(t),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 하단 전환 버튼
                    if (!isCurrent)
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<TripProvider>().switchTrip(t.metadata.id);
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('이 계획 사용하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompareRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isHighlight ? AppTheme.primary : AppTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRouteTimelineList(Trip trip) {
    final Map<int, List<TripItem>> dayMap = {};
    for (final i in trip.items) {
      dayMap.putIfAbsent(i.day, () => []).add(i);
    }

    if (dayMap.isEmpty) {
      return const [
        Text(
          '(등록된 일정이 없습니다)',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ];
    }

    final sortedDays = dayMap.keys.toList()..sort();
    return sortedDays.map((d) {
      final items = dayMap[d]!;
      final dayColor = AppTheme.getDayColor(d);

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dayColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Day $d',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dayColor),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        items[i].title,
                        style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (i < items.length - 1)
                      const Icon(Icons.arrow_forward, size: 10, color: AppTheme.textSecondary),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
