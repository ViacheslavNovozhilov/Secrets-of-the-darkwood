/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Вячеслав Новожилов
 * Дата: 20.03.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Я разбивал запросы, согласно заданию, ты попросил меня свести выводы в одну таблицу, я это сделал.
 
WITH 
	total_users AS (SELECT count(id) AS total_users_cnt FROM fantasy.users),
	total_paing_users AS (SELECT count(id) AS total_paing_users_cnt FROM fantasy.users WHERE payer=1),
	total_users_per_race AS (SELECT race, count(id) cnt_users_per_race 
							FROM fantasy.users 
							LEFT JOIN fantasy.race USING(race_id) GROUP BY race ORDER BY cnt_users_per_race desc),
	paing_users_per_pace AS (SELECT race, 
							count(id) AS paing_cnt_users_per_race 
							FROM fantasy.race LEFT JOIN fantasy.users using(race_id) WHERE payer=1 GROUP BY race ORDER BY paing_cnt_users_per_race desc)
SELECT race.race, cnt_users_per_race, paing_cnt_users_per_race, total_users_cnt, total_paing_users_cnt,
		round(total_paing_users_cnt::NUMERIC/total_users_cnt, 2) AS part_payer_users,
		round(paing_cnt_users_per_race::NUMERIC/cnt_users_per_race, 2) AS part_paing_users_per_race
		FROM fantasy.race 
		LEFT JOIN total_users_per_race USING(race)
		LEFT JOIN paing_users_per_pace USING(race),
		total_users , total_paing_users 
GROUP BY race.race, cnt_users_per_race, paing_cnt_users_per_race, total_users_cnt, total_paing_users_cnt
ORDER BY part_paing_users_per_race desc; 

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT 
	count(DISTINCT transaction_id) AS trans_cnt, 
	sum(amount) AS sum_amount,
	min(amount) AS min_amount,
	max(amount) AS max_amount,
	round(avg(amount)::NUMERIC, 4) AS avg_amount,
	round(stddev(amount)::NUMERIC, 4) AS stand_dev,
	round((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount))::NUMERIC, 4) AS median_amount
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
WITH
	transactions AS (SELECT count(transaction_id) AS total_transactions FROM fantasy.events),
	events_amount_with_zero AS (SELECT transaction_id FROM fantasy.events WHERE amount = 0 ORDER BY transaction_id),
	trans_with_zero AS (SELECT COUNT(transaction_id) AS total_transactions_with_zero FROM fantasy.events WHERE amount=0)
SELECT 'количество нулевых транзакций' AS field, total_transactions_with_zero FROM trans_with_zero
UNION all
SELECT 'доля таких транзакций от общего числа транзакций' AS field,
total_transactions_with_zero::float/total_transactions AS part_trans_with_zero FROM trans_with_zero, transactions;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
---Учитываем, что необходимо исключить игроков, которые также заплатили 0 "лепестков"
WITH
	total_users AS (SELECT count(id) AS total_users_cnt FROM fantasy.users),
    paying_users AS (SELECT COUNT(id) AS paying_users_cnt FROM fantasy.users LEFT JOIN fantasy.events USING(id) 
        			WHERE payer=1 AND amount!=0),
    not_paying_users AS (SELECT COUNT(id) AS not_paying_users_cnt FROM fantasy.users WHERE payer=0),
    transactions AS (SELECT users.payer,
            		COUNT(transaction_id) AS total_transactions,
            		SUM(amount) AS total_amount
        			FROM fantasy.users LEFT JOIN fantasy.events USING(id) WHERE amount!=0 GROUP BY payer)
SELECT 
    CASE WHEN users.payer = 1 THEN 'payers' ELSE 'non-payers' END AS user_type,
    COUNT(users.id) AS user_count,
    ROUND(CASE WHEN COUNT(users.id)>0 THEN total_transactions::NUMERIC / COUNT(users.id) END, 0) AS avg_transactions_per_user,
    ROUND(CASE WHEN COUNT(users.id)>0 THEN total_amount / COUNT(users.id) END::NUMERIC, 2) AS avg_sum_amount_per_user,
	ROUND(count(users.id)::NUMERIC / total_users_cnt, 2) AS part_of_paying_users
FROM fantasy.users LEFT JOIN transactions using(payer)
CROSS JOIN paying_users CROSS JOIN total_users
GROUP BY 
    users.payer, total_transactions, total_amount, paying_users_cnt, total_users_cnt 
ORDER BY users.payer;


-- 2.4: Популярные эпические предметы:

