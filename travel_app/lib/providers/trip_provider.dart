/// @intent 여행 계획 중앙 상태 관리자(TripProvider) - 다중 여행 CRUD, 슬롯 후보 관리, 계정별 격리 및 동행자 공유/협업(TripSharing) 지원
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/trip.dart';
import '../models/trip_item.dart';
import '../models/trip_metadata.dart';
import '../services/cloud_sync_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/trip_sharing_service.dart';

enum SyncStatus {
  synced,
  syncing,
  offline,
  localOnly,
}

class TripProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SupabaseService _supabaseService;
  final CloudSyncService _cloudSyncService;
  final TripSharingService _tripSharingService;
  final Uuid _uuid = const Uuid();

  List<Trip> _trips = [Trip.defaultTrip()];
  String _currentTripId = 'trip-my-first-trip';
  dynamic _selectedDay = 1; // 1..N 또는 'all'
  String? _selectedItemId;
  String _activeTab = 'timeline'; // 'timeline' | 'map' | 'expense'
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncMessage = '';

  String? _currentUserId;
  SyncStatus _syncStatus = SyncStatus.localOnly;

  TripProvider({
    StorageService? storageService,
    SupabaseService? supabaseService,
    CloudSyncService? cloudSyncService,
    TripSharingService? tripSharingService,
  })  : _storageService = storageService ?? StorageService(),
        _supabaseService = supabaseService ?? SupabaseService(),
        _cloudSyncService = cloudSyncService ?? CloudSyncService(),
        _tripSharingService = tripSharingService ?? TripSharingService() {
    init();
  }

  // Getters
  List<Trip> get trips => _trips;
  String get currentTripId => _currentTripId;
  dynamic get selectedDay => _selectedDay;
  String? get selectedItemId => _selectedItemId;
  String get activeTab => _activeTab;
  bool get isLoading => _isLoading;
  String? get currentUserId => _currentUserId;
  SyncStatus get syncStatus => _syncStatus;
  TripSharingService get tripSharingService => _tripSharingService;

  bool get isCurrentTripShared => currentTrip.metadata.isShared;
  String get currentTripRole => currentTrip.metadata.currentUserRole(_currentUserId);
  bool get canEditCurrentTrip => currentTrip.metadata.canUserEdit(_currentUserId);
  bool get isCloudSyncEnabled =>
      _currentUserId != null &&
      _currentUserId!.isNotEmpty &&
      _currentUserId != 'guest' &&
      _currentUserId != 'guest-local-user' &&
      _cloudSyncService.isCloudAvailable;

  Trip get currentTrip {
    return _trips.firstWhere(
      (t) => t.metadata.id == _currentTripId,
      orElse: () => _trips.isNotEmpty ? _trips.first : Trip.defaultTrip(),
    );
  }

  int get maxDay {
    int maxD = 1;
    for (final item in currentTrip.items) {
      if (item.day > maxD) {
        maxD = item.day;
      }
    }
    return maxD;
  }

  List<TripItem> get itemsForSelectedDay {
    if (_selectedDay == 'all') {
      return List<TripItem>.from(currentTrip.items);
    }
    final targetDay = _selectedDay is int ? _selectedDay as int : int.tryParse(_selectedDay.toString()) ?? 1;
    return currentTrip.items.where((item) => item.day == targetDay).toList();
  }

  /// 현재 선택된 일차(또는 전체)에서 확정/활성(isSelected == true) 상태인 대표 아이템 목록 반환
  List<TripItem> get activeItemsForSelectedDay {
    return itemsForSelectedDay.where((item) => item.isSelected).toList();
  }

  /// 특정 일차(또는 전체)의 아이템들을 effectiveSlotId 기준으로 슬롯 그룹핑하여 맵으로 반환
  Map<String, List<TripItem>> getSlotGroupsForDay(dynamic day) {
    final List<TripItem> items = (day == 'all')
        ? currentTrip.items
        : currentTrip.items.where((i) => i.day == (day is int ? day : int.tryParse(day.toString()) ?? 1)).toList();

    final Map<String, List<TripItem>> slotGroups = {};
    for (final item in items) {
      slotGroups.putIfAbsent(item.effectiveSlotId, () => []).add(item);
    }
    return slotGroups;
  }

  bool get isSyncing => _isSyncing;
  String get syncMessage => _syncMessage;
  SupabaseService get supabaseService => _supabaseService;
  CloudSyncService get cloudSyncService => _cloudSyncService;

  // 초기화 및 로드
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    // 1. 현재 사용자(또는 게스트) 로컬 저장소 우선 로드
    final result = await _storageService.loadTrips(userId: _currentUserId);
    _trips = result.trips;
    _currentTripId = result.currentTripId;
    _selectedDay = 1;
    _selectedItemId = null;
    _isLoading = false;
    notifyListeners();

    // 2. Supabase 클라우드 실시간 데이터 자동 조회 및 복원
    await syncFromCloud();
  }

  /// 계정 로그인/전환 시 사용자 바인딩 (이전 사용자 데이터 메모리 완전 정화 및 격리 로드)
  Future<void> bindUser(String? userId) async {
    if (_currentUserId == userId && !_isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    // 이전 사용자 데이터 메모리에서 완전 정화(Clear)
    _trips = [];
    _currentTripId = '';
    _selectedItemId = null;
    _selectedDay = 1;
    _currentUserId = userId;

    // 해당 사용자(또는 게스트)의 로컬 캐시 로드
    final result = await _storageService.loadTrips(userId: _currentUserId);
    _trips = result.trips;
    _currentTripId = result.currentTripId;
    _isLoading = false;
    notifyListeners();

    // 클라우드 동기화 수행
    await syncFromCloud();
  }

  /// 로그아웃 시 메모리 및 상태 즉시 초기화하고 게스트 전용 데이터로 전환 (다른 사용자 데이터 잔류 방지)
  Future<void> unbindUser() async {
    await bindUser(null);
  }

  /// 게스트 모드에서 작성한 유의미한 일정이 있는지 검사 (마이그레이션 안내 팝업용)
  Future<bool> hasGuestTripsToMigrate() async {
    try {
      final guestTrips = await _storageService.getGuestTrips();
      const defaultTitles = {'나의 여행 계획', '새로운 여행 계획', '도쿄 감성 힐링 여행', '도쿄 3박 4일 감성 힐링 여행'};
      return guestTrips.any((t) =>
          t.items.isNotEmpty ||
          (!defaultTitles.contains(t.metadata.title) && t.metadata.title.trim().isNotEmpty));
    } catch (_) {
      return false;
    }
  }

  /// 게스트 모드 작성 일정을 현재 로그인 사용자 계정으로 마이그레이션
  Future<int> migrateGuestTripsToUser() async {
    if (_currentUserId == null ||
        _currentUserId!.isEmpty ||
        _currentUserId == 'guest' ||
        _currentUserId == 'guest-local-user') {
      return 0;
    }

    try {
      final guestTrips = await _storageService.getGuestTrips();
      if (guestTrips.isEmpty) return 0;

      // 유의미한 게스트 여행 선별 (아이템이 있거나 커스텀 타이틀)
      const defaultTitles = {'나의 여행 계획', '새로운 여행 계획', '도쿄 감성 힐링 여행', '도쿄 3박 4일 감성 힐링 여행'};
      final validGuestTrips = guestTrips
          .where((t) => t.items.isNotEmpty || (!defaultTitles.contains(t.metadata.title) && t.metadata.title.trim().isNotEmpty))
          .toList();

      if (validGuestTrips.isEmpty) return 0;

      // 현재 사용자의 목록에 병합 (기존 기본 템플릿만 있으면 교체)
      if (_trips.length == 1 &&
          _trips.first.metadata.id == 'trip-my-first-trip' &&
          _trips.first.items.isEmpty) {
        _trips = List<Trip>.from(validGuestTrips);
        _currentTripId = _trips.first.metadata.id;
      } else {
        for (final gt in validGuestTrips) {
          if (!_trips.any((t) => t.metadata.id == gt.metadata.id)) {
            _trips.add(gt);
          }
        }
      }

      // 로컬 및 클라우드 영구 저장
      await _storageService.saveTrips(_trips, _currentTripId, userId: _currentUserId);
      await _cloudSyncService.migrateLocalTripsToCloud(validGuestTrips, _currentUserId!);
      await _storageService.clearGuestTrips();

      notifyListeners();
      return validGuestTrips.length;
    } catch (e) {
      debugPrint('[TripProvider] migrateGuestTripsToUser 실패: $e');
      return 0;
    }
  }

  /// Supabase 클라우드에서 여행 계획 목록 조회 및 병합 동기화
  Future<void> syncFromCloud() async {
    _isSyncing = true;
    _syncStatus = SyncStatus.syncing;
    _syncMessage = '클라우드 데이터 확인 중...';
    notifyListeners();

    try {
      List<Trip> cloudTrips = [];

      if (isCloudSyncEnabled) {
        cloudTrips = await _cloudSyncService.fetchUserTrips(_currentUserId!);
      } else {
        // 게스트 모드이거나 SupabaseService 주입(테스트 등) 환경: 기본 fetchTrips 시도
        cloudTrips = await _supabaseService.fetchTrips();
      }

      if (cloudTrips.isNotEmpty) {
        // 충돌 해결 및 병합
        _trips = _cloudSyncService.resolveConflicts(_trips, cloudTrips);

        // 현재 활성 여행 유효성 검사
        if (!_trips.any((t) => t.metadata.id == _currentTripId)) {
          _currentTripId = _trips.first.metadata.id;
        }

        await _storageService.saveTrips(_trips, _currentTripId, userId: _currentUserId);
        _syncStatus = SyncStatus.synced;
        _syncMessage = '클라우드 동기화 완료';
      } else {
        // 클라우드가 비어있고 로그인 상태에서 로컬에 여행이 있으면 클라우드로 업로드
        if (isCloudSyncEnabled && _trips.isNotEmpty && _trips.any((t) => t.items.isNotEmpty)) {
          for (final t in _trips) {
            await _cloudSyncService.syncTripToCloud(t, _currentUserId!);
          }
          _syncStatus = SyncStatus.synced;
          _syncMessage = '클라우드 연동 완료';
        } else {
          _syncStatus = isCloudSyncEnabled ? SyncStatus.synced : SyncStatus.localOnly;
          _syncMessage = isCloudSyncEnabled ? '클라우드 연동 완료' : '로컬 오프라인 모드';
        }
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline;
      _syncMessage = '오프라인 모드';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storageService.saveTrips(_trips, _currentTripId, userId: _currentUserId);
    // Supabase 클라우드 백그라운드 자동 동기화
    final cur = currentTrip;
    if (cur.metadata.id.isNotEmpty) {
      if (isCloudSyncEnabled) {
        _cloudSyncService.syncTripToCloud(cur, _currentUserId!);
      } else {
        _supabaseService.syncTrip(cur);
      }
    }
  }

  // 탭 및 필터 변경
  void setSelectedDay(dynamic day) {
    if (day == 'all') {
      _selectedDay = 'all';
    } else {
      _selectedDay = day is int ? day : int.tryParse(day.toString()) ?? 1;
    }
    notifyListeners();
  }

  void setSelectedItemId(String? id) {
    _selectedItemId = id;
    notifyListeners();
  }

  void setActiveTab(String tab) {
    _activeTab = tab;
    notifyListeners();
  }

  // 여행 CRUD
  Trip? switchTrip(String tripId) {
    final target = _trips.cast<Trip?>().firstWhere(
      (t) => t?.metadata.id == tripId,
      orElse: () => null,
    );
    if (target == null) return null;

    _currentTripId = target.metadata.id;
    _selectedDay = 1;
    _selectedItemId = null;
    _persist();
    notifyListeners();
    return target;
  }

  Trip createTrip({TripMetadata? metadata, List<TripItem>? initialItems}) {
    final newId = metadata?.id.isNotEmpty == true
        ? metadata!.id
        : 'trip-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 4)}';

    final newMeta = (metadata ?? const TripMetadata(id: '', title: '새로운 여행 계획')).copyWith(id: newId);
    final newTrip = Trip(
      metadata: newMeta,
      items: initialItems != null ? List<TripItem>.from(initialItems) : [],
    );

    _trips.add(newTrip);
    _currentTripId = newId;
    _selectedDay = 1;
    _selectedItemId = null;
    _persist();
    notifyListeners();
    return newTrip;
  }

  Trip? duplicateTrip(String tripId) {
    final source = _trips.cast<Trip?>().firstWhere(
      (t) => t?.metadata.id == tripId,
      orElse: () => null,
    );
    if (source == null) return null;

    final newTripId = 'trip-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 4)}';
    final copiedMeta = source.metadata.copyWith(
      id: newTripId,
      title: '${source.metadata.title} (사본)',
    );

    final copiedItems = source.items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      return item.copyWith(
        id: 'item-${DateTime.now().millisecondsSinceEpoch}-$idx-${_uuid.v4().substring(0, 4)}',
      );
    }).toList();

    final duplicated = Trip(metadata: copiedMeta, items: copiedItems);
    _trips.add(duplicated);
    _currentTripId = newTripId;
    _selectedDay = 1;
    _selectedItemId = null;
    _persist();
    notifyListeners();
    return duplicated;
  }

  bool deleteTrip(String tripId) {
    if (_trips.length <= 1) return false;

    final idx = _trips.indexWhere((t) => t.metadata.id == tripId);
    if (idx == -1) return false;

    _trips.removeAt(idx);

    if (_currentTripId == tripId) {
      _currentTripId = _trips.first.metadata.id;
      _selectedDay = 1;
      _selectedItemId = null;
    }

    _persist();
    if (isCloudSyncEnabled) {
      _cloudSyncService.deleteTripFromCloud(tripId, _currentUserId!);
    } else {
      _supabaseService.deleteTrip(tripId);
    }
    notifyListeners();
    return true;
  }

  void clearCurrentTripItems() {
    final idx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (idx != -1) {
      _trips[idx] = _trips[idx].copyWith(items: []);
      _selectedItemId = null;
      _persist();
      notifyListeners();
    }
  }

  void updateMetadata(TripMetadata patch) {
    final idx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (idx != -1) {
      _trips[idx] = _trips[idx].copyWith(metadata: patch);
      _persist();
      notifyListeners();
    }
  }

  // 일정 아이템 CRUD
  TripItem addItem(TripItem item) {
    final assignedDay = item.day > 0
        ? item.day
        : ((_selectedDay == 'all')
            ? 1
            : (_selectedDay is int ? _selectedDay as int : 1));

    final finalItem = item.copyWith(
      id: item.id.isNotEmpty
          ? item.id
          : 'item-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 4)}',
      day: assignedDay,
    );

    final idx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (idx != -1) {
      final updatedItems = List<TripItem>.from(_trips[idx].items);
      // assignedDay 이하의 마지막 아이템 뒤에 삽입 (해당 일차의 맨 밑에 추가)
      int insertIdx = -1;
      for (int i = updatedItems.length - 1; i >= 0; i--) {
        if (updatedItems[i].day <= assignedDay) {
          insertIdx = i + 1;
          break;
        }
      }
      if (insertIdx == -1) {
        insertIdx = 0;
      }
      updatedItems.insert(insertIdx, finalItem);
      _trips[idx] = _trips[idx].copyWith(items: updatedItems);
      _persist();
      notifyListeners();
    }
    return finalItem;
  }

  /// 일정 목록 순서 이동 (Drag & Drop Reordering)
  void reorderItems(int oldIndex, int newIndex) {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return;
    if (oldIndex == newIndex) return;

    final currentItems = List<TripItem>.from(_trips[tripIdx].items);

    if (_selectedDay == 'all') {
      if (oldIndex < 0 || oldIndex >= currentItems.length) return;
      final item = currentItems.removeAt(oldIndex);
      final insertIdx = newIndex.clamp(0, currentItems.length);
      currentItems.insert(insertIdx, item);
    } else {
      final targetDay = _selectedDay is int
          ? _selectedDay as int
          : int.tryParse(_selectedDay.toString()) ?? 1;

      // targetDay에 속한 아이템들의 전체 리스트 내 실제 인덱스 매핑
      final dayItemIndices = <int>[];
      for (int i = 0; i < currentItems.length; i++) {
        if (currentItems[i].day == targetDay) {
          dayItemIndices.add(i);
        }
      }

      if (oldIndex < 0 || oldIndex >= dayItemIndices.length) return;

      final realOldIndex = dayItemIndices[oldIndex];
      final item = currentItems.removeAt(realOldIndex);

      // item 제거 후 인덱스 재계산
      final updatedDayItemIndices = <int>[];
      for (int i = 0; i < currentItems.length; i++) {
        if (currentItems[i].day == targetDay) {
          updatedDayItemIndices.add(i);
        }
      }

      final realNewIndex = (newIndex < updatedDayItemIndices.length)
          ? updatedDayItemIndices[newIndex]
          : (updatedDayItemIndices.isNotEmpty ? updatedDayItemIndices.last + 1 : currentItems.length);

      final clampedRealNewIndex = realNewIndex.clamp(0, currentItems.length);
      currentItems.insert(clampedRealNewIndex, item);
    }

    _trips[tripIdx] = _trips[tripIdx].copyWith(items: currentItems);
    _persist();
    notifyListeners();
  }

  TripItem? updateItem(String id, TripItem updated) {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return null;

    final itemIdx = _trips[tripIdx].items.indexWhere((i) => i.id == id);
    if (itemIdx == -1) return null;

    final existing = _trips[tripIdx].items[itemIdx];

    // 동일 일차 내 수정 시 슬롯 메타데이터(slotGroupId, candidateLabel, isSelected) 완벽 보존
    TripItem finalItem = updated;
    if (existing.slotGroupId.isNotEmpty && updated.day == existing.day) {
      finalItem = updated.copyWith(
        slotGroupId: updated.slotGroupId.isNotEmpty ? updated.slotGroupId : existing.slotGroupId,
        candidateLabel: updated.slotGroupId.isNotEmpty ? updated.candidateLabel : existing.candidateLabel,
        isSelected: (existing.slotGroupId.isNotEmpty && updated.slotGroupId.isEmpty) ? existing.isSelected : updated.isSelected,
      );
    } else if (existing.slotGroupId.isNotEmpty && updated.day != existing.day) {
      // 다른 일차로 이동한 경우 단독 슬롯으로 리셋
      finalItem = updated.copyWith(
        slotGroupId: '',
        candidateLabel: '1',
        isSelected: true,
      );
    }

    var updatedItems = List<TripItem>.from(_trips[tripIdx].items);
    updatedItems[itemIdx] = finalItem;

    // 만약 다른 일차로 이동했고 기존에 선택되어 있던 아이템이었다면, 기존 슬롯에 남은 후보 자동 승격 처리
    if (existing.slotGroupId.isNotEmpty && updated.day != existing.day && existing.isSelected) {
      final remainingSlotItems = updatedItems
          .where((i) => i.id != id && i.effectiveSlotId == existing.effectiveSlotId)
          .toList();
      if (remainingSlotItems.isNotEmpty && !remainingSlotItems.any((i) => i.isSelected)) {
        final firstRemainingId = remainingSlotItems.first.id;
        updatedItems = updatedItems.map((item) {
          if (item.id == firstRemainingId) {
            return item.copyWith(isSelected: true);
          }
          return item;
        }).toList();
      }
    }

    _trips[tripIdx] = _trips[tripIdx].copyWith(items: updatedItems);
    _persist();
    notifyListeners();
    return finalItem;
  }

  bool deleteItem(String id) {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return false;

    final originalLen = _trips[tripIdx].items.length;
    final targetItem = _trips[tripIdx].items.cast<TripItem?>().firstWhere(
      (i) => i?.id == id,
      orElse: () => null,
    );
    if (targetItem == null) return false;

    var updatedItems = _trips[tripIdx].items.where((i) => i.id != id).toList();

    // 활성(isSelected == true) 아이템이 삭제되었고, 동일 슬롯에 다른 후보가 남아있다면 첫 번째 후보를 자동 승격
    if (targetItem.isSelected) {
      final remainingSlotItems = updatedItems.where((i) => i.effectiveSlotId == targetItem.effectiveSlotId).toList();
      if (remainingSlotItems.isNotEmpty && !remainingSlotItems.any((i) => i.isSelected)) {
        final firstRemainingId = remainingSlotItems.first.id;
        updatedItems = updatedItems.map((item) {
          if (item.id == firstRemainingId) {
            return item.copyWith(isSelected: true);
          }
          return item;
        }).toList();
      }
    }

    if (_selectedItemId == id) {
      _selectedItemId = null;
    }

    _trips[tripIdx] = _trips[tripIdx].copyWith(items: updatedItems);
    _persist();
    notifyListeners();

    // 클라우드 Storage 사진 파일 비동기 정리
    if (targetItem.photos.isNotEmpty) {
      for (final photo in targetItem.photos) {
        if (photo.contains('trip-photos')) {
          _supabaseService.deletePhoto(photo);
        }
      }
    }

    return originalLen != updatedItems.length;
  }

  /// 동일 슬롯(effectiveSlotId) 내에서 targetItemId를 활성(isSelected = true) 후보로 선택하고 나머지를 false로 변경
  void selectCandidate(String targetItemId) {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return;

    final currentItems = _trips[tripIdx].items;
    final targetItem = currentItems.cast<TripItem?>().firstWhere(
          (i) => i?.id == targetItemId,
          orElse: () => null,
        );
    if (targetItem == null) return;

    final targetSlotId = targetItem.effectiveSlotId;
    final updatedItems = currentItems.map((item) {
      if (item.effectiveSlotId == targetSlotId) {
        return item.copyWith(isSelected: item.id == targetItemId);
      }
      return item;
    }).toList();

    _trips[tripIdx] = _trips[tripIdx].copyWith(items: updatedItems);
    _persist();
    notifyListeners();
  }

  /// 기존 baseItem의 슬롯에 새로운 후보(대안 플랜) 아이템 추가
  TripItem? addCandidateItem({required TripItem baseItem, required TripItem candidateItem}) {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return null;

    final currentItems = List<TripItem>.from(_trips[tripIdx].items);
    final baseIndex = currentItems.indexWhere((i) => i.id == baseItem.id);
    if (baseIndex == -1) return null;

    // 1. baseItem의 slotGroupId 확보 (기존에 비어있으면 생성 후 baseItem 갱신)
    String assignedSlotId = baseItem.slotGroupId;
    if (assignedSlotId.isEmpty) {
      assignedSlotId = 'slot-${baseItem.day}-${DateTime.now().millisecondsSinceEpoch}';
      final updatedBase = baseItem.copyWith(
        slotGroupId: assignedSlotId,
        candidateLabel: baseItem.candidateLabel.isNotEmpty ? baseItem.candidateLabel : '1',
        isSelected: true,
      );
      currentItems[baseIndex] = updatedBase;
    }

    // 2. 현재 슬롯에 속한 후보 개수 확인하여 다음 라벨 지정
    final existingCandidates = currentItems.where((i) => i.effectiveSlotId == assignedSlotId).toList();
    final nextSeq = existingCandidates.length + 1;
    final nextLabel = candidateItem.candidateLabel.isNotEmpty && candidateItem.candidateLabel != '1'
        ? candidateItem.candidateLabel
        : '$nextSeq';

    // 3. 신규 후보 아이템 생성 (기본값: isSelected = false)
    final newCandidateId = candidateItem.id.isNotEmpty
        ? candidateItem.id
        : 'item-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 4)}';

    final finalCandidate = candidateItem.copyWith(
      id: newCandidateId,
      day: baseItem.day,
      slotGroupId: assignedSlotId,
      candidateLabel: nextLabel,
      isSelected: false,
    );

    // baseItem의 슬롯 그룹 마지막 아이템 바로 뒤에 삽입
    int insertIdx = baseIndex + 1;
    for (int i = currentItems.length - 1; i >= 0; i--) {
      if (currentItems[i].effectiveSlotId == assignedSlotId) {
        insertIdx = i + 1;
        break;
      }
    }
    if (insertIdx > currentItems.length) {
      insertIdx = currentItems.length;
    }
    currentItems.insert(insertIdx, finalCandidate);

    _trips[tripIdx] = _trips[tripIdx].copyWith(items: currentItems);
    _persist();
    notifyListeners();

    return finalCandidate;
  }

  /// 현재 여행의 초대 코드 조회 또는 생성
  Future<String> getOrGenerateInviteCode(String tripId, {String? ownerName}) async {
    final idx = _trips.indexWhere((t) => t.metadata.id == tripId);
    if (idx == -1) return '';

    final trip = _trips[idx];
    final code = await _tripSharingService.generateInviteCode(
      trip,
      ownerId: _currentUserId,
      ownerName: ownerName,
    );

    // 갱신된 메타데이터 로컬 반영
    if (_trips[idx].metadata.inviteCode != code) {
      _trips[idx] = _trips[idx].copyWith(
        metadata: _trips[idx].metadata.copyWith(
          inviteCode: code,
          ownerId: _trips[idx].metadata.ownerId.isNotEmpty
              ? _trips[idx].metadata.ownerId
              : (_currentUserId ?? ''),
          ownerName: _trips[idx].metadata.ownerName.isNotEmpty
              ? _trips[idx].metadata.ownerName
              : (ownerName ?? '호스트 여행자'),
        ),
      );
      await _persist();
      notifyListeners();
    }
    return code;
  }

  /// 초대 코드로 여행 조회 (미리보기용)
  Future<Trip?> previewTripByInviteCode(String inviteCode) async {
    return await _tripSharingService.getTripByInviteCode(inviteCode);
  }

  /// 초대 코드로 여행 참여 및 내 여행 목록에 추가/전환
  Future<bool> joinTripByInviteCode(
    String inviteCode, {
    String? userEmail,
    String? userDisplayName,
  }) async {
    final userId = _currentUserId ?? 'guest-local-user';
    final email = userEmail ?? 'traveler@mytriplog.com';
    final displayName = userDisplayName ?? '동행자';

    final joinedTrip = await _tripSharingService.joinTripWithInviteCode(
      inviteCode: inviteCode,
      userId: userId,
      email: email,
      displayName: displayName,
    );

    if (joinedTrip == null) return false;

    // 내 여행 목록에 추가 또는 갱신
    final existingIdx = _trips.indexWhere((t) => t.metadata.id == joinedTrip.metadata.id);
    if (existingIdx != -1) {
      _trips[existingIdx] = joinedTrip;
    } else {
      _trips.add(joinedTrip);
    }

    _currentTripId = joinedTrip.metadata.id;
    _selectedDay = 1;
    _selectedItemId = null;
    await _persist();
    notifyListeners();
    return true;
  }

  /// 참여자 권한 변경
  Future<bool> updateMemberRole(String targetUserId, String newRole) async {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return false;

    try {
      final updated = _tripSharingService.updateMemberRole(
        trip: _trips[tripIdx],
        targetUserId: targetUserId,
        newRole: newRole,
        requestUserId: _currentUserId ?? '',
      );
      _trips[tripIdx] = updated;
      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 참여자 추방 / 탈퇴
  Future<bool> removeMember(String targetUserId) async {
    final tripIdx = _trips.indexWhere((t) => t.metadata.id == _currentTripId);
    if (tripIdx == -1) return false;

    try {
      final updated = _tripSharingService.removeMember(
        trip: _trips[tripIdx],
        targetUserId: targetUserId,
        requestUserId: _currentUserId ?? '',
      );

      // 만약 내가 탈퇴한 경우 내 목록에서 여행 삭제
      if (targetUserId == _currentUserId) {
        return deleteTrip(_currentTripId);
      }

      _trips[tripIdx] = updated;
      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
