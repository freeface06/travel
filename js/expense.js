/**
 * @intent 다중 통화 환율 환산 및 최소 송금 횟수 그리디(Greedy) 1/N 정산 엔진
 * @agent  Gemini/manager-develop
 * @branch feat/mytriplog-core
 * @author @developer_name
 * @date   2026-09-29
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TripExpense = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // 기본 환율표 (KRW 기준)
  const DEFAULT_RATES = {
    KRW: 1.0,
    USD: 1350.0,
    JPY: 9.2,
    EUR: 1460.0,
    CNY: 185.0,
    GBP: 1720.0
  };

  /**
   * 통화 환산 (기본 통화 또는 임의의 통화 간 변환)
   * @param {number} amount - 금액
   * @param {string} fromCurrency - 원래 통화
   * @param {string} toCurrency - 대상 통화
   * @param {object} customRates - 사용자 지정 환율 객체
   * @returns {number} 환산된 금액
   */
  function convertCurrency(amount, fromCurrency = 'KRW', toCurrency = 'KRW', customRates = {}) {
    const num = Number(amount) || 0;
    if (num === 0) return 0;

    const from = (fromCurrency || 'KRW').toUpperCase();
    const to = (toCurrency || 'KRW').toUpperCase();
    if (from === to) return num;

    const rates = Object.assign({}, DEFAULT_RATES, customRates);
    const fromRate = rates[from] !== undefined ? rates[from] : 1.0;
    const toRate = rates[to] !== undefined ? rates[to] : 1.0;

    // 1단계: KRW 기준으로 변환
    const inKRW = num * fromRate;
    // 2단계: 대상 통화로 변환
    const converted = inKRW / toRate;

    // KRW 및 JPY는 소수점 반올림, 그 외는 소수점 둘째 자리
    if (to === 'KRW' || to === 'JPY') {
      return Math.round(converted);
    }
    return Math.round(converted * 100) / 100;
  }

  /**
   * 전체 여행 지출 집계 요약 계산
   * @param {Array<object>} items - 일정 아이템 목록
   * @param {Array<string>} participants - 참가자 목록
   * @param {string} baseCurrency - 기준 통화 (기본 'KRW')
   * @param {object} customRates - 환율표
   * @returns {object} 집계 결과
   */
  function calculateExpenseSummary(items = [], participants = [], baseCurrency = 'KRW', customRates = {}) {
    const validItems = Array.isArray(items) ? items : [];
    const members = Array.isArray(participants) && participants.length > 0 ? [...participants] : [];

    let totalInBase = 0;
    const byCategory = {};
    const byCurrency = {};
    const paidByMember = {};

    members.forEach((m) => {
      paidByMember[m] = 0;
    });

    validItems.forEach((item) => {
      const rawCost = Number(item.cost) || 0;
      if (rawCost <= 0) return;

      const currency = (item.currency || baseCurrency).toUpperCase();
      const payer = item.payer ? item.payer.trim() : (members[0] || '공통');
      const category = (item.category || 'OTHER').toUpperCase();

      const costInBase = convertCurrency(rawCost, currency, baseCurrency, customRates);
      totalInBase += costInBase;

      // 카테고리별 누적
      byCategory[category] = (byCategory[category] || 0) + costInBase;

      // 원통화별 누적
      byCurrency[currency] = (byCurrency[currency] || 0) + rawCost;

      // 참가자별 결제액 누적
      if (!paidByMember[payer]) {
        paidByMember[payer] = 0;
      }
      paidByMember[payer] += costInBase;
    });

    return {
      totalInBase,
      baseCurrency,
      byCategory,
      byCurrency,
      paidByMember,
      participantCount: members.length
    };
  }

  /**
   * 1/N 분담금 및 잔여 단수 분배
   * @param {number} totalAmount - 총 지출액
   * @param {Array<string>} participants - 참여자 목록
   * @param {string} currency - 통화 코드
   * @returns {object} { [member]: shareAmount }
   */
  function calculateIndividualShares(totalAmount, participants, currency = 'KRW') {
    const shares = {};
    const n = participants.length;
    if (n === 0) return shares;
    if (totalAmount <= 0) {
      participants.forEach((m) => {
        shares[m] = 0;
      });
      return shares;
    }

    const isIntegerCurrency = currency === 'KRW' || currency === 'JPY';

    if (isIntegerCurrency) {
      const total = Math.round(totalAmount);
      const baseShare = Math.floor(total / n);
      let remainder = total - baseShare * n;

      participants.forEach((m, idx) => {
        if (idx < remainder) {
          shares[m] = baseShare + 1;
        } else {
          shares[m] = baseShare;
        }
      });
    } else {
      const totalCents = Math.round(totalAmount * 100);
      const baseCent = Math.floor(totalCents / n);
      let remCent = totalCents - baseCent * n;

      participants.forEach((m, idx) => {
        const memberCents = idx < remCent ? baseCent + 1 : baseCent;
        shares[m] = memberCents / 100;
      });
    }

    return shares;
  }

  /**
   * 그리디 알고리즘 기반 최소 횟수 1/N 정산 송금 내역 산출
   * @param {Array<string>} participants - 참가자 목록
   * @param {Array<object>} items - 일정 아이템 목록
   * @param {string} baseCurrency - 기준 통화
   * @param {object} customRates - 환율
   * @returns {object} { settlements: Array<{from, to, amount, currency}>, summary: object, balances: Array<object> }
   */
  function calculateSettlements(participants = [], items = [], baseCurrency = 'KRW', customRates = {}) {
    const members = Array.from(new Set(participants.map((p) => (p || '').trim()).filter(Boolean)));
    const summary = calculateExpenseSummary(items, members, baseCurrency, customRates);

    // 참가자가 0명이거나 1명이면 송금 불필요
    if (members.length <= 1 || summary.totalInBase <= 0) {
      const balances = members.map((m) => ({
        member: m,
        paid: summary.paidByMember[m] || 0,
        share: summary.totalInBase,
        net: 0
      }));
      return {
        settlements: [],
        summary,
        balances
      };
    }

    // 각 참가자별 공평한 분담금(Share) 계산
    const shares = calculateIndividualShares(summary.totalInBase, members, baseCurrency);

    // 순 차액(Net Balance) 계산: Net = Paid - Share
    // Net > 0: 돈을 더 냈으므로 받아야 함 (Creditor)
    // Net < 0: 돈을 덜 냈으므로 보내야 함 (Debtor)
    const balances = members.map((m) => {
      const paid = summary.paidByMember[m] || 0;
      const share = shares[m] || 0;
      const net = paid - share;
      return { member: m, paid, share, net };
    });

    const debtors = [];
    const creditors = [];

    balances.forEach((b) => {
      if (b.net < -0.001) {
        debtors.push({ member: b.member, amount: -b.net });
      } else if (b.net > 0.001) {
        creditors.push({ member: b.member, amount: b.net });
      }
    });

    const settlements = [];
    const isInteger = baseCurrency === 'KRW' || baseCurrency === 'JPY';

    // 그리디 매칭 알고리즘 (가장 많이 줘야 할 사람과 가장 많이 받아야 할 사람을 상계)
    while (debtors.length > 0 && creditors.length > 0) {
      debtors.sort((a, b) => b.amount - a.amount);
      creditors.sort((a, b) => b.amount - a.amount);

      const debtor = debtors[0];
      const creditor = creditors[0];

      const transferAmount = Math.min(debtor.amount, creditor.amount);
      const roundedAmount = isInteger ? Math.round(transferAmount) : Math.round(transferAmount * 100) / 100;

      if (roundedAmount > 0) {
        settlements.push({
          from: debtor.member,
          to: creditor.member,
          amount: roundedAmount,
          currency: baseCurrency
        });
      }

      debtor.amount -= transferAmount;
      creditor.amount -= transferAmount;

      if (debtor.amount <= 0.001) {
        debtors.shift();
      }
      if (creditor.amount <= 0.001) {
        creditors.shift();
      }
    }

    return {
      settlements,
      summary,
      balances
    };
  }

  /**
   * 금액 포맷팅 문자열 생성 (예: 120,000 KRW 또는 $100.50)
   * @param {number} amount 
   * @param {string} currency 
   * @returns {string}
   */
  function formatAmount(amount, currency = 'KRW') {
    const num = Number(amount) || 0;
    const curr = (currency || 'KRW').toUpperCase();

    if (curr === 'KRW') {
      return `${Math.round(num).toLocaleString('ko-KR')}원`;
    }
    if (curr === 'JPY') {
      return `${Math.round(num).toLocaleString('ja-JP')}엔`;
    }
    if (curr === 'USD') {
      return `$${num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }
    if (curr === 'EUR') {
      return `€${num.toLocaleString('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }
    return `${num.toLocaleString()} ${curr}`;
  }

  return {
    DEFAULT_RATES,
    convertCurrency,
    calculateExpenseSummary,
    calculateIndividualShares,
    calculateSettlements,
    formatAmount
  };
});
