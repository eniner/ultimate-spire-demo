-- Invisible auto-spawned Zone Controller NPC.
-- EQEmu loads quests/global/zone_controller.pl for an NPC named zone_controller.
-- instance_tools.pl GetControllerNPCID() is hardcoded to 2000986.
-- If you already have a different zone_controller id, either use 2000986
-- or change GetControllerNPCID() to match.

INSERT INTO npc_types (
  id, name, lastname, level, race, class, bodytype, hp, special_abilities
) VALUES (
  2000986,
  'zone_controller',
  NULL,
  100,
  127,
  1,
  68,
  999999999,
  '12,1^13,1^14,1^15,1^16,1^17,1^18,1^19,1^20,1^21,1^22,1^23,1^24,1^25,1^26,1^28,1^31,1^35,1^39,1'
) ON DUPLICATE KEY UPDATE
  name = 'zone_controller',
  race = 127,
  class = 1,
  bodytype = 68,
  hp = 999999999;
