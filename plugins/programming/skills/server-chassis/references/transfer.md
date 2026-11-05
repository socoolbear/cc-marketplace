# I/O — Transfer

Output 방식 Send 를 구현하는 컴포넌트다. §1~§4 는 양쪽을 우리가 만드는 전송 (에이전트 → 수집 서버) 에 적용하고, 외부 API 호출에는 §3 의 압축, §6 의 재시도·타임아웃만 적용한다. 구간 계약은 `contract.md` §3, 디스크 버퍼는 `io.md` §3.

## 1. TCP·TLS 만으로는 전달을 모른다

`send()` 성공은 OS 버퍼에 넣었다는 뜻이다. 연결이 끊기면 어디까지 갔는지 앱은 알 수 없다 ([rsyslog](https://docs.rsyslog.com/doc/whitepapers/reliable_logging.html), [RFC 5425](https://www.rfc-editor.org/rfc/rfc5425.txt) §6.3). 그래서 **응용 계층 확인 응답** 이 필요하다.

| 프로토콜 | 확인 방식 |
|---|---|
| Fluentd Forward | `chunk` id → 같은 값의 `ack`. 기본은 at-most-once, `require_ack_response` 로 at-least-once ([규격](https://github.com/fluent/fluentd/wiki/Forward-Protocol-Specification-v1.5), [out_forward](https://docs.fluentd.org/output/forward)) |
| Lumberjack (Beats) | window 안에서 누적 ack ([PROTOCOL](https://github.com/logstash-plugins/logstash-input-beats/blob/main/PROTOCOL.md)) |
| RELP | syslog 에 응용 ack 를 더함 |
| OTLP | 응답 코드. 재전송 중복은 의도한 선택이라 명시 ([OTLP](https://opentelemetry.io/docs/specs/otlp/)) |

ack 를 쓰면 ack 유실 때 재전송이 나므로 at-least-once + 받는 쪽 멱등이다 (Contract 4).

## 2. 프로토콜 선택

- 로그·지표·trace: OTLP. 재시도·throttling·partial success 가 규격으로 정해져 있다
- 업무 데이터: gRPC 또는 HTTP 위에 같은 규칙 (재시도 코드, `Retry-After`, partial success 는 재시도 안 함) 을 옮긴다. HTTP 는 429·502·503·504 만 재시도한다
- 자체 TCP 프로토콜은 §1 표의 프로토콜로 안 될 때만. 프레이밍은 길이 접두사다 (RFC 6587 도 줄바꿈 구분은 메시지가 쪼개지고 octet counting 이 신뢰할 수 있다고 적는다, [RFC 6587](https://www.rfc-editor.org/rfc/rfc6587.txt)). 코덱 규칙은 `protocol.md` §2
- **UDP**: 유실을 감지·복구할 수 없고 혼잡 제어도 없다. 유실 허용·메시지 독립·순서 무관 데이터를 확보된 망에서 보낼 때만 ([RFC 5426](https://www.rfc-editor.org/rfc/rfc5426.txt)). 전송 속도는 앱이 제어한다 ([RFC 8085](https://www.rfc-editor.org/rfc/rfc8085.txt))
- 장애 때 TCP ↔ UDP 로 자동 전환하지 않는다. 평소 타지 않는 경로이고 전달 보장이 바뀐다 (`chassis-failure.md` §3)

## 3. 크기와 압축

- 메시지 크기 상한을 양쪽에 둔다. gRPC 수신 기본은 4MiB, 송신은 무제한이다 ([server.go](https://github.com/grpc/grpc-go/blob/master/server.go)). 1MB 를 넘으면 다른 전략을 고려한다 ([protobuf](https://protobuf.dev/programming-guides/techniques/))
- 큰 데이터는 나눠 보낸다. 조각마다 `(batchId, seq, total)` 을 싣고 받는 쪽은 다 모인 뒤 저장 확정을 응답한다. 재전송은 조각 단위, 멱등 키는 배치 단위다. 조립 중 상태에 상한과 TTL 을 둔다
- gRPC 긴 스트림은 시작 뒤 부하 분산이 안 된다 ([performance](https://grpc.io/docs/guides/performance/)). 수집이면 짧은 단위 호출이나 `MaxConnectionAge` 를 쓴다
- 압축은 배치 단위가 효과적이다. 작은 페이로드는 거의 줄지 않는다 ([configgrpc](https://github.com/open-telemetry/opentelemetry-collector/blob/main/config/configgrpc/README.md)). gzip 은 OTLP 서버 필수라 호환 기본이고, 양쪽을 통제하면 저수준 zstd 가 CPU 대비 낫다 (zstd -1 510MB/s, zlib -1 105MB/s, [zstd](https://github.com/facebook/zstd/blob/dev/README.md)). CPU 가 문제면 압축 수준을 낮춘다

## 4. 암호화·인증

- TLS 1.3 + mTLS 를 쓴다. 암호를 직접 조합하지 않는다. 키 교체·재전송 공격 방어까지 다시 만들게 된다
- 순서는 압축 → 암호화다 (암호문은 압축되지 않는다, [RFC 3173](https://www.rfc-editor.org/rfc/rfc3173.txt)). TLS 자체 압축은 쓰지 않는다 (TLS 1.3 은 없앴다). 응용 압축은 비밀과 공격자 제어 입력이 같은 압축 문맥에 있고 공격자가 길이를 볼 수 있을 때 위험하다 ([RFC 9113](https://www.rfc-editor.org/rfc/rfc9113.txt) §10.6, [BREACH](https://www.breachattack.com/)). 로그 배치면 비밀을 전송 전에 마스킹해 조건을 없앤다
- 송신자 식별은 인증서로 한다. 망 수준 허용 목록은 보조다
- 인증서는 재시작 없이 교체한다. Go 는 `GetCertificate`·`GetClientCertificate` 콜백을 쓰고 `Certificates` 를 비워 둔다 (채워 두면 SNI 없을 때 콜백이 안 불린다). CA 교체는 `GetConfigForClient`. 기존 연결은 옛 인증서로 남으므로 수명 상한을 둔다 ([crypto/tls](https://pkg.go.dev/crypto/tls)). 발급은 [cert-manager](https://cert-manager.io/docs/usage/certificate/) (90일, 2/3 지점 갱신) 또는 [SPIFFE](https://spiffe.io/docs/latest/spiffe-about/overview/)

## 5. 많은 송신자가 한 서버로 몰릴 때

장애가 풀리는 순간이 가장 위험하다. 수백 대가 쌓인 데이터를 한꺼번에 보낸다.

- 재접속·재전송은 Full Jitter 지수 백오프 ([AWS](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)). 서버의 `Retry-After` 를 따른다. 예약 작업은 호스트별 고정 지터 ([AWS](https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter))
- 동시 요청 수는 응답으로 조절한다 (Vector ARC: RTT 상승·429·503 이면 줄인다, [글](https://vector.dev/blog/adaptive-request-concurrency/))
- 재시도 기본값을 확인한다. Fluent Bit `Retry_Limit` 기본은 1 이다 ([문서](https://docs.fluentbit.io/manual/administration/scheduling-and-retries)). 한도를 넘겨 버리면 조용한 유실이다
- 서버는 부하 차단으로 싸게 거절한다 (`chassis-overload.md` §3). 복구 전송 순서는 `chassis-lifecycle.md` §7

## 6. 재시도·타임아웃

재시도 층·예산은 `chassis-overload.md` §1·§2. gRPC 는 기본 재시도 정책이 없고 keepalive 도 클라이언트 기본 꺼짐이다. 서버 허용 최소 간격 (기본 5분) 보다 짧게 ping 하면 `too_many_pings` 로 끊긴다 ([retry](https://grpc.io/docs/guides/retry/), [keepalive](https://grpc.io/docs/guides/keepalive/)).

## 7. 호스트의 본업을 방해하지 않기

에이전트는 남의 호스트에서 돈다. 자원 양보는 코드가 아니라 감독자 설정으로 한다.

- systemd: `Nice=`, `CPUWeight=` (`idle` 은 남는 CPU 만), `IOWeight=`, `MemoryHigh=` (감속·회수), `MemoryMax=` (최후 방어선) ([resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html))
- k8s: request·limit 와 QoS. 노드 압박 때 BestEffort → Burstable → Guaranteed 순으로 축출된다 ([QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/))
- `MemoryHigh` 감속으로 전송이 밀리면 버퍼가 찬다 → 버퍼 가득 정책과 함께 정한다 (`io.md` §3)
