# deprecate · 삭제

deprecate 와 삭제는 다른 단계다. deprecate 는 "더 쓰지 말고 이걸 쓰라" 는 안내이고, 삭제는 그 뒤 사용자가 따로 정한다.

## deprecate

1. **근거** — 공식 기능 링크와 기능 비교표 (플러그인이 하는 일 / 공식 기능 / 빠지는 것). 빠지는 것이 핵심 사용 사례면 deprecate 하지 않는다 ([`sources.md`](sources.md) 판정 기준).
2. **표시** — 대체되는 스킬의 `SKILL.md` frontmatter `description` 맨 앞에 `[deprecated → <대체 기능>]` 을 붙인다. 플러그인 안 스킬이 **모두** 대체될 때만 `marketplace.json`·`plugin.json` 의 `description` 에도 붙인다. 일부만이면 그 설명에서 해당 스킬 소개를 같은 표시로 바꾼다. 스킬이 없는 플러그인 (훅·명령만) 은 `plugin.json`·`marketplace.json` 의 `description` 에 표시한다 (생성 파일은 손대지 않는다).
3. **안내** — 대체되는 `SKILL.md` 본문 맨 위에 대체 기능을 쓰는 법 1~2줄과 남은 차이를 적는다. 스킬이 호출되면 이 안내를 먼저 전한다.
4. **버전** — minor 를 올린다 (`plugin.json`·`marketplace.json` 동시).
5. **기록** — `docs/evolution/<n>.md` 에 deprecate 일자·근거·**삭제 재검토 조건** (예: "deprecate 후 60일 + 그 기간 memory·이슈에 언급 없음") 을 적는다.

## 삭제

`AGENTS.md` 의 "Ask first: 플러그인 삭제" 를 따른다. 사용자 확인 후 별도 커밋으로:

- `marketplace.json` 에서 항목 제거, `plugins/<n>/` 삭제
- 다른 플러그인·문서가 가리키는 곳이 없는지 검색 (`grep -rn <n>`)
- 결정 기록 파일은 남긴다 (왜 사라졌는지의 기록)
