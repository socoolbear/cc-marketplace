이 SQL 이 느린데 인덱스를 추천해줘.

```sql
SELECT * FROM orders WHERE user_id = ? AND created_at > ? ORDER BY created_at DESC;
```
