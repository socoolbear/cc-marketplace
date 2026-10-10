---
max_turns: 4
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
---

React 컴포넌트에서 useEffect 가 무한 루프를 도는데 고쳐줘.

```tsx
useEffect(() => { setItems([...items, x]); }, [items]);
```
