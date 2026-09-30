/// @intent 다중 사용자 여행 공유 및 협업 멤버(TripMember) 도메인 모델 정의
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

class TripMember {
  final String userId;
  final String email;
  final String displayName;
  final String role; // 'owner' | 'editor' | 'viewer'
  final String joinedAt;

  const TripMember({
    required this.userId,
    required this.email,
    required this.displayName,
    this.role = 'editor',
    required this.joinedAt,
  });

  bool get isOwner => role == 'owner';
  bool get canEdit => role == 'owner' || role == 'editor';
  bool get isViewer => role == 'viewer';

  TripMember copyWith({
    String? userId,
    String? email,
    String? displayName,
    String? role,
    String? joinedAt,
  }) {
    return TripMember(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'displayName': displayName,
      'role': role,
      'joinedAt': joinedAt,
    };
  }

  factory TripMember.fromJson(Map<String, dynamic> json) {
    return TripMember(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      role: json['role'] as String? ?? 'editor',
      joinedAt: json['joinedAt'] as String? ?? DateTime.now().toUtc().toIso8601String(),
    );
  }
}
