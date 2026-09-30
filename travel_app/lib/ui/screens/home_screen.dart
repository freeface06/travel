/*
 * @intent 메인 홈 화면 - 지도 1층, Day 칩 플로팅 2층, DraggableScrollableSheet 타임라인 3층의 인터랙티브 반응형 구조 및 계정 프로필 연동
 * @agent  Gemini/manager-develop
 * @branch feat/v2.0.0-commercial
 * @author @developer_name
 * @date   2026-09-30
 */
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trip_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../dialogs/item_edit_dialog.dart';
import '../dialogs/trip_manager_dialog.dart';
import '../dialogs/trip_settings_dialog.dart';
import '../dialogs/trip_share_dialog.dart';
import '../tabs/expense_tab.dart';
import 'dart:async';
import '../tabs/map_tab.dart';
import '../tabs/timeline_tab.dart';
import '../theme/app_theme.dart';
import '../widgets/app_menu_divider.dart';
import '../widgets/app_toast.dart';
import '../../services/quick_import_service.dart';
import '../sheets/quick_place_import_sheet.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  String _mapStyle = 'google_roadmap'; // 'google_roadmap' (일반) | 'google_satellite' (위성)
  bool _checkedGuestMigration = false;
  StreamSubscription<String>? _placeUrlSub;
  bool _isImportSheetShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheetController.addListener(_onSheetScroll);

    // 구글맵 공유 인텐트 및 클립보드 장소 감지 초기화 및 리스너 등록
    QuickImportService.instance.initialize();
    _placeUrlSub = QuickImportService.instance.onPlaceUrlDetected.listen(_handleDetectedPlaceUrl);

    // 첫 프레임 렌더링 완료 후 클립보드 자동 검사 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        QuickImportService.instance.checkClipboard();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      QuickImportService.instance.checkClipboard();
    }
  }

  /// 구글맵 URL이 공유 인텐트나 클립보드에서 감지되었을 때 바텀시트 팝업
  Future<void> _handleDetectedPlaceUrl(String url) async {
    if (!mounted || _isImportSheetShowing) return;

    // 현재 화면 컨텍스트 안전성 검사
    final nav = Navigator.maybeOf(context);
    if (nav == null) return;

    _isImportSheetShowing = true;
    try {
      final tripProvider = context.read<TripProvider>();
      final currentDay = tripProvider.selectedDay is int ? tripProvider.selectedDay as int : 1;
      await QuickPlaceImportSheet.show(
        context,
        rawInput: url,
        targetDay: currentDay,
      );
    } finally {
      if (mounted) {
        _isImportSheetShowing = false;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkGuestMigrationPrompt();
  }

  Future<void> _checkGuestMigrationPrompt() async {
    if (_checkedGuestMigration) return;
    final auth = context.read<AuthProvider>();
    final tripProvider = context.read<TripProvider>();

    if (auth.isAuthenticated && !auth.isGuestMode) {
      _checkedGuestMigration = true;
      final hasGuestTrips = await tripProvider.hasGuestTripsToMigrate();
      if (hasGuestTrips && mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('게스트 일정 동기화', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: const Text('게스트 모드에서 작성한 여행 일정이 있습니다.\n현재 계정으로 가져와 클라우드에 보관하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('나중에', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('내 계정으로 가져오기'),
              ),
            ],
          ),
        );

        if (confirm == true && mounted) {
          final count = await tripProvider.migrateGuestTripsToUser();
          if (mounted && count > 0) {
            AppToast.success(context, '$count개의 여행 일정을 내 계정으로 가져왔습니다.');
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _placeUrlSub?.cancel();
    _sheetController.removeListener(_onSheetScroll);
    _sheetController.dispose();
    super.dispose();
  }

  void _onSheetScroll() {
    if (!_sheetController.isAttached) return;
    final provider = context.read<TripProvider>();
    if (provider.activeTab == 'expense') return;

    final currentSize = _sheetController.size;
    if (currentSize <= 0.25 && provider.activeTab != 'map') {
      provider.setActiveTab('map');
    } else if (currentSize > 0.25 && provider.activeTab != 'timeline') {
      provider.setActiveTab('timeline');
    }
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details, double screenHeight) {
    if (!_sheetController.isAttached || screenHeight <= 0) return;
    final delta = details.primaryDelta ?? 0.0;
    final deltaRatio = delta / screenHeight;
    final newSize = (_sheetController.size - deltaRatio).clamp(0.14, 0.93);
    _sheetController.jumpTo(newSize);
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    final currentSize = _sheetController.size;
    final velocity = details.primaryVelocity ?? 0.0;

    double targetSize = 0.48;

    if (velocity < -300) {
      // 위로 스와이프: 현재 크기보다 한 단계 위로 확장
      if (currentSize < 0.40) {
        targetSize = 0.48;
      } else {
        targetSize = 0.93;
      }
    } else if (velocity > 300) {
      // 아래로 스와이프: 현재 크기보다 한 단계 아래로 축소
      if (currentSize > 0.55) {
        targetSize = 0.48;
      } else {
        targetSize = 0.14;
      }
    } else {
      // 드래그 종료 시 가장 가까운 스냅 지점으로 안착
      const snapPoints = [0.14, 0.48, 0.93];
      targetSize = snapPoints.reduce((a, b) =>
          (a - currentSize).abs() < (b - currentSize).abs() ? a : b);
    }

    _sheetController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _onMarkerTap(TripItem item) {
    final provider = context.read<TripProvider>();
    provider.setSelectedItemId(item.id);
    if (provider.selectedDay != 'all' && provider.selectedDay != item.day) {
      provider.setSelectedDay(item.day);
    }
    if (provider.activeTab == 'expense') {
      provider.setActiveTab('timeline');
    }
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.60,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onTimelineItemTap(TripItem item) {
    if (item.hasCoordinates && _sheetController.isAttached) {
      _sheetController.animateTo(
        0.14,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _calculateDDay(String startDateStr) {
    if (startDateStr.isEmpty) return '';
    try {
      final start = DateTime.parse(startDateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(start.year, start.month, start.day);
      final diff = target.difference(today).inDays;

      if (diff == 0) return 'D-Day';
      if (diff > 0) return 'D-$diff';
      return 'D+${-diff}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final trip = provider.currentTrip;
    final meta = trip.metadata;
    final dDay = _calculateDDay(meta.startDate);
    final activeTab = provider.activeTab;

    String durationText = '';
    if (meta.startDate.isNotEmpty && meta.endDate.isNotEmpty) {
      try {
        final s = DateTime.parse(meta.startDate);
        final e = DateTime.parse(meta.endDate);
        final diff = e.difference(s).inDays;
        if (diff > 0) {
          durationText = '${meta.startDate} ~ ${meta.endDate} ($diff박 ${diff + 1}일)';
        } else if (diff == 0) {
          durationText = '${meta.startDate} (당일치기)';
        } else {
          durationText = '${meta.startDate} ~ ${meta.endDate}';
        }
      } catch (_) {
        durationText = '${meta.startDate} ~ ${meta.endDate}';
      }
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => const TripManagerDialog(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                // 브랜드 비행기 로고 뱃지
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.flight_takeoff, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              meta.title.isEmpty ? 'MyTripLog' : meta.title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 18, color: AppTheme.textSecondary),
                          if (dDay.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dDay,
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (durationText.isNotEmpty)
                        Text(
                          durationText,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: provider.isSyncing
                  ? null
                  : () async {
                      await provider.syncFromCloud();
                      if (context.mounted) {
                        AppToast.info(context, provider.syncMessage);
                      }
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _getSyncBadgeBgColor(provider.syncStatus),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _getSyncBadgeBorderColor(provider.syncStatus),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.isSyncing)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AppTheme.primary,
                        ),
                      )
                    else
                      Icon(
                        _getSyncBadgeIcon(provider.syncStatus),
                        size: 13,
                        color: _getSyncBadgeTextColor(provider.syncStatus),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _getSyncBadgeLabel(provider.syncStatus),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getSyncBadgeTextColor(provider.syncStatus),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return PopupMenuButton<String>(
                tooltip: '계정 및 더보기 메뉴',
                elevation: 6,
                shadowColor: const Color(0x1E0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                offset: const Offset(0, 44),
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  if (value == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => const TripSettingsDialog(),
                    );
                  } else if (value == 'share') {
                    showDialog(
                      context: context,
                      builder: (_) => const TripShareDialog(),
                    );
                  } else if (value == 'manage') {
                    showDialog(
                      context: context,
                      builder: (_) => const TripManagerDialog(),
                    );
                  } else if (value == 'login') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  } else if (value == 'logout') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text(
                          '로그아웃',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        content: const Text('현재 계정에서 로그아웃하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text(
                              '취소',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('로그아웃'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      await authProvider.signOut();
                      if (context.mounted) {
                        AppToast.info(context, '로그아웃되었습니다.');
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  // 상단 계정 정보 헤더
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 52,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: authProvider.isGuestMode
                              ? const Color(0xFF64748B)
                              : AppTheme.primary,
                          child: Icon(
                            authProvider.isGuestMode
                                ? Icons.person_outline
                                : Icons.flight_takeoff,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                authProvider.displayName ?? '여행자',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                authProvider.isGuestMode
                                    ? '오프라인 게스트 모드'
                                    : (authProvider.email ?? ''),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: authProvider.isGuestMode
                                      ? const Color(0xFFD97706)
                                      : AppTheme.textSecondary,
                                  fontWeight: authProvider.isGuestMode
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AppMenuDivider(),
                  PopupMenuItem(
                    value: 'edit',
                    height: 44,
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
                            Icons.tune_rounded,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '여행 정보 수정',
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
                    value: 'share',
                    height: 44,
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
                            Icons.share_rounded,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '여행 공유 및 동행자 관리',
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
                    value: 'manage',
                    height: 44,
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
                            Icons.folder_copy_outlined,
                            size: 16,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '여행 계획 목록 및 비교',
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
                  if (authProvider.isGuestMode)
                    PopupMenuItem(
                      value: 'login',
                      height: 44,
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
                              Icons.login_rounded,
                              size: 16,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '계정 로그인 / 회원가입',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    PopupMenuItem(
                      value: 'logout',
                      height: 44,
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '로그아웃',
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
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: activeTab == 'expense' ? 1 : 0,
        children: [
          Stack(
              children: [
                // 1층 (배경): 전체 화면 지도 렌더링
                Positioned.fill(
                  child: MapTab(
                    onMarkerTap: _onMarkerTap,
                    mapStyle: _mapStyle,
                    onMapStyleChanged: (style) {
                      setState(() => _mapStyle = style);
                    },
                    showInternalStyleSwitcher: false,
                  ),
                ),

                // 2층 (상단 플로팅): 통합 단일 행 (Day 칩 바 80% + 일반/위성 스위처 20%)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: _buildTopControlBar(context, provider),
                ),

                // 3층 (전경): DraggableScrollableSheet 타임라인 바텀시트
                DraggableScrollableSheet(
                  controller: _sheetController,
                  minChildSize: 0.14,
                  initialChildSize: 0.48,
                  maxChildSize: 0.93,
                  snap: true,
                  snapSizes: const [0.14, 0.48, 0.93],
                  builder: (context, scrollController) {
                    final selectedDay = provider.selectedDay;
                    final dayItems = provider.itemsForSelectedDay;
                    final dayText = selectedDay == 'all' ? '전체 일정' : 'Day $selectedDay';
                    final countText = '${dayItems.length}개 일정';

                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 드래그 핸들 및 상단 헤더 (GestureDetector로 손잡이 드래그/스냅/탭 완벽 컨트롤)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) =>
                                _handleHeaderDragUpdate(details, MediaQuery.of(context).size.height),
                            onVerticalDragEnd: _handleHeaderDragEnd,
                            onTap: () {
                              if (_sheetController.isAttached) {
                                final currentSize = _sheetController.size;
                                final target = currentSize < 0.3
                                    ? 0.48
                                    : (currentSize < 0.7 ? 0.93 : 0.14);
                                _sheetController.animateTo(
                                  target,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 손잡이 터치 영역 (상하 넉넉한 10px 패딩)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 48,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCBD5E1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                                // 상단 헤더: 현재 일차 요약 배지 및 당겨올리기 힌트
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selectedDay == 'all'
                                              ? AppTheme.primary.withValues(alpha: 0.12)
                                              : AppTheme.getDayColor(selectedDay as int).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 13,
                                              color: selectedDay == 'all'
                                                  ? AppTheme.primary
                                                  : AppTheme.getDayColor(selectedDay as int),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              dayText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: selectedDay == 'all'
                                                    ? AppTheme.primary
                                                    : AppTheme.getDayColor(selectedDay as int),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        countText,
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
                            ),
                          ),
                          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

                          // 본문: TimelineTab
                          Expanded(
                            child: TimelineTab(
                              scrollController: scrollController,
                              onItemTap: _onTimelineItemTap,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          const ExpenseTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _getNavIndex(activeTab),
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          switch (index) {
            case 0: // 지도 탭: 바텀시트를 아래로 접어 지도를 전면에 확장
              if (provider.activeTab == 'expense') {
                provider.setActiveTab('map');
              }
              if (_sheetController.isAttached) {
                _sheetController.animateTo(
                  0.14,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
              break;
            case 1: // 일정 탭: 바텀시트를 올려 타임라인 일정을 표시
              if (provider.activeTab == 'expense') {
                provider.setActiveTab('timeline');
              }
              if (_sheetController.isAttached) {
                _sheetController.animateTo(
                  0.60,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
              break;
            case 2: // 추가 탭
              if (!provider.canEditCurrentTrip) {
                AppToast.warning(context, '이 여행은 뷰어(읽기 전용) 권한으로 참여 중이므로 일정을 추가할 수 없습니다.');
                break;
              }
              ItemEditDialog.show(context);
              break;
            case 3: // 경비 탭
              provider.setActiveTab('expense');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: '지도',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: '일정',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline, size: 24),
            activeIcon: Icon(Icons.add_circle, size: 24),
            label: '추가',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart_outline),
            activeIcon: Icon(Icons.pie_chart),
            label: '경비',
          ),
        ],
      ),
    );
  }

  int _getNavIndex(String tab) {
    switch (tab) {
      case 'map':
        return 0;
      case 'timeline':
        return 1;
      case 'expense':
        return 3;
      default:
        return 1;
    }
  }

  Color _getSyncBadgeBgColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Color(0xFFEFF6FF);
      case SyncStatus.syncing:
        return const Color(0xFFF0FDF4);
      case SyncStatus.offline:
        return const Color(0xFFFEF2F2);
      case SyncStatus.localOnly:
        return const Color(0xFFF8FAFC);
    }
  }

  Color _getSyncBadgeBorderColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Color(0xFFBFDBFE);
      case SyncStatus.syncing:
        return const Color(0xFFBBF7D0);
      case SyncStatus.offline:
        return const Color(0xFFFECACA);
      case SyncStatus.localOnly:
        return const Color(0xFFE2E8F0);
    }
  }

  Color _getSyncBadgeTextColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return AppTheme.primaryDark;
      case SyncStatus.syncing:
        return const Color(0xFF15803D);
      case SyncStatus.offline:
        return const Color(0xFFDC2626);
      case SyncStatus.localOnly:
        return const Color(0xFF64748B);
    }
  }

  IconData _getSyncBadgeIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Icons.cloud_done_outlined;
      case SyncStatus.syncing:
        return Icons.cloud_sync_outlined;
      case SyncStatus.offline:
        return Icons.cloud_off_outlined;
      case SyncStatus.localOnly:
        return Icons.save_outlined;
    }
  }

  String _getSyncBadgeLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return '클라우드';
      case SyncStatus.syncing:
        return '동기화 중';
      case SyncStatus.offline:
        return '오프라인';
      case SyncStatus.localOnly:
        return '로컬 저장';
    }
  }

  /// 상단 지도 제어 통합 단일 행 (Day 칩 가로 80% + 일반/위성 스위처 20%)
  Widget _buildTopControlBar(BuildContext context, TripProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Day 1, 2 칩 탭 (가로 약 80% 차지, 가로 스크롤)
          Expanded(
            child: _buildDayChipsBar(context, provider),
          ),
          const SizedBox(width: 8),

          // 2. 일반 / 위성 토글 버튼 (나머지 공간에 고정 배치)
          _buildMapStyleSwitcher(),
        ],
      ),
    );
  }

  Widget _buildDayChipsBar(BuildContext context, TripProvider provider) {
    final selectedDay = provider.selectedDay;
    final maxDay = provider.maxDay;
    final isAllSelected = selectedDay == 'all';

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // 전체(All) 칩
          _buildDayChipPill(
            label: '전체',
            isSelected: isAllSelected,
            activeColor: AppTheme.primary,
            indicatorDotColor: AppTheme.primary,
            onTap: () => provider.setSelectedDay('all'),
          ),

          // Day 1..N 칩
          ...List.generate(maxDay, (idx) {
            final day = idx + 1;
            final isSelected = !isAllSelected && selectedDay == day;
            final dayColor = AppTheme.getDayColor(day);

            return _buildDayChipPill(
              label: 'Day $day',
              isSelected: isSelected,
              activeColor: dayColor,
              indicatorDotColor: dayColor,
              onTap: () => provider.setSelectedDay(day),
            );
          }),
        ],
      ),
    );
  }

  /// Day 칩 바와 동일한 높이(38px)와 스타일로 결합되는 일반/위성 세그먼트 스위처
  Widget _buildMapStyleSwitcher() {
    final isRoadmap = _mapStyle == 'google_roadmap';
    final isSatellite = _mapStyle == 'google_satellite';

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 일반 지도 버튼
          InkWell(
            onTap: () {
              if (!isRoadmap) {
                setState(() => _mapStyle = 'google_roadmap');
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isRoadmap ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '일반',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isRoadmap ? FontWeight.bold : FontWeight.w600,
                  color: isRoadmap ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          ),

          // 위성 지도 버튼
          InkWell(
            onTap: () {
              if (!isSatellite) {
                setState(() => _mapStyle = 'google_satellite');
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isSatellite ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '위성',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSatellite ? FontWeight.bold : FontWeight.w600,
                  color: isSatellite ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 지도 디자인과 자연스럽게 어울리는 개별 플로팅 Day 칩 위젯
  Widget _buildDayChipPill({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required Color indicatorDotColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? activeColor : const Color(0xFFE2E8F0),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? activeColor.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.10),
            blurRadius: isSelected ? 6 : 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isSelected) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: indicatorDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    letterSpacing: -0.2,
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
