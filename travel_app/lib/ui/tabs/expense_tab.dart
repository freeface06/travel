/// @intent 여행 총 예상 경비 요약, 카테고리별 지출 분석 및 확정 플랜(isSelected) 기준 일차별 지출 현황 탭 화면
/// @agent Gemini/manager-develop
/// @branch feat/flutter-travel-app
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/expense_calculator.dart';
import '../theme/app_theme.dart';

class ExpenseTab extends StatelessWidget {
  const ExpenseTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final currentTrip = provider.currentTrip;
    final meta = currentTrip.metadata;

    final summary = ExpenseCalculator.calculateSettlements(
      meta.participants,
      currentTrip.items,
      baseCurrency: meta.baseCurrency,
      customRates: meta.customRates,
    );

    // 일차별 지출 계산 (확정 플랜만 반영)
    final Map<int, double> dayExpenseMap = {};
    for (final item in currentTrip.items) {
      if (item.isSelected && item.cost > 0) {
        final converted = ExpenseCalculator.convertCurrency(
          item.cost,
          fromCurrency: item.currency,
          toCurrency: meta.baseCurrency,
          customRates: meta.customRates,
        );
        dayExpenseMap[item.day] = (dayExpenseMap[item.day] ?? 0.0) + converted;
      }
    }

    final totalCostItemsCount = currentTrip.items.where((i) => i.isSelected && i.cost > 0).length;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // 1. 총 예상 경비 요약 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x332563EB), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '총 예상 여행 경비',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '기준 통화: ${summary.baseCurrency}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ExpenseCalculator.formatAmount(summary.totalInBase, summary.baseCurrency),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                totalCostItemsCount > 0 ? '총 $totalCostItemsCount건의 지출 항목 등록됨' : '등록된 지출 내역 없음',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. 카테고리별 지출 분석 및 프로그레스 바
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '카테고리별 지출 분석',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
                if (summary.totalInBase == 0)
                  const Text(
                    '등록된 비용 정보가 없습니다.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  )
                else ...[
                  ...summary.byCategory.entries.map((entry) {
                    final catKey = entry.key;
                    final amount = entry.value;
                    if (amount <= 0) return const SizedBox.shrink();

                    final catMeta = AppTheme.getCategoryMeta(catKey);
                    final percent = summary.totalInBase > 0 ? (amount / summary.totalInBase) : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(catMeta.icon, size: 14, color: catMeta.color),
                                  const SizedBox(width: 6),
                                  Text(catMeta.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Text(
                                '${ExpenseCalculator.formatAmount(amount, summary.baseCurrency)} (${(percent * 100).toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: percent.clamp(0.0, 1.0),
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: catMeta.color,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),

        // 3. 일차별 지출 현황 (Day 1..N)
        if (dayExpenseMap.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '일차별 지출 현황',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(provider.maxDay, (idx) {
                    final d = idx + 1;
                    final dayCost = dayExpenseMap[d] ?? 0.0;
                    final dayPercent = summary.totalInBase > 0 ? (dayCost / summary.totalInBase) : 0.0;
                    final dayColor = AppTheme.getDayColor(d);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: dayColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Day $d',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dayColor),
                                ),
                              ),
                              Text(
                                '${ExpenseCalculator.formatAmount(dayCost, summary.baseCurrency)} (${(dayPercent * 100).toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: dayPercent.clamp(0.0, 1.0),
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: dayColor,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
