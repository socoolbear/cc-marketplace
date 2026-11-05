# I/O — Plugin Interface

서버 본체를 고치지 않고 파서·처리·프로토콜 어댑터·출력을 끼워 넣는 확장점이다. Processing 의 확장점이며 Source·Sink 구현에도 같은 규칙을 쓴다.

## 1. 둘지 판단

구현체가 둘 이상이거나 다른 팀·외부가 확장해야 할 때만 둔다. 그 밖에는 함수 하나로 충분하다. 플러그인 인터페이스는 한 번 공개하면 호환 의무가 생긴다.

## 2. 등록 방식

| 방식 | 사례 | 장점 | 비용 | 고르는 때 |
|---|---|---|---|---|
| 컴파일 시 등록 (**기본**) | Telegraf `init()` + blank import ([INPUTS](https://raw.githubusercontent.com/influxdata/telegraf/master/docs/INPUTS.md)), Caddy `RegisterModule` + `xcaddy`, OTel `ocb` ([ocb](https://opentelemetry.io/docs/collector/extend/ocb/)) | 단일 바이너리, 빌드 때 호환 검사 | 추가할 때마다 재빌드, 프로세스 경계가 없어 panic 이 번진다 | 플러그인을 우리가 관리한다 |
| 같은 프로세스 동적 로드 | Java `ServiceLoader` ([문서](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/ServiceLoader.html)), Python entry points ([규격](https://packaging.python.org/en/latest/specifications/entry-points/)), pluggy | 재빌드 없이 추가, 호출이 싸다 | 격리 없음, 의존성 충돌 | 언어 표준 수단이 있고 플러그인을 믿는다 |
| 별도 프로세스·샌드박스 | HashiCorp go-plugin ([README](https://raw.githubusercontent.com/hashicorp/go-plugin/main/README.md)), Telegraf `execd` ([README](https://raw.githubusercontent.com/influxdata/telegraf/master/plugins/inputs/execd/README.md)), proxy-wasm ([설계](https://raw.githubusercontent.com/proxy-wasm/spec/main/docs/WebAssembly-in-Envoy.md)) | crash 격리, 언어 자유 | IPC·복사·메모리, 재시작 관리 | 제3자 코드, 신뢰할 수 없거나 crash 가 잦다 |

Go 표준 `plugin` 은 쓰지 않는다. Linux·FreeBSD·macOS 만 되고, 툴체인·build tag·공통 의존성이 정확히 같아야 하며, 닫을 수 없다. 문서도 정적 빌드나 IPC 를 대안으로 든다 ([plugin](https://pkg.go.dev/plugin)). 동적 확장은 유지 비용이 커서 없앤 사례도 있다 (Vector WASM 제거, [글](https://vector.dev/highlights/2021-08-23-removing-wasm/)).

## 3. 플러그인 계약

```
interface Plugin:
  name(), apiVersion()
  validate(section)                 # 부수 효과 없음
  start(ctx), stop(deadline)        # components.md §2. stop 은 start 실패 뒤에도 안전
  prepare(section), commit(), abort() # 재적재를 지원할 때만 (components.md §2)
  process(item, ctx) -> items | Err # 호출당 기한은 호스트가 정한다
  canaryWrite(failedTarget) -> ok | failed | unsupported # Sink 플러그인만. 실패한 쓰기와 같은 샤드·테넌트로. SinkDown 판정에 쓴다
```

- **오류는 분류해서 돌려준다**: Retryable / Poison / Fatal, 그리고 취소로 끝났으면 취소 오류. Retryable 이 SinkDown 인지는 호스트가 판정하고 재시도·DLQ·종료도 호스트가 결정한다 (Failure Handling). 플러그인이 스스로 DLQ 로 보내거나 오류를 삼키면 조용한 유실이다
- **확인 응답은 호스트 소유다.** 플러그인은 commit·ack 를 부르지 않는다. 호스트가 Contract 2 순서를 지킨다
- **상태는 작게.** 플러그인 안 버퍼에도 상한이 있고, 잃으면 안 되는 상태는 호스트가 주는 저장소에 둔다
- **결정성.** 멱등 키 계산이나 출력에 시계·난수를 넣지 않는다 (Contract 3)
- **블로킹 금지.** 이벤트 루프 호스트면 플러그인 호출도 루프 밖이다 (`io.md` §7)
- **로그·지표는 호스트가 준 핸들로.** `plugin=<name>` 라벨이 자동으로 붙게 하고, 플러그인별 처리량·오류·지연을 낸다
- 공유 자원은 호스트가 주입한다. 재적재 때 새 인스턴스와 옛 인스턴스가 겹칠 수 있다 (Caddy 는 새 것을 먼저 시작한다, [extending](https://raw.githubusercontent.com/caddyserver/website/master/src/docs/markdown/extending-caddy.md)) → 포트·파일을 플러그인이 직접 쥐지 않는다

## 4. 실패 격리

| 사건 | 같은 프로세스 | 별도 프로세스 |
|---|---|---|
| 예외·오류 | 호스트 경계에서 잡아 분류. 분류가 없으면 Poison 으로 보지 말고 Fatal | 같음 |
| panic·segfault | 언어 복구가 가능하면 기록하고 끝낸다. 메모리 상태를 믿을 수 없으면 프로세스 종료 (Telegraf 는 input panic 을 기록 후 종료, [agent.go](https://raw.githubusercontent.com/influxdata/telegraf/master/agent/agent.go)) | 호스트는 산다. 지연 재시작 + 횟수 상한 (`execd` `restart_delay`·`stop_on_error`. go-plugin 은 자동 재시작이 없다) |
| 시간 초과 | 호출 기한. 취소를 무시하면 같은 프로세스에서는 끊을 수 없다 → 신뢰 못 하면 별도 프로세스 | 프로세스 종료 |
| 시작 실패 | 필수 플러그인이면 시작 중단. 선택이면 정책 (Telegraf `startup_error_behavior`: error·retry·ignore·probe) + 지표. Sink 플러그인은 `ignore` 불가 | 같음 |

플러그인이 실패 상태일 때 어떻게 할지 플러그인마다 정한다: 멈춤 (fail-closed, 기본) / 건너뜀 (fail-open: 변환 플러그인만 해당한다. 그 처리만 생략하고 항목은 다음 단계로 간다. 항목 자체가 문제면 Poison 으로 DLQ. Sink·출력 플러그인을 건너뛰면 쓰기 없이 확인 응답이 나가 유실이므로 금지) / 다시 띄움 (Envoy `FAIL_CLOSED`·`FAIL_OPEN`·`FAIL_RELOAD`, [proto](https://raw.githubusercontent.com/envoyproxy/envoy/main/api/envoy/extensions/wasm/v3/wasm.proto)). 인증·과금·검증 플러그인은 건너뛰지 않는다 ([Istio](https://istio.io/latest/docs/reference/config/proxy_extensions/wasm-plugin/)).

## 5. 버전 호환

- 인터페이스에 API 버전을 둔다. 컴파일 시 등록이면 빌드가 검사한다 (`ocb` 는 core·컴포넌트 버전을 맞춘다). 별도 프로세스는 시작 때 협상하고 맞지 않으면 시작을 거절한다 (go-plugin handshake·`VersionedPlugins`, [internals](https://raw.githubusercontent.com/hashicorp/go-plugin/main/docs/internals.md))
- 안정성 수준을 표시하고 폐기 기간을 약속한다 (OTel Development~Stable, [stability](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/main/docs/component-stability.md))
- 인자 추가가 기존 구현을 깨지 않게 만든다 (pluggy 는 구현이 일부 인자만 받아도 된다. Go 면 옵션 구조체)

## 6. 시험

플러그인 공통 적합성 시험을 호스트가 제공한다: 수명 순서, `stop` 재호출, 오류 분류, 기한 초과, 재적재 겹침. 모든 플러그인이 같은 시험을 통과해야 한다. 실패 주입은 `verification.md`.
