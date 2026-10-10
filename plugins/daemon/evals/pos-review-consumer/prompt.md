---
max_turns: 4
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
---

이 컨슈머 코드 리뷰해줘.

```ts
const consumer = kafka.consumer({ groupId: 'billing' });
await consumer.run({
  autoCommit: true,
  eachMessage: async ({ message }) => {
    try {
      await db.insert(JSON.parse(message.value.toString()));
    } catch (e) {
      logger.error(e);
    }
  },
});
```
