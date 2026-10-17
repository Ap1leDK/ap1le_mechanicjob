-- ap1le_mechanicjob database install
-- Run once on the server database (ESX Legacy schema must already exist).
-- Safe to run again: every statement is idempotent.
-- owned_vehicles is ESX's existing table; this script does not change it.

-- 1) Job
INSERT IGNORE INTO `jobs` (`name`, `label`, `whitelisted`) VALUES
    ('mechanic', 'Mechanic', 1);

-- 2) Job grades
-- Remove any previous grades first so re-running the script never creates duplicate grades.
DELETE FROM `job_grades` WHERE `job_name` = 'mechanic';

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
    ('mechanic', 0, 'recruit',     'Recruit',     500,  '{}', '{}'),
    ('mechanic', 1, 'mechanic',    'Mechanic',    800,  '{}', '{}'),
    ('mechanic', 2, 'experienced', 'Experienced', 1000, '{}', '{}'),
    ('mechanic', 3, 'boss',        'Boss',        1500, '{}', '{}');

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
CREATE TABLE IF NOT EXISTS `ap1le_mechanicjob_parts` (
    `plate` VARCHAR(12) NOT NULL,
    `category` VARCHAR(20) NOT NULL,
    `level` TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`plate`, `category`)
);
