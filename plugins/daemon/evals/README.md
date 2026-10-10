# daemon evals

`claude plugin eval` 스위트. `daemon-programming` 스킬의 발동 (trigger) 과, 스킬이 답변 품질을 올리는지 (quality) 를 본다. 결과는 참고용이고 릴리스 게이트가 아니다.

## 실행

repo 루트에서:

```
# 발동
claude plugin eval plugins/daemon --trust-plugin --tag trigger --ablation none -j 4
# 품질: 스킬 있음·없음을 같은 기준으로 채점해 차이를 본다
claude plugin eval plugins/daemon --trust-plugin --tag quality --ablation with-without --judge-model sonnet --runs 3 -j 4
```

- 쓰기 도구가 없다. 발동 케이스는 스킬을 부르는지만, 품질 케이스는 최종 답변만 채점한다.
- 발동 케이스를 더 나눠 돌릴 수 있다: `--tag should-fire`, `--tag should-not-fire`.
- 결과는 `evals/results/` 에 쌓이며 gitignore 된다.

## 케이스

| 태그 | 수 | 통과 기준 |
|---|---|---|
| `should-fire` (`pos-*`) | 12 | Skill 도구로 `daemon-programming` 을 1회 이상 부른다. 요청 문장에 description 의 트리거 문구를 그대로 쓰지 않았다 |
| `should-not-fire` (`neg-*`) | 9 | 부르지 않는다. 일회성 스크립트·API 업무 로직·launchd/systemd 운영 같은 제외 대상과 무관한 작업 |
| `quality` (`q-*`) | 4 | 과제별 LLM 채점 기준 4개 (`graders/`). 스킬 문서를 읽지 않은 에이전트가 공식 문서 기준으로 "운영에 올리면 유실·중복·장애가 나는 실수" 를 골라 썼다 — 스킬에서 기준을 뽑으면 스킬 쪽에 유리한 순환 측정이 된다 |

## 한계

- 모델 출력이 확률적이라 `runs: 1` 결과는 흔들릴 수 있다. description 을 고친 뒤에는 `--runs 3` 으로 다시 본다.
- 스킬을 켠 쪽은 references 를 읽고 답이 길어져 300s 기본 시간 제한에 걸릴 수 있다 (시간 초과 run 은 0점).
- LLM 채점이 틀릴 수 있다. 실패 항목은 답변 원문 (`results/*/aggregate-result.json` 의 `evidence`) 을 읽고 확인한다 — 2026-10 측정에서 종료·drain 기준이 요건을 다 갖춘 답을 FAIL 로 판정한 사례가 있었다.
- 빈 작업 디렉토리에서 돈다. 실제 프로젝트 코드가 있으면 발동률이 달라질 수 있다.