WITH
    gamers_cnt AS (SELECT COUNT(DISTINCT users.id) AS all_gamers_cnt FROM fantasy.users 
        			JOIN fantasy.events USING(id) WHERE amount != 0),
    gamers_cnt_over_once AS (SELECT game_items, 
            				COUNT(DISTINCT users.id) AS gamers_cnt_per_item_once FROM fantasy.users 
            				JOIN fantasy.events USING(id)
        					JOIN fantasy.items USING(item_code) WHERE amount != 0 GROUP BY game_items 
        					HAVING COUNT(DISTINCT transaction_id) >= 1),
    items_cnt AS (SELECT item_code, 
            		game_items, 
            		COUNT(transaction_id) AS trans_cnt_per_item
        			FROM fantasy.items JOIN fantasy.events USING(item_code) WHERE amount != 0 GROUP BY item_code, game_items 
        			ORDER BY trans_cnt_per_item DESC),
    trans_cnt AS (SELECT COUNT(transaction_id) AS all_trans_count FROM fantasy.events WHERE amount != 0)
SELECT 
    items_cnt.item_code, 
    gamers_cnt_over_once.game_items, 
    items_cnt.trans_cnt_per_item,  
    ROUND(items_cnt.trans_cnt_per_item::NUMERIC / (SELECT all_trans_count FROM trans_cnt), 4) AS part_item_sold,
    ROUND((items_cnt.trans_cnt_per_item::NUMERIC / (SELECT all_trans_count FROM trans_cnt)) * 100, 0) AS part_item_sold_in_procent,
    COALESCE(ROUND(gamers_cnt_over_once.gamers_cnt_per_item_once::NUMERIC / gamers_cnt.all_gamers_cnt, 5), 0) AS part_players,
    COALESCE(ROUND((gamers_cnt_over_once.gamers_cnt_per_item_once::NUMERIC / gamers_cnt.all_gamers_cnt) * 100, 0), 0) AS part_players_in_procent
FROM items_cnt JOIN gamers_cnt_over_once using(game_items)
CROSS JOIN gamers_cnt
ORDER BY items_cnt.trans_cnt_per_item DESC, part_item_sold DESC, gamers_cnt_over_once.gamers_cnt_per_item_once DESC, part_players DESC;


-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:

--Из задания -
/*общее количество зарегистрированных игроков - total_registered_players_per_race;
-количество игроков, которые совершают внутриигровые покупки - players_with_purchases
-доля игроков, которые совершают внутриигровые покупки от общего количества игроков - part_players_with_purchases;
-доля платящих игроков от количества игроков, которые совершили покупки - part_paid_players_per_race;
-среднее количество покупок на одного игрока - avg_purchases_per_player;
-средняя стоимость одной покупки на одного игрока - avg_purchase_value_per_player;
-средняя суммарная стоимость всех покупок на одного игрока - avg_total_spent_per_paid_player.*/

WITH
    cnt_users AS (SELECT 
            		race, 
            		COUNT(DISTINCT id) AS users_cnt_per_race 
       				FROM fantasy.users JOIN fantasy.race USING(race_id) GROUP BY race),
    users_cnt_paid AS (SELECT 
            			race, 
            			COUNT(DISTINCT id) AS paid_users_cnt_per_race 
        				FROM fantasy.users 
        				JOIN fantasy.race USING(race_id) 
        				JOIN fantasy.events USING(id) WHERE amount != 0 AND payer = 1 
        				GROUP BY race HAVING COUNT(DISTINCT transaction_id) != 0),
    trans_cnt AS (SELECT 
            		race, 
            		COUNT(DISTINCT transaction_id) AS trans_cnt_per_race FROM fantasy.race 
        			JOIN fantasy.users USING(race_id) JOIN fantasy.events USING(id) WHERE amount != 0 GROUP BY race),
    total_amount AS (SELECT 
            			race, 
            			SUM(amount) AS total_amount_per_race,
            			COUNT(DISTINCT id) AS total_users_per_race 
        				FROM fantasy.users JOIN fantasy.race USING(race_id) JOIN fantasy.events USING(id) 
        				WHERE amount != 0 GROUP BY race),
    avg_purchase AS (SELECT race,
            			AVG(fantasy.events.amount) AS avg_purchase_value_per_transaction
        				FROM fantasy.events 
        				JOIN fantasy.users USING(id)
        				JOIN fantasy.race USING(race_id)
        				WHERE amount != 0 
        				GROUP BY race),
    users_with_purchases AS (SELECT 
            					race, 
            					COUNT(DISTINCT id) AS players_with_purchases 
        						FROM fantasy.users JOIN fantasy.race USING(race_id) 
        						JOIN fantasy.events USING(id) WHERE amount != 0 
        						GROUP BY race)
