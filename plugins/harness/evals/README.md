# harness evals

`claude plugin eval` 스위트. 케이스 4개. 결과는 참고용이고 릴리스 게이트가 아니다.

## 실행

repo 루트에서:

```
claude plugin eval plugins/harness --trust-plugin --scaffold --allow-tools Write Edit Bash
```

- `--scaffold`: 각 케이스의 `scaffold.sh` (빈 작업 디렉토리 cwd 에 fixture 생성) 를 실행한다. 없으면 fixture 가 만들어지지 않는다.
- `--allow-tools Write Edit Bash`: 없으면 파일을 만드는 케이스가 통과할 수 없다.
- 비용 절감: `--runs 1 --ablation none --case <이름>`. 결과는 `evals/results/` 에 쌓이며 gitignore 된다.
- 기본값은 no-plugin 비교 실행(ablation)을 함께 돈다. `arm: both` 를 준 채점기만 두 실행 모두 점수에 들어간다.

## 케이스

| 케이스 | 확인하는 것 |
|---|---|
| `setup-fresh` | 문서 없는 프로젝트에서 setup 이 산출물 7종을 만들고 AGENTS.md 가 40줄 이하·실재 명령만 적는지, 이미 있는 관례 문서 (`CONTRIBUTING.md`) 를 `harness/CONVENTIONS.md` 로 베끼지 않고 포인터로 가리키는지 |
| `setup-greenfield` | 코드 없는 신규 프로젝트에서 요청에 담긴 스택·레이어를 ARCHITECTURE·ADR (`Accepted`) 에 넣고, `package.json`·`src/`·강제 훅을 만들지 않고, 없는 검증 명령을 적지 않는지, 요청에 담긴 코딩 관례로 `harness/CONVENTIONS.md` 를 만들고 AGENTS.md 가 가리키는지 |
| `maintain-report-only` | 점검만 요청하면 Edit·Write 없이 깨진 포인터 `harness/RUNBOOK.md`, AGENTS.md 에 없는 `lint` 스크립트 (⑦), 마커 4.0.0 이후 변경 이력을 보고하는지 |
| `signal-suggest` | 마커 3.0.0 프로젝트에서 무관한 작업 후 `/harness` 를 제안하되 스킬을 스스로 실행하지 않는지 |

## 한계

- `signal-suggest` 는 플러그인 `SessionStart` 훅이 eval 실행 안에서도 발동한다는 가정에 의존한다 (미검증). 훅이 안 돌면 `/harness` regex 가 실패하므로 참고용으로만 본다.
- 모델 출력이 확률적이라 같은 케이스도 결과가 흔들릴 수 있다.
