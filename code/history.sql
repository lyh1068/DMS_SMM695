-- SQLite
-- sqlite3 etilqs/History.db < history.sql
SELECT * 
FROM history_items 
WHERE URL LIKE '%citystgeorges%' 
ORDER BY id DESC 
LIMIT 10;

SELECT * 
FROM history_items
WHERE URL LIKE '%bayes%' 
ORDER BY id DESC 
LIMIT 10;