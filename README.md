# Daily Stamp (macOS Menu Bar App)

Notion 데이터베이스의 "오늘 할일" 체크박스를 메뉴바에서 빠르게 조회/추가/수정/완료 처리하는 macOS 앱입니다.

## 주요 기능

- 메뉴바 팝업에서 오늘 할일 목록 조회
- 체크박스 완료/해제
- 할일 추가 및 제목 수정
- "출석 체크" 버튼으로 오늘 페이지 생성/확인

## 사전 준비

1. Notion Integration Token 발급
2. Notion Database ID 확인
3. Integration에 데이터베이스 접근 권한 부여

## 로컬 설정 (중요)

실제 시크릿은 절대 커밋하지 않습니다.

1. 루트에 `Secrets.xcconfig` 파일 생성
2. 아래 예시를 복사해서 실제 값 입력

```xcconfig
NOTION_ACCESS_TOKEN = ntn_...
NOTION_DATABASE_ID = ...
INFOPLIST_KEY_NOTION_ACCESS_TOKEN = $(NOTION_ACCESS_TOKEN)
INFOPLIST_KEY_NOTION_DATABASE_ID = $(NOTION_DATABASE_ID)
```

또는 `Secrets.xcconfig.example`을 복사해 시작할 수 있습니다.

```bash
cp dailyStamp/Secrets.xcconfig.example Secrets.xcconfig
```