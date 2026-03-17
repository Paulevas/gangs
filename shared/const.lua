-- shared/const.lua (CLEAN)
-- Constants used for debug session names + step types.

SessionNames = {
  ESX_OBJECT = "Getting ESX shared object thread",
  QBCORE_OBJECT = "Getting QBCore shared object thread",
  MAIN_CLIENT_THREAD = "Main client resource thread",
  MAIN_SERVER_THREAD = "Main server resource thread",
  ZONE_LOYALTY_MANAGEMENT = "Zone loyalty management thread",
  INPUT_FROM_KEYBOARD = "Input from keyboard thread",
  OX_INTEGRATION = "Integration for OX ped stuff thread",
  QB_AMBULANCE_JOB_INTEGRATION = "Integration for qb-ambulance stuff thread",
  SETTING_PLAYER_PRESENCE_POINT = "Setting player presence into point thread",
  MYSQL_INIT = "MySQL creation thread",
  BUSINESSES_MONEY_MANAGEMENT = "Businesses management thread",
  RIVALRIES_STATUS = "Rivalries status thread",
}

-- StepTypes maps "session name" -> { stepKey = "STEP_KEY" }
-- Kept compatible with the original structure.
StepTypes = {
  [SessionNames.MAIN_CLIENT_THREAD] = {
    GANG_ZONE_LOGIC = "GANG_ZONE_LOGIC",
    TARGETED_ACTION_PROCESSING = "TARGETED_ACTION_PROCESSING",
    MENU_RENDERING_CONTROL = "MENU_RENDERING_CONTROL",
    HUD_ZONE_DISPLAY = "HUD_ZONE_DISPLAY",
    GANG_ZONE_RETVAL = "GANG_ZONE_RETVAL",
    GANG_ZONE_RENDER_BUSINESS = "GANG_ZONE_RENDER_BUSINESS",
    GANG_ZONE_CHECKPOINT = "GANG_ZONE_CHECKPOINT",
    TARGET_DRUG_OPTIONS = "TARGET_DRUG_OPTIONS",
    CACHE_PEDS_DRUG_OPTIONS = "CACHE_PEDS_DRUG_OPTIONS",
    CACHING_PEDS = "CACHING_PEDS",
    KIDNAPPING_ACTION = "KIDNAPPING_ACTION",
    KIDNAPPING_ACTION_ENTITIES = "KIDNAPPING_ACTION_ENTITIES",
  },
}
