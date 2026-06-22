# EXPLAIN_A

학생이 음성으로 개념을 **설명하면**, AI가 듣고 **소크라테스식 질문**을 던지는 역방향 학습 앱
(학생 → AI). 설명 데이터를 **LEI(Learning Explanation Index)** 로 수치화합니다.

- **스택**: HTML + CSS + JS 단일 파일 · Supabase(DB/Auth) · Gemini(STT + 질문 생성 + 채점) · GitHub Pages
- **특징**: 키가 없으면 **데모 모드**로 바로 동작 → 키를 넣으면 실연동

## 파일
| 파일 | 설명 |
|---|---|
| `index.html` | 앱 전체 (5개 화면 + 연동 로직) |
| `schema.sql` | Supabase 테이블 + RLS + 트리거 |
| `README.md` | 이 문서 |

## LEI 5대 지표 (기획서 기준)
| 지표 | 산출 방식 |
|---|---|
| 개념 포함도 | 설명에 포함된 핵심개념 / 전체 핵심개념 (코드 계산) |
| 설명 정확도 | 오개념 여부 (Gemini 판정) |
| 응답 속도 | 질문 표시 → 녹음 시작까지 생각 시간 (2초 이내 100 / 30초 이상 0) |
| 설명 확장성 | 단순 암기 vs 자기 언어 (Gemini 판정) |
| 질문 대응력 | AI 추가 질문에 대한 응답 적절성 (Gemini 판정) |

**LEI = 5개 지표의 평균** (데크 예시 85·90·75·80·70 → 80 과 일치)

## 리스크분석 반영 사항
- **오개념 오탐 완충**: 오개념 판정 시 "🙋 이의 제기" 버튼 → 즉시 점수 제외 (신뢰 회복)
- **마찰 완화**: STT 결과를 직접 수정 가능, 데모 모드로 진입장벽 0
- **동기부여**: 🔥 연속 학습일 · 최고 LEI · 격려 우선 피드백
- **KPI 분리 추적**: 교사 대시보드에 LEI(기술 KPI)와 설명 지속률(사용자 KPI) 분리 표시

---

## 1. 데모로 바로 보기
`index.html`을 더블클릭하면 데모 모드로 실행됩니다. (마이크 녹음은 Gemini 키가 있어야 실제 STT 동작 → 데모 모드에서는 샘플 문장으로 대체)

## 2. 실연동 설정
앱 우측 하단 **⚙︎ API 키 설정**에서 입력 (localStorage 저장, 소스에 커밋 안 됨):

### Supabase
1. [supabase.com](https://supabase.com)에서 프로젝트 생성
2. **SQL Editor**에 `schema.sql` 붙여넣고 실행
3. **Project Settings → API**에서 `URL`, `anon public key` 복사 → 설정창에 입력
4. **Authentication → Providers → Email** 활성화

### Gemini
1. [aistudio.google.com](https://aistudio.google.com/apikey)에서 API 키 발급
2. 설정창 Gemini 칸에 입력

## 3. GitHub Pages 배포
```bash
cd ~/Desktop/explain-a
git init && git add . && git commit -m "EXPLAIN_A 초기 버전"
git branch -M main
git remote add origin https://github.com/<사용자>/explain-a.git
git push -u origin main
```
GitHub 저장소 → **Settings → Pages → Branch: main / root** 선택 → 게시.

---

## ⚠️ 보안 주의 (배포 전 필독)
- GitHub Pages는 정적 호스팅이라 **JS에 박은 API 키는 노출**됩니다.
- 현재 구조는 키를 **각 사용자 브라우저(localStorage)** 에 저장 → 소스에는 키가 없습니다. 프로토타입/내부 검증용으로 적합.
- **운영 배포 시**: Gemini 호출을 **Supabase Edge Function**(또는 서버리스 프록시)로 옮겨 키를 서버에 숨기세요. Supabase anon key는 RLS로 보호되므로 클라이언트 노출 OK.

## STT 포맷 참고
- 브라우저 `MediaRecorder`는 보통 `audio/webm`(Chrome) 또는 `audio/mp4`(Safari)를 생성합니다.
- Gemini 멀티모달에 해당 오디오를 그대로 전송합니다. 특정 브라우저에서 인식이 불안정하면 `transcribeAudio()`를 Web Speech API(`SpeechRecognition`)로 교체하는 폴백을 권장합니다.

## 다음 개발 로드맵
- [ ] 교과지식 DB를 Supabase 테이블로 이전 (현재 `CONCEPT_DB` 시드)
- [ ] 플래너 이미지 OCR → 핵심개념 추출 (기획서 1차 진단)
- [ ] 학습 레벨(1~5)별 질문 난이도 분기
- [ ] LEI 변화 → 성적 예측 모델
- [ ] Gemini 호출 Edge Function 프록시화