SELECT 
    cnt_users.race,
    cnt_users.users_cnt_per_race AS total_registered_players_per_race,
    COALESCE(users_with_purchases.players_with_purchases, 0) AS players_with_purchases,
    COALESCE(users_cnt_paid.paid_users_cnt_per_race, 0) AS total_paid_players_per_race,
    ROUND(CASE WHEN cnt_users.users_cnt_per_race > 0 THEN COALESCE(users_with_purchases.players_with_purchases, 0)::numeric / cnt_users.users_cnt_per_race END, 4) AS part_players_with_purchases,
    ROUND(CASE WHEN users_with_purchases.players_with_purchases > 0 THEN COALESCE(users_cnt_paid.paid_users_cnt_per_race, 0)::numeric / users_with_purchases.players_with_purchases END, 4) AS part_paid_players_per_race,
    ROUND(CASE WHEN trans_cnt.trans_cnt_per_race > 0 THEN COALESCE(trans_cnt.trans_cnt_per_race, 0)::numeric / users_with_purchases.players_with_purchases END, 4) AS avg_purchases_per_player,
    ROUND(CASE WHEN cnt_users.users_cnt_per_race > 0 THEN COALESCE(total_amount.total_amount_per_race, 0)::numeric / cnt_users.users_cnt_per_race END, 4) AS avg_purchase_value_per_player,
    ROUND(CASE WHEN users_cnt_paid.paid_users_cnt_per_race > 0 THEN COALESCE(total_amount.total_amount_per_race, 0)::numeric / users_cnt_paid.paid_users_cnt_per_race END, 4) AS avg_total_spent_per_paid_player,
    ROUND(COALESCE(avg_purchase.avg_purchase_value_per_transaction, 0)::numeric, 4) AS avg_purchase_value_per_transaction
FROM cnt_users 
LEFT JOIN users_cnt_paid using(race)
LEFT JOIN users_with_purchases USING(race)
LEFT JOIN trans_cnt using(race)
LEFT JOIN total_amount using(race)
LEFT JOIN avg_purchase using(race)
ORDER BY total_registered_players_per_race DESC, players_with_purchases DESC, total_paid_players_per_race DESC;

-- Задача 2: Частота покупок
WITH 
	purchases AS (SELECT users.id,
        			amount,
        			date,
        			LAG(date::timestamp) OVER (PARTITION BY id ORDER BY date) AS previous_purchase_date
    			FROM fantasy.users JOIN fantasy.events using(id) WHERE amount!=0),
	days_between AS (SELECT id, 
        		COUNT(*) AS total_purchases,
        		AVG(purchases.date::timestamp - purchases.previous_purchase_date) AS avg_days_between FROM purchases GROUP BY id),
	user_status AS (SELECT users.id,
        		CASE 
            		WHEN payer=1 THEN 1 
            	ELSE 0 
        		END AS is_paid
    			FROM fantasy.users LEFT JOIN fantasy.events using(id) WHERE amount!=0 GROUP BY users.id),
	active_users AS (SELECT days_between.id,
        			days_between.total_purchases,
        			days_between.avg_days_between,
        			user_status.is_paid
    			FROM days_between JOIN user_status using(id) WHERE days_between.total_purchases>=25),
	division_by_groups AS (SELECT active_users.id,
        				active_users.total_purchases,
        				active_users.avg_days_between,
        				active_users.is_paid,
        				NTILE(3) OVER (ORDER BY active_users.avg_days_between DESC) AS purchase_frequency_group FROM active_users)
SELECT
	case
    	WHEN purchase_frequency_group=1 THEN 'высокая частота'
    	WHEN purchase_frequency_group=2 THEN 'умеренная частота'
    	WHEN purchase_frequency_group=3 THEN 'низкая частота'
   	END AS purchase_frequency_group_phrase,
    COUNT(division_by_groups.id) AS number_of_players,
    SUM(division_by_groups.is_paid) AS number_of_paid_players,
    round(SUM(division_by_groups.is_paid)::numeric/COUNT(division_by_groups.id), 4) AS paid_players_ratio,
    round(AVG(division_by_groups.total_purchases), 4) AS avg_purchases_per_player,
    EXTRACT('day' FROM AVG(division_by_groups.avg_days_between)) AS avg_days_between_purchases_per_player
FROM division_by_groups GROUP BY division_by_groups.purchase_frequency_group
ORDER BY avg_days_between_purchases_per_player desc;



