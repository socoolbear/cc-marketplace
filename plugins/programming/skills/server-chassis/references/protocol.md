# I/O — Protocol Handler

바이트와 내부 메시지 사이를 맡는 컴포넌트다. 일반 HTTP 프레임워크 위에서는 프레임워크가 대신한다. XMPP·SNMP·WebSocket·MQTT·자체 TCP 처럼 프로토콜을 직접 다루는 서버에서 필요하다. 표준 프로토콜이면 파서·상태 기계를 새로 짜기 전에 검증된 라이브러리를 먼저 본다.

## 1. 통신 형태를 먼저 고른다

형태가 확인 응답·재전송·연결 수명을 정한다. 프로토콜 하나가 여러 형태를 섞기도 한다 (SNMP 는 요청-응답 + Trap).

| 형태 | 예 | 전달 확인 | 서버가 정할 것 |
|---|---|---|---|
| 요청-응답 | HTTP, SNMP Get | 응답이 곧 확인. 재전송은 요청 쪽 응용 재량 ([RFC 3416](https://www.rfc-editor.org/rfc/rfc3416.txt) §2.2) | 요청 시간 상한, 멱등 |
| 단방향 무확인 | SNMP Trap, UDP syslog, MQTT QoS 0 | 없음. 유실을 알 수 없다 | 유실 허용 근거, 수신 버퍼 드롭 지표, 송신자 식별 |
| 단방향 확인 | SNMP Inform, MQTT QoS 1 | 받았다는 확인. Inform 도 전달을 보장하지는 않는다 (RFC 3416 §4.2.7) | 중복 흡수, 확인 시점 (Contract 2) |
| 서버 → 클라이언트 스트림 | SSE | 재연결 때 `Last-Event-ID` ([HTML](https://html.spec.whatwg.org/multipage/server-sent-events.html)) | 재개 위치 보관 기간, 느린 수신자 |
| 장기 양방향 | XMPP, WebSocket, MQTT, gRPC 양방향 스트림 | 프로토콜마다 다름. XMPP 코어는 끊김을 늦게 알아 stanza 를 잃을 수 있고 XEP-0198 이 ack·재개로 메운다. 재개 때 중복은 막지 못한다 ([RFC 6120](https://www.rfc-editor.org/rfc/rfc6120.txt) §3.4, [XEP-0198](https://xmpp.org/extensions/xep-0198.html)) | 세션, heartbeat, 연결별 송신 큐, 라우팅, drain |

단방향 무확인은 Contract 1 의 예외다. at-most-once 를 고른 이유를 설계 메모에 적는다. 장기 양방향은 양쪽이 모두 보낼 수 있으므로 서버가 보내는 쪽 구간에도 Contract 를 건다.

## 2. 코덱·프레이밍

- TCP 의 read 경계는 메시지 경계가 아니다 ([RFC 9293](https://www.rfc-editor.org/rfc/rfc9293.txt), [recv(2)](https://man7.org/linux/man-pages/man2/recv.2.html)). 디코더는 누적 버퍼에서 완전한 프레임이 있을 때만 메시지를 낸다 ([Netty ByteToMessageDecoder](https://github.com/netty/netty/blob/4.1/codec/src/main/java/io/netty/handler/codec/ByteToMessageDecoder.java), 덜 왔으면 `Ok(None)` 을 내는 [tokio Decoder](https://github.com/tokio-rs/tokio/blob/master/tokio-util/src/codec/decoder.rs))
- 프레임 길이는 받기 전에 검사한다 (`maxFrameLength` + `failFast`, [LengthFieldBasedFrameDecoder](https://github.com/netty/netty/blob/4.1/codec/src/main/java/io/netty/handler/codec/LengthFieldBasedFrameDecoder.java)). 줄 단위 파서에도 상한이 있다 (Go `bufio.Scanner` 기본 64KiB, 넘으면 `ErrTooLong`)
- 층을 나눈다: 프레이밍 (바이트 → 프레임) → 코덱 (프레임 → 프로토콜 메시지) → 어댑터 (프로토콜 메시지 → 내부 메시지). 업무 로직은 내부 메시지만 본다. 이 층은 순수 함수에 가깝게 두면 fuzzing 과 단위 시험이 쉽다
- 프로토콜 오류는 연결 단위 Poison 이다. 복구할 수 없는 프레임 오류면 오류 응답 후 그 연결만 닫고, 프로세스나 다른 연결로 번지지 않게 한다

## 3. 연결 수명

- 연결마다 상태 기계를 둔다 (`connected → negotiating → authenticated → active → closing`). 상태마다 시간 상한을 둔다. 인증 전 연결은 특히 짧게 둔다
- **TCP keepalive 로 부족하다.** 구현은 선택이고 기본 꺼짐, 간격은 2시간 이상이다 ([RFC 1122](https://www.rfc-editor.org/rfc/rfc1122.txt) §4.2.3.6, [tcp(7)](https://man7.org/linux/man-pages/man7/tcp.7.html)). 커널이 ACK 해도 상대 응용이 살아 있다는 뜻은 아니다 (RFC 6120 §4.6 은 dead connection·broken stream·idle peer 를 나눈다). 응용 heartbeat 를 쓴다: WebSocket ping/pong ([RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.txt) §5.5.2), [XEP-0199](https://xmpp.org/extensions/xep-0199.html), MQTT Keep Alive (1.5배 안에 수신이 없으면 끊는다, [MQTT 5](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html))
- 반열림 연결은 보내 봐야 드러난다. 조용한 연결은 heartbeat 로 찾고, 보낸 데이터가 머무는 상한은 `TCP_USER_TIMEOUT` 으로 둔다
- half-close: 두 방향은 따로 닫힌다 ([shutdown(2)](https://man7.org/linux/man-pages/man2/shutdown.2.html)). 상대가 쓰기를 닫아도 남은 응답을 보낼 수 있다
- 자원: fd 를 다 쓰면 accept 가 `EMFILE` 을 낸다 ([accept(2)](https://man7.org/linux/man-pages/man2/accept.2.html)). accept 루프는 백오프로 돌고 (Go `http.Server` 5ms → 1s), 연결 수·IP 별 연결 수·시도 횟수에 상한을 둔다 (RFC 6120 §13.12). `listen` backlog 는 `somaxconn` 으로 조용히 잘린다 ([listen(2)](https://man7.org/linux/man-pages/man2/listen.2.html))

## 4. 연결별 송신 큐와 느린 수신자

서버가 먼저 보내는 프로토콜의 대표 사고는 **수신자 하나가 느려 메모리가 차거나 전체 전달이 막히는 것** 이다.

- 연결마다 상한 있는 송신 큐를 두고 전달 경로는 블록하지 않는다. 쓰기는 연결별 실행 단위가 쓰기 기한을 걸고 한다
- 큐가 찼을 때 정책을 정한다

| 정책 | 사례 | 쓰는 때 |
|---|---|---|
| 연결 끊기 | NATS (쓰기 기한 초과 또는 대기 64MiB, [slow consumers](https://docs.nats.io/running-a-nats-service/nats_admin/slow_consumers)), ejabberd `max_fsm_queue` 10000, gorilla chat 예제 (send 채널이 차면 제거) | 재접속·재개가 있을 때의 기본값 |
| 메시지 버림 | Mosquitto `max_queued_bytes` (조용히 버린다, [conf](https://mosquitto.org/man/mosquitto-conf-5.html)) | 최신 값만 의미 있을 때. 버린 수를 지표로 낸다 |
| 흐름 제어 | HTTP/2 `WINDOW_UPDATE` ([RFC 9113](https://www.rfc-editor.org/rfc/rfc9113.txt) §5.2.1), MQTT Receive Maximum | 프로토콜이 지원할 때 |

### 수신 쪽 과부하

HTTP 의 503 + `Retry-After` 에 해당하는 수단을 프로토콜마다 정한다.

| 수단 | 예 | 주의 |
|---|---|---|
| 연결별 읽기 중단 | 내부 큐가 차면 그 소켓 read 를 멈춘다. TCP 흐름 제어가 송신자를 늦춘다 | heartbeat 도 함께 멈춘다 → 멈출 시간에 상한을 둔다 |
| 프로토콜 거절 | XMPP `resource-constraint`, MQTT CONNACK `0x89` Server busy·`0x9F` Connection rate exceeded (RFC 6120, MQTT 5) | 재시도 신호가 없으면 클라이언트 지터에 기댄다 |
| 새 연결 거절 | 연결 상한·인증 처리량 상한 | 기존 연결을 지키는 쪽을 우선한다 |
| UDP 드롭 | 소켓 버퍼·내부 큐가 차면 버린다. 되돌릴 수단이 없다 | 수신 스레드는 큐에 넣기만 하고, 버린 수를 지표로 낸다 |

Sink 장애 (degraded) 때도 같은 수단을 쓴다. 확인 응답을 주는 프로토콜이면 저장 확정 전에는 응답하지 않는다.

### 내보내는 쪽 도구

- Netty `WriteBufferWaterMark` 는 기본 32/64KiB 에서 `isWritable()` 신호만 준다. 끊을지 말지는 앱이 정한다
- 지표: 연결별 큐 깊이 분포, 느린 수신자로 끊은 수, 버린 메시지 수. Resource Limits 는 `연결 수 × 큐 상한` 으로 잡는다

## 5. 파서 보안

파서는 인증 전 입력을 먼저 만나는 코드다.

- 인증 전에는 크기·시간·연결 수를 더 작게 둔다. 기본값이 무제한인 서버가 있다 (ejabberd `max_stanza_size` 기본 infinity, 권장 c2s 65536, [listen options](https://docs.ejabberd.im/admin/configuration/listen-options/))
- XML 은 DTD·외부 엔티티를 끈다. XMPP 는 규격이 금지한다 (RFC 6120 §11.1, `<restricted-xml/>`)
- SNMP v1·v2c community 는 사실상 인증이 아니다 ([RFC 3410](https://www.rfc-editor.org/rfc/rfc3410.txt)). 민감한 경로는 v3 USM 을 쓴다 ([RFC 3414](https://www.rfc-editor.org/rfc/rfc3414.txt), DoS 는 범위 밖)
- UDP 응답은 증폭 공격에 쓰인다 (SNMPv2 약 6.3배, [CISA](https://www.cisa.gov/news-events/alerts/2014/01/17/udp-based-amplification-attacks)). 인터넷에 열지 않고, 위조 주소에 큰 응답을 보내지 않게 응답 크기·속도를 제한한다
- 코덱은 fuzzing 대상이다 ([Go fuzz](https://go.dev/doc/security/fuzz/), [OSS-Fuzz](https://google.github.io/oss-fuzz/))

## 6. 다중 프로토콜

- listener 마다 프로토콜 어댑터를 붙이고 공통 코어로 모은다 (ejabberd `listen` 의 `module`, [listen](https://docs.ejabberd.im/admin/configuration/listen/), EMQX Gateway 의 통합 모델, [gateway](https://docs.emqx.com/en/emqx/latest/gateway/gateway.html)). 어댑터는 Plugin Interface 로 등록할 수 있다 (`plugin-interface.md`)
- 코어는 내부 메시지만 알고, 프로토콜별 차이 (확인 방식·세션 재개·QoS) 는 어댑터가 Contract 로 번역한다. 공통 메시지에 모든 프로토콜의 기능을 다 넣지 않는다. 가장 약한 프로토콜이 줄 수 있는 보장을 넘겨 약속하지 않는다
- 한 포트에서 첫 바이트나 ALPN 으로 나눌 수도 있지만 ([Netty port unification](https://github.com/netty/netty/blob/4.1/example/src/main/java/io/netty/example/portunification/PortUnificationServerHandler.java), [RFC 7301](https://www.rfc-editor.org/rfc/rfc7301.txt)), 포트를 나눌 수 있으면 나누는 쪽이 단순하다

## 7. 버전·기능 협상

연결 초기에 협상해 양쪽이 쓸 기능을 정한다: XMPP stream features (RFC 6120 §4.3.2), ALPN, WebSocket subprotocol (RFC 6455 §1.9). 자체 프로토콜도 첫 프레임에 버전을 싣고, 모르는 버전은 명확한 오류로 거절한다. 롤링 배포 중 구·신버전이 공존한다 (Contract 5).

## 8. 세션 라우팅과 drain

인스턴스가 여럿이면 서버가 보낼 대상이 다른 인스턴스에 붙어 있다.

- 세션 위치 표 또는 pub/sub 이 필요하다 (ejabberd Session Manager, [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html), MQTT 공유 구독). 이 표는 인스턴스가 죽으면 낡으므로 TTL 이나 인스턴스 세대로 정리한다
- **재개를 약속하면 세션 상태가 Position 이다.** 세션 재개·미전달 메시지 (XEP-0198, MQTT Clean Start=0, SSE `Last-Event-ID`) 를 약속하면 세션별 마지막 확인 번호와 미전달 메시지를 프로세스 밖 저장소에 둔다. 인스턴스가 죽어도 다른 인스턴스가 이어받아야 하기 때문이다. 메모리에만 두면 재개는 같은 인스턴스가 살아 있을 때만 된다. 재개를 약속하지 않으면 재접속 뒤 전체 동기화 경로를 둔다. 서버가 보낸 명령은 소켓 쓰기가 아니라 상대의 확인으로 완료를 판정하고, 오프라인 대상은 재전달이나 만료를 정한다
- 배포는 재접속 폭주다. 끊기 전에 프로토콜의 이동 신호를 보낸다: HTTP/2 GOAWAY (RFC 9113 §6.8), XMPP `see-other-host`, MQTT `0x9C`·`0x9D`
- 한꺼번에 끊지 말고 나눠 끊는다 (Phoenix drainer 기본 1만 연결씩 2초 간격, [Endpoint](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html)). 클라이언트는 랜덤 지연 뒤 재접속한다 (RFC 6455 §7.2.3). 연결 수 ÷ 배치 크기 × 간격이 종료 유예 시간 안에 드는지 계산한다
- 일반 Accept 종료 순서는 `io.md` §5
