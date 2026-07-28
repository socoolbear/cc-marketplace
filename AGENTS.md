# cc-marketplace

socoolbear 의 개인용 Claude Code 플러그인 마켓플레이스. 플러그인은 `plugins/<name>/` 에 두고 루트 `.claude-plugin/marketplace.json` 에 등재한다.

## 검증 명령 (완료 주장 전 반드시 실행)

- 매니페스트 JSON 파싱: `for f in .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json; do python3 -m json.tool "$f" >/dev/null || echo "INVALID $f"; done`
- 버전 일치: 각 `plugins/<n>/.claude-plugin/plugin.json` 의 `version` == `marketplace.json` 의 동명 플러그인 `version`
- 스킬 내부 링크 실재: 각 `skills/*/SKILL.md` 와 그 참조 파일의 상대 경로가 실재하는지

## 경계

- Never: 플러그인 산출물에 영향을 주는 변경 (스킬 본문·references·규약 문서) 을 하면서 **버전 bump 를 빠뜨리기**
- Always: 위 변경 시 `plugins/<n>/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 해당 플러그인 `version` 을 **동시에** minor 이상 올린다 (두 값이 어긋나면 설치본과 목록이 갈린다)
- Always: 스킬 자료는 `skills/<skill>/` 안에 둔다 (`references/`, `scripts/`) — 스킬 디렉토리 밖 참조 금지
- Ask first: 플러그인 삭제, 마켓플레이스 이름·소유자 변경

## 문서 유지 규칙

- 플러그인의 모드·산출물 구조를 바꾸는 변경은 같은 커밋에서 해당 플러그인의 규약 문서와 README 표를 갱신
- 작업 중 거짓으로 판명된 문서 문장은 같은 커밋에서 수정
