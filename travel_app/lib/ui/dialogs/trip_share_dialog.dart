/// @intent 여행 초대 코드 발급/복사 및 동행자 참여 멤버 권한 관리 다이얼로그
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

class TripShareDialog extends StatefulWidget {
  const TripShareDialog({super.key});

  @override
  State<TripShareDialog> createState() => _TripShareDialogState();
}

class _TripShareDialogState extends State<TripShareDialog> {
  String _inviteCode = '';
  bool _isLoadingCode = true;

  @override
  void initState() {
    super.initState();
    _loadOrCreateInviteCode();
  }

  Future<void> _loadOrCreateInviteCode() async {
    final tripProvider = context.read<TripProvider>();
    final authProvider = context.read<AuthProvider>();

    final code = await tripProvider.getOrGenerateInviteCode(
      tripProvider.currentTrip.metadata.id,
      ownerName: authProvider.displayName ?? '호스트 여행자',
    );

    if (mounted) {
      setState(() {
        _inviteCode = code;
        _isLoadingCode = false;
      });
    }
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: 'TRIP-$code'));
    AppToast.success(context, '초대 코드(TRIP-$code)가 복사되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = context.watch<TripProvider>();
    final trip = tripProvider.currentTrip;
    final meta = trip.metadata;
    final isOwner = tripProvider.currentTripRole == 'owner';
    final members = meta.members;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더 영역
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.share_rounded,
                      color: AppTheme.primaryDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '여행 공유 및 동행자 관리',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          meta.title.isEmpty ? '나의 여행 계획' : meta.title,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 초대 코드 발급 및 복사 카드
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '동행자 초대 코드',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingCode)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                'TRIP-$_inviteCode',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.0,
                                  color: AppTheme.primaryDark,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _inviteCode.isEmpty ? null : () => _copyToClipboard(_inviteCode),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('복사'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      '동행자가 MyTripLog 앱에서 위 6자리 코드를 입력하면 함께 일정을 실시간으로 편집할 수 있습니다.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 참여자 목록 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '참여 멤버 (${members.length + 1}명)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOwner ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOwner ? '내 권한: 소유자 (Owner)' : '내 권한: ${tripProvider.currentTripRole.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOwner ? AppTheme.primaryDark : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 참여자 리스트
              Expanded(
                child: ListView(
                  children: [
                    // 1. 소유자(Host) 카드
                    _buildMemberTile(
                      displayName: meta.ownerName.isNotEmpty ? meta.ownerName : '호스트 여행자',
                      email: '여행 생성자',
                      roleLabel: '소유자',
                      roleColor: AppTheme.primaryDark,
                      roleBgColor: AppTheme.primaryLight,
                      isOwnerRow: true,
                      canManage: false,
                    ),

                    // 2. 참여자 목록
                    if (members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '아직 초대된 동행자가 없습니다.\n위 초대 코드를 공유해 함께 일정을 계획해보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    else
                      ...members.map((member) => _buildMemberTile(
                            displayName: member.displayName,
                            email: member.email,
                            roleLabel: member.role == 'editor' ? '편집자' : '뷰어(읽기전용)',
                            roleColor: member.role == 'editor' ? const Color(0xFF059669) : const Color(0xFF64748B),
                            roleBgColor: member.role == 'editor' ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
                            isOwnerRow: false,
                            canManage: isOwner,
                            onRoleChange: (newRole) async {
                              await tripProvider.updateMemberRole(member.userId, newRole);
                            },
                            onRemove: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('동행자 내보내기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  content: Text('${member.displayName}님을 이 여행에서 제외하시겠습니까?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('취소', style: TextStyle(color: AppTheme.textSecondary)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFEF4444),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('내보내기'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await tripProvider.removeMember(member.userId);
                              }
                            },
                          )),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // 하단 닫기 버튼
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '확인',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberTile({
    required String displayName,
    required String email,
    required String roleLabel,
    required Color roleColor,
    required Color roleBgColor,
    required bool isOwnerRow,
    required bool canManage,
    ValueChanged<String>? onRoleChange,
    VoidCallback? onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isOwnerRow ? AppTheme.primaryLight : const Color(0xFFF1F5F9),
            child: Icon(
              isOwnerRow ? Icons.person_rounded : Icons.person_outline_rounded,
              size: 18,
              color: isOwnerRow ? AppTheme.primaryDark : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: roleBgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: roleColor,
              ),
            ),
          ),
          if (canManage && onRoleChange != null && onRemove != null) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (value) {
                if (value == 'editor' || value == 'viewer') {
                  onRoleChange(value);
                } else if (value == 'remove') {
                  onRemove();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'editor',
                  height: 38,
                  child: Text('편집자(Editor)로 변경', style: TextStyle(fontSize: 13)),
                ),
                const PopupMenuItem(
                  value: 'viewer',
                  height: 38,
                  child: Text('뷰어(Viewer)로 변경', style: TextStyle(fontSize: 13)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'remove',
                  height: 38,
                  child: Text('내보내기', style: TextStyle(fontSize: 13, color: Color(0xFFEF4444))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
