/// @intent 여행 메타데이터 도메인 모델 정의, 공유 초대 코드(inviteCode) 및 참여자(TripMember) 다중 협업 권한 제어
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'trip_member.dart';

class TripMetadata {
  final String id;
  final String title;
  final String startDate;
  final String endDate;
  final List<String> participants;
  final String baseCurrency;
  final Map<String, double> customRates;
  final String ownerId;
  final String ownerName;
  final String inviteCode;
  final List<TripMember> members;

  const TripMetadata({
    required this.id,
    required this.title,
    this.startDate = '',
    this.endDate = '',
    this.participants = const ['신랑', '신부'],
    this.baseCurrency = 'KRW',
    this.customRates = const {
      'KRW': 1.0,
      'USD': 1350.0,
      'JPY': 9.2,
      'EUR': 1460.0,
      'CNY': 185.0,
      'GBP': 1720.0,
    },
    this.ownerId = '',
    this.ownerName = '',
    this.inviteCode = '',
    this.members = const [],
  });

  /// 현재 사용자의 여행 권한 판정 ('owner' | 'editor' | 'viewer')
  String currentUserRole(String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty || currentUserId == 'guest' || currentUserId == 'guest-local-user') {
      return 'owner'; // 오프라인 게스트는 본인 기기 로컬 데이터에 대해 완전한 권한 보유
    }
    if (ownerId.isEmpty || ownerId == currentUserId) {
      return 'owner';
    }
    final member = members.cast<TripMember?>().firstWhere(
          (m) => m?.userId == currentUserId,
          orElse: () => null,
        );
    return member?.role ?? 'viewer';
  }

  /// 현재 사용자가 일정을 추가/수정/삭제할 수 있는지 여부
  bool canUserEdit(String? currentUserId) {
    final role = currentUserRole(currentUserId);
    return role == 'owner' || role == 'editor';
  }

  /// 2명 이상 참여 중이거나 외부 공유된 여행인지 여부
  bool get isShared {
    if (members.length > 1) return true;
    if (members.isNotEmpty && ownerId.isNotEmpty && members.any((m) => m.userId != ownerId)) {
      return true;
    }
    return false;
  }

  TripMetadata copyWith({
    String? id,
    String? title,
    String? startDate,
    String? endDate,
    List<String>? participants,
    String? baseCurrency,
    Map<String, double>? customRates,
    String? ownerId,
    String? ownerName,
    String? inviteCode,
    List<TripMember>? members,
  }) {
    return TripMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      participants: participants ?? List<String>.from(this.participants),
      baseCurrency: baseCurrency ?? this.baseCurrency,
      customRates: customRates ?? Map<String, double>.from(this.customRates),
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      inviteCode: inviteCode ?? this.inviteCode,
      members: members ?? List<TripMember>.from(this.members),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDate': startDate,
      'endDate': endDate,
      'participants': participants,
      'baseCurrency': baseCurrency,
      'customRates': customRates,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'inviteCode': inviteCode,
      'members': members.map((m) => m.toJson()).toList(),
    };
  }

  factory TripMetadata.fromJson(Map<String, dynamic> json) {
    final rawRates = json['customRates'];
    final Map<String, double> parsedRates = {
      'KRW': 1.0,
      'USD': 1350.0,
      'JPY': 9.2,
      'EUR': 1460.0,
      'CNY': 185.0,
      'GBP': 1720.0,
    };

    if (rawRates is Map) {
      rawRates.forEach((k, v) {
        if (v is num) {
          parsedRates[k.toString().toUpperCase()] = v.toDouble();
        }
      });
    }

    final rawParticipants = json['participants'];
    List<String> parsedParticipants = ['신랑', '신부'];
    if (rawParticipants is List) {
      final list = rawParticipants
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) {
        parsedParticipants = list;
      }
    }

    final rawMembers = json['members'];
    final List<TripMember> parsedMembers = [];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        if (m is Map<String, dynamic>) {
          parsedMembers.add(TripMember.fromJson(m));
        } else if (m is Map) {
          parsedMembers.add(TripMember.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }

    return TripMetadata(
      id: json['id'] as String? ?? 'trip-my-first-trip',
      title: json['title'] as String? ?? '나의 여행 계획',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      participants: parsedParticipants,
      baseCurrency: (json['baseCurrency'] as String? ?? 'KRW').toUpperCase(),
      customRates: parsedRates,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
      members: parsedMembers,
    );
  }
}
