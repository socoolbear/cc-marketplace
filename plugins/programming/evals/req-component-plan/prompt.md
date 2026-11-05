---
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
---

수백 대 호스트의 로그를 읽어 이상을 찾는 에이전트와, 그 데이터를 받아 저장하는 수집 서버를 새로 만들려고 해. 에이전트는 systemd 로, 수집 서버는 Kubernetes 로 운영해. 구현 전에 무엇을 어떻게 만들지 정리해줘.
