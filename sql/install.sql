-- ap1le_mechanicjob database install
-- Run once on the server database (ESX Legacy schema must already exist).
-- Safe to run again: every statement is idempotent and keeps existing rows (grades you renamed or
-- re-priced stay as they are).
-- owned_vehicles is ESX's existing table; this script does not change it.
--
-- RESTART THE SERVER after running this file (or at least es_extended's job refresh plus
-- `restart esx_addonaccount` and then `restart esx_society`): ESX loads jobs/grades and esx_addonaccount
-- loads shared accounts only when they start. Until then hiring/promoting (unknown job grade), ordering
-- parts and the computer's deposit/withdraw (society account not found) fail.
--
-- Grade 3 is named 'boss' on purpose: esx_society only lets grades whose NAME is in its
-- Config.BossGrades (default 'boss') withdraw from the society.

-- 1) Job
INSERT IGNORE INTO `jobs` (`name`, `label`, `whitelisted`) VALUES
    ('mechanic', 'Mechanic', 1);

-- 2) Job grades (each one only if that grade does not exist yet; existing grades are never touched)
INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
SELECT 'mechanic', 0, 'recruit', 'Recruit', 500, '{}', '{}' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'mechanic' AND `grade` = 0);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
SELECT 'mechanic', 1, 'mechanic', 'Mechanic', 800, '{}', '{}' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'mechanic' AND `grade` = 1);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
SELECT 'mechanic', 2, 'experienced', 'Experienced', 1000, '{}', '{}' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'mechanic' AND `grade` = 2);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
SELECT 'mechanic', 3, 'boss', 'Boss', 1500, '{}', '{}' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'mechanic' AND `grade` = 3);

-- 3) Society account (esx_addonaccount, shared)
INSERT IGNORE INTO `addon_account` (`name`, `label`, `shared`) VALUES
    ('society_mechanic', 'Mechanic', 1);

-- 4) Society account balance row (only if missing)
INSERT INTO `addon_account_data` (`account_name`, `money`, `owner`)
SELECT 'society_mechanic', 0, NULL FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM `addon_account_data` WHERE `account_name` = 'society_mechanic'
);

-- 5) Server-only record of the performance parts this resource installed.
-- owned_vehicles.vehicle is also written by other resources from client data, so a removed part
-- is only returned to the mechanic when its level matches the level recorded here.
-- model = unsigned model hash of the vehicle the part went into, so a record never matches another car
-- that later gets the same plate (NULL for records written before v2: plate only).
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_parts` (
    `plate` VARCHAR(12) NOT NULL,
    `category` VARCHAR(20) NOT NULL,
    `level` TINYINT NOT NULL DEFAULT 0,
    `model` INT UNSIGNED NULL DEFAULT NULL,
    PRIMARY KEY (`plate`, `category`)
);

-- 5b) Upgrade from v1: add `model` if the table already existed without it
-- (works on MySQL and MariaDB, which do not share an "ADD COLUMN IF NOT EXISTS" syntax)
SET @ap1le_parts_model = (
    SELECT IF(COUNT(*) = 0,
        'ALTER TABLE `ap1le_mechanicjob_parts` ADD COLUMN `model` INT UNSIGNED NULL DEFAULT NULL',
        'SELECT 1')
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap1le_mechanicjob_parts' AND COLUMN_NAME = 'model'
);
PREPARE ap1le_stmt FROM @ap1le_parts_model;
EXECUTE ap1le_stmt;
DEALLOCATE PREPARE ap1le_stmt;

-- ---------------------------------------------------------------------------------------------
-- v2 tables. All time columns are unix seconds (INT UNSIGNED, written by the resource with os.time()),
-- so the server clock is the only clock that matters and no time zone conversion happens anywhere.
-- ---------------------------------------------------------------------------------------------

-- 6) Part orders (paid by the society). status: 'ordered' -> 'arrived' (crate at the workshop) -> 'collected'.
-- items = JSON array [{"item": "engine_lvl1", "count": 2}, ...]
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_orders` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(50) NOT NULL,
    `items` LONGTEXT NOT NULL,
    `total` INT UNSIGNED NOT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'ordered',
    `ordered_by` VARCHAR(64) NOT NULL,
    `ordered_by_name` VARCHAR(100) NOT NULL DEFAULT '',
    `created_at` INT UNSIGNED NOT NULL,
    `ready_at` INT UNSIGNED NOT NULL,
    `collected_by` VARCHAR(64) NULL DEFAULT NULL,
    `collected_at` INT UNSIGNED NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `workshop_status` (`workshop`, `status`),
    KEY `status_ready` (`status`, `ready_at`)
);

-- 7) Paid invoices (lines = JSON array [{"label": "...", "amount": 1500}, ...]).
-- workshop is NULL for invoices sent outside a workshop (field repairs).
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_invoices` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(50) NULL DEFAULT NULL,
    `mechanic_identifier` VARCHAR(64) NOT NULL,
    `mechanic_name` VARCHAR(100) NOT NULL DEFAULT '',
    `customer_identifier` VARCHAR(64) NOT NULL,
    `customer_name` VARCHAR(100) NOT NULL DEFAULT '',
    `total` INT UNSIGNED NOT NULL,
    `society_share` INT UNSIGNED NOT NULL,
    `lines` LONGTEXT NOT NULL,
    `created_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    KEY `created_at` (`created_at`)
);

-- 8) Society transfers made from the chef's computer. type: 'deposit' | 'withdraw'
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_transactions` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(50) NULL DEFAULT NULL,
    `type` VARCHAR(16) NOT NULL,
    `amount` INT UNSIGNED NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `name` VARCHAR(100) NOT NULL DEFAULT '',
    `created_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    KEY `created_at` (`created_at`)
);

-- 9) Price overrides set from the chef's computer (id = Config.Cosmetic mod id, extras key or 'wash').
-- A missing row means the config default applies.
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_prices` (
    `id` VARCHAR(40) NOT NULL,
    `price` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`)
);

-- ---------------------------------------------------------------------------------------------
-- v3 tables (unix seconds as well)
-- ---------------------------------------------------------------------------------------------

-- 10) Tuning presets. A player's preset belongs to one vehicle model (cosmetic mod indices differ per
-- model); built-in presets live in Config.Presets.builtin, not here.
-- model = unsigned model hash. data = JSON {"cosmetic": {<ox_lib prop key>: value}, "performance": {<category>: level}}
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_presets` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner` VARCHAR(64) NOT NULL,
    `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
    `name` VARCHAR(64) NOT NULL,
    `model` INT UNSIGNED NOT NULL,
    `data` LONGTEXT NOT NULL,
    `created_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    KEY `owner_model` (`owner`, `model`)
);

-- 11) Customer work orders sent from a workshop terminal: one per vehicle (trimmed plate), same data
-- format as presets. Deleted by the resource after expires_at (Config.Presets.workOrderHours).
-- workshop = the terminal's workshop id. model = unsigned model hash of the car it was designed on.
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_workorders` (
    `plate` VARCHAR(16) NOT NULL,
    `workshop` VARCHAR(50) NULL DEFAULT NULL,
    `model` INT UNSIGNED NOT NULL,
    `data` LONGTEXT NOT NULL,
    `owner` VARCHAR(64) NOT NULL,
    `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
    `created_at` INT UNSIGNED NOT NULL,
    `expires_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`plate`),
    KEY `expires_at` (`expires_at`)
);
