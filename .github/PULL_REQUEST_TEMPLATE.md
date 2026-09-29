## 📌 작업 개요 (Summary)
<!-- 변경 사항 및 기능에 대한 간략한 요약을 작성해주세요. -->

## 🤖 AI 협업 메타데이터 (AI Bill of Materials)
- **사용 도구 (Tool/Harness)**: <!-- [ ] Claude Code  [ ] Cursor  [ ] Gemini  [ ] Copilot -->
- **사용 모델 (Model)**: <!-- Claude 3.7 Sonnet / GPT-4o / Gemini 2.0 Flash 등 -->
- **적용 스킬 (Skills Used)**: <!-- e.g. strict-unit-tester, trust-auditor, secops-guard -->
- **담당 페르소나 (Role)**: <!-- e.g. manager-develop, manager-spec, manager-docs -->

## 🛡️ TRUST 5 엔터프라이즈 품질 검증 체크리스트
PR을 제출하기 전 다음 항목들을 모두 확인했습니까?
- [ ] **T (Tested)**: 타입체크 에러 0건, 단위 테스트(Happy Path 1개 + Edge Case 2개 이상) 통과
- [ ] **R (Readable)**: 린트/포맷 경고 0건, 네이밍 컨벤션 준수
- [ ] **U (Unified)**: 계층 분리 아키텍처 및 불변성 패턴 준수
- [ ] **S (Secured)**: API 키/자격증명 노출 0건 (Secret Scanning 통과), OWASP 취약점 부재
- [ ] **T (Trackable)**: 코드 상단 `@intent` 출처 블록 주석 100% 명시

## ⚖️ 계획과 감사의 분리 (Plan-Audit Separation)
- [ ] 독립 심사자(`trust-auditor`)의 4차원 심사(기능·보안·작법·일관성) PASS 완료

## 💥 Breaking Changes 여부
- [ ] 없음
- [ ] 있음 (경계면/DTO/API 스펙 변경 내용 상세 기재 필요)

## 📋 리뷰어 참고사항
<!-- 리뷰어가 특별히 확인해주었으면 하는 부분이나 설계상의 고민을 작성해주세요. -->
