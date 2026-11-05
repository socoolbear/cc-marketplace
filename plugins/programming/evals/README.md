# daemon evals

`claude plugin eval` 스위트. `server-chassis` 스킬의 발동 (trigger) 과, 스킬이 답변 품질을 올리는지 (quality) 를 본다. 결과는 참고용이고 릴리스 게이트가 아니다.

## 실행

repo 루트에서:

```
# 발동
claude plugin eval plugins/programming --trust-plugin --tag trigger --ablation none --runs 3 -j 4
# 품질: 스킬 있음·없음을 같은 기준으로 채점해 차이를 본다
claude plugin eval plugins/programming --trust-plugin --tag quality --ablation with-without --judge-model sonnet --runs 3 -j 4
# 스킬 효과: 어려운 구현 과제
claude plugin eval plugins/programming --trust-plugin --tag hard --ablation with-without --judge-model sonnet --runs 3 -j 4
# 요구사항: 새 서버 설계에 컴포넌트별 판정이 나오는지
claude plugin eval plugins/programming --trust-plugin --tag requirement --ablation none --judge-model sonnet --runs 3 -j 4
```

- 쓰기 도구가 없다. 발동 케이스는 스킬을 부르는지만, 품질 케이스는 최종 답변만 채점한다.
- 발동 케이스의 `allowed_tools` 는 `[Skill]` 이다. references 를 읽다가 턴 한도에 닿지 않게 하고, 판정에 필요 없는 비용을 줄인다.
- 발동 케이스를 더 나눠 돌릴 수 있다: `--tag should-fire`, `--tag should-not-fire`.
- 결과는 `evals/results/` 에 쌓이며 gitignore 된다.

## 케이스

| 태그 | 수 | 통과 기준 |
|---|---|---|
| `should-fire` (`pos-*`) | 19 | Skill 도구로 `server-chassis` 를 1회 이상 부른다. 요청 문장에 description 의 트리거 문구를 그대로 쓰지 않았다 |
| `should-not-fire` (`neg-*`) | 12 | 부르지 않는다. 일회성 스크립트·HTTP 프레임워크 위 API·CRUD 서버·launchd/systemd 운영 같은 제외 대상과 무관한 작업 |
| `quality` (`q-*`) | 5 | 과제별 LLM 채점 기준 4개 (`graders/`). 스킬 문서를 읽지 않은 에이전트가 공식 문서 기준으로 "운영에 올리면 유실·중복·장애가 나는 실수" 를 골라 썼다 — 스킬에서 기준을 뽑으면 스킬 쪽에 유리한 순환 측정이 된다 |
| `hard` (`q-hard-*`) | 3 | 구현 과제. 강한 모델이 스킬 없이 놓치는 운영 실수를 잰다. 기준은 스킬을 읽지 않은 작성자가 공식 문서로 썼다. 스킬 효과는 이 시험의 with-without 으로 본다 |
| `requirement` (`req-*`) | 1 | 새 서버 설계 답변이 컴포넌트마다 판정을 내는가. 스킬의 요구를 그대로 재는 **순환 측정**이라 품질 지표로 쓰지 않고, 스킬 있는 쪽만 돌린다 |

## 한계

- 모델 출력이 확률적이라 `runs: 1` 결과는 흔들릴 수 있다. description 을 고친 뒤에는 `--runs 3` 으로 다시 본다.
- 스킬을 켠 쪽은 references 를 읽고 답이 길어져 300s 기본 시간 제한에 걸릴 수 있다 (시간 초과 run 은 0점).
- LLM 채점이 틀릴 수 있다. 실패 항목은 답변 원문 (`results/*/aggregate-result.json` 의 `evidence`) 을 읽고 확인한다 — 2026-10 측정에서 종료·drain 기준이 요건을 다 갖춘 답을 FAIL 로 판정한 사례가 있었다.
- 빈 작업 디렉토리에서 돈다. 실제 프로젝트 코드가 있으면 발동률이 달라질 수 있다.
