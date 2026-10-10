# daemon evals

`claude plugin eval` 스위트. `daemon-programming` 스킬의 발동 (trigger) 만 본다. 구현 품질은 보지 않는다. 결과는 참고용이고 릴리스 게이트가 아니다.

## 실행

repo 루트에서:

```
claude plugin eval plugins/daemon --trust-plugin --ablation none -j 4
```

- 케이스마다 `max_turns: 4` 이고 쓰기 도구가 없다. 첫 응답에서 스킬을 부르는지만 본다.
- 태그로 나눠 돌릴 수 있다: `--tag should-fire`, `--tag should-not-fire`.
- 결과는 `evals/results/` 에 쌓이며 gitignore 된다.

## 케이스

| 태그 | 수 | 통과 기준 |
|---|---|---|
| `should-fire` (`pos-*`) | 10 | Skill 도구로 `daemon-programming` 을 1회 이상 부른다. 요청 문장에 description 의 트리거 문구를 그대로 쓰지 않았다 |
| `should-not-fire` (`neg-*`) | 8 | 부르지 않는다. 일회성 스크립트·API 업무 로직·launchd/systemd 운영 같은 제외 대상과 무관한 작업 |

## 한계

- 모델 출력이 확률적이라 `runs: 1` 결과는 흔들릴 수 있다. description 을 고친 뒤에는 `--runs 3` 으로 다시 본다.
- 빈 작업 디렉토리에서 돈다. 실제 프로젝트 코드가 있으면 발동률이 달라질 수 있다.
