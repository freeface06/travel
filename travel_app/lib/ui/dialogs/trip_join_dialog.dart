/// @intent 동행자 초대 코드 입력을 통한 여행 참여(Join) 모달 다이얼로그
/// @agent Gemini/manager-develop
/// @branch feat/v2.0.0-commercial
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/trip.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

class TripJoinDialog extends StatefulWidget {
  const TripJoinDialog({super.key});

  @override
  State<TripJoinDialog> createState() => _TripJoinDialogState();
}

class _TripJoinDialogState extends State<TripJoinDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final rawCode = _codeController.text.trim();
    if (rawCode.isEmpty) {
      setState(() => _errorMessage = '초대 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final tripProvider = context.read<TripProvider>();
    final authProvider = context.read<AuthProvider>();

    try {
      // 1. 여행 미리보기 조회
      final previewTrip = await tripProvider.previewTripByInviteCode(rawCode);
      if (previewTrip == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '유효하지 않은 초대 코드입니다. 코드를 다시 확인해주세요.';
        });
        return;
      }

      if (!mounted) return;

      // 2. 여행 미리보기 확인 모달
      final confirmed = await _showPreviewConfirmation(previewTrip);
      if (confirmed != true) {
        setState(() => _isLoading = false);
        return;
      }

      // 3. 실제 참여 처리
      final success = await tripProvider.joinTripByInviteCode(
        rawCode,
        userEmail: authProvider.email,
        userDisplayName: authProvider.displayName,
      );

      if (success && mounted) {
        AppToast.success(context, '\'${previewTrip.metadata.title}\' 여행에 참여했습니다.');
        Navigator.pop(context, true);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '여행 참여에 실패했습니다. 다시 시도해주세요.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '처리 중 오류가 발생했습니다: $e';
        });
      }
    }
  }

  Future<bool?> _showPreviewConfirmation(Trip trip) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.flight_takeoff, color: AppTheme.primary, size: 22),
            SizedBox(width: 8),
            Text(
              '여행 참여 확인',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip.metadata.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            if (trip.metadata.startDate.isNotEmpty && trip.metadata.endDate.isNotEmpty)
              Text(
                '일정: ${trip.metadata.startDate} ~ ${trip.metadata.endDate}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            Text(
              '호스트: ${trip.metadata.ownerName.isNotEmpty ? trip.metadata.ownerName : '동행 호스트'}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            Text(
              '등록된 일정: ${trip.items.length}개 항목',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            const Text(
              '이 여행에 동행자로 참여하시겠습니까?\n참여 시 내 여행 목록에 추가되며 함께 일정을 확인하고 편집할 수 있습니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('참여하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.group_add_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '초대 코드로 여행 참여',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '동행자로부터 전달받은 6자리 초대 코드를 입력해주세요.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 20),

              // 에러 메시지
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // 초대 코드 입력 필드
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                  LengthLimitingTextInputFormatter(11), // 'TRIP-XXXXXX' 호환
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '예: TRIP-A8K2F9',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    letterSpacing: 0,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: const Icon(Icons.key_rounded, size: 20, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _handleJoin(),
              ),
              const SizedBox(height: 24),

              // 버튼 행
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('취소', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              '여행 찾기 및 참여',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
