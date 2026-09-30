/// @intent 여행 계획 중앙 상태 관리자(TripProvider) - 다중 여행 CRUD 및 일정 후보/대안 플랜(Slot Grouping, selectCandidate) 지원
/// @agent Gemini/manager-develop
/// @branch feat/flutter-travel-app
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/trip.dart';
import '../models/trip_item.dart';
import '../models/trip_metadata.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class TripProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SupabaseService _supabaseService;
  final Uuid _uuid = const Uuid();

  List<Trip> _trips = [Trip.defaultTrip()];
  String _currentTripId = 'trip-my-first-trip';
  dynamic _selectedDay = 1; // 1..N 또는 'all'
  String? _selectedItemId;
  String _activeTab = 'timeline'; // 'timeline' | 'map' | 'expense'
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncMessage = '';

  TripProvider({StorageService? storageService, SupabaseService? supabaseService})
      : _storageService = storageService ?? StorageService(),
        _supabaseService = supabaseService ?? SupabaseService() {
    init();
  }

  // Getters
  List<Trip> get trips => _trips;
  String get currentTripId => _currentTripId;
  dynamic get selectedDay => _selectedDay;
  String? get selectedItemId => _selectedItemId;
  String get activeTab => _activeTab;
  bool get isLoading => _isLoading;

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

  // 초기화 및 로드
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    // 1. 로컬 SharedPreferences 우선 로드
    final result = await _storageService.loadTrips();
    _trips = result.trips;
    _currentTripId = result.currentTripId;
    _selectedDay = 1;
    _selectedItemId = null;
    _isLoading = false;
    notifyListeners();

    // 2. Supabase 클라우드 실시간 데이터 자동 조회 및 복원
    await syncFromCloud();
  }

  /// Supabase 클라우드에서 여행 계획 목록 조회 및 병합 동기화
  Future<void> syncFromCloud() async {
    _isSyncing = true;
    _syncMessage = '클라우드 데이터 확인 중...';
    notifyListeners();

    try {
      final cloudTrips = await _supabaseService.fetchTrips();
      if (cloudTrips.isNotEmpty) {
        final Map<String, Trip> tripMap = {};
        for (final t in _trips) {
          if (t.metadata.id.isNotEmpty) {
            tripMap[t.metadata.id] = t;
          }
        }
        // 클라우드 데이터로 덮어쓰기/병합
        for (final ct in cloudTrips) {
          if (ct.metadata.id.isNotEmpty) {
            tripMap[ct.metadata.id] = ct;
          }
        }

        _trips = tripMap.values.toList();
        // 클라우드에 현재 여행 ID가 없으면 첫 번째 클라우드 여행으로 활성화
        if (!_trips.any((t) => t.metadata.id == _currentTripId) && cloudTrips.isNotEmpty) {
          _currentTripId = cloudTrips.first.metadata.id;
        } else if (cloudTrips.isNotEmpty && _currentTripId == 'trip-my-first-trip' && cloudTrips.any((t) => t.metadata.id == 'trip-my-first-trip')) {
          _currentTripId = 'trip-my-first-trip';
        }

        await _storageService.saveTrips(_trips, _currentTripId);
        _syncMessage = '클라우드 데이터 동기화 완료';
      } else {
        _syncMessage = '클라우드 연동 완료';
      }
    } catch (_) {
      _syncMessage = '오프라인 모드';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storageService.saveTrips(_trips, _currentTripId);
    // Supabase 클라우드 백그라운드 자동 동기화
    final cur = currentTrip;
    if (cur.metadata.id.isNotEmpty) {
      _supabaseService.syncTrip(cur);
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
    _supabaseService.deleteTrip(tripId);
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
}
