/// @intent 여행 기본 메타데이터(제목, 여행 기간, 참가자, 기준 통화) 설정 및 수정 다이얼로그
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

class TripSettingsDialog extends StatefulWidget {
  const TripSettingsDialog({super.key});

  @override
  State<TripSettingsDialog> createState() => _TripSettingsDialogState();
}

class _TripSettingsDialogState extends State<TripSettingsDialog> {
  late TextEditingController _titleController;
  late TextEditingController _newParticipantController;
  String _startDate = '';
  String _endDate = '';
  late List<String> _participants;
  late String _baseCurrency;

  @override
  void initState() {
    super.initState();
    final meta = context.read<TripProvider>().currentTrip.metadata;
    _titleController = TextEditingController(text: meta.title);
    _newParticipantController = TextEditingController();
    _startDate = meta.startDate;
    _endDate = meta.endDate;
    _participants = List<String>.from(meta.participants);
    _baseCurrency = meta.baseCurrency;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newParticipantController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    DateTime initial = DateTime.now();
    final currentStr = isStart ? _startDate : _endDate;
    if (currentStr.isNotEmpty) {
      final parsed = DateTime.tryParse(currentStr);
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isStart ? '여행 시작일 선택' : '여행 종료일 선택',
    );

    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        if (isStart) {
          _startDate = formatted;
          if (_endDate.isNotEmpty && _endDate.compareTo(_startDate) < 0) {
            _endDate = _startDate;
          }
        } else {
          _endDate = formatted;
        }
      });
    }
  }

  void _addParticipant() {
    final text = _newParticipantController.text.trim();
    if (text.isNotEmpty && !_participants.contains(text)) {
      setState(() {
        _participants.add(text);
        _newParticipantController.clear();
      });
    }
  }

  void _removeParticipant(String member) {
    if (_participants.length <= 1) {
      AppToast.warning(context, '참가자는 최소 1명 이상이어야 합니다.');
      return;
    }
    setState(() {
      _participants.remove(member);
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppToast.warning(context, '여행 제목을 입력해주세요.');
      return;
    }

    final provider = context.read<TripProvider>();
    final updatedMeta = provider.currentTrip.metadata.copyWith(
      title: title,
      startDate: _startDate,
      endDate: _endDate,
      participants: _participants,
      baseCurrency: _baseCurrency,
    );

    provider.updateMetadata(updatedMeta);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '여행 정보 설정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '여행 제목',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          hintText: '여행 제목 입력',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '여행 기간',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: true),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_startDate.isEmpty ? '시작일 선택' : _startDate),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('~'),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: false),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_endDate.isEmpty ? '종료일 선택' : _endDate),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '기준 통화',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _baseCurrency,
                        items: const [
                          DropdownMenuItem(value: 'KRW', child: Text('대한민국 원 (KRW)')),
                          DropdownMenuItem(value: 'JPY', child: Text('일본 엔 (JPY)')),
                          DropdownMenuItem(value: 'USD', child: Text('미국 달러 (USD)')),
                          DropdownMenuItem(value: 'EUR', child: Text('유럽 유로 (EUR)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _baseCurrency = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '참가자 목록',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newParticipantController,
                              decoration: const InputDecoration(
                                hintText: '새 참가자 이름',
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addParticipant(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addParticipant,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            child: const Text('추가'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _participants.map((m) {
                          return Chip(
                            label: Text(m),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeParticipant(m),
                            backgroundColor: AppTheme.primaryLight,
                            side: BorderSide.none,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('저장'),
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
