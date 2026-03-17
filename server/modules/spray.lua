-- [AI CLEANUP] Decompiled Lua - Fix these:
-- 1. Move ::SHX_LABEL_XX:: outside nested blocks if 'no visible label' error
-- 2. Rename SHX0_1, SHX1_2 variables to meaningful names
-- 3. Replace goto/label with while/repeat-until where possible
-- 4. Remove decompiler comments, add meaningful ones
-- 5. Fix indentation and formatting

local SHX0_1, SHX1_1, SHX2_1, SHX3_1
SHX0_1 = {}
SHX1_1 = AddEventHandler
SHX2_1 = "rcore_sprays:addSpray"
function SHX3_1(SHX0_2, SHX1_2, SHX2_2)
  -- [AI CLEANUP] Decompiled Lua - Fix these:
  -- 1. Move ::SHX_LABEL_XX:: outside nested blocks if 'no visible label' error
  -- 2. Rename SHX0_1, SHX1_2 variables to meaningful names
  -- 3. Replace goto/label with while/repeat-until where possible
  -- 4. Remove decompiler comments, add meaningful ones
  -- 5. Fix indentation and formatting
  
  local SHX3_2, SHX4_2, SHX5_2, SHX6_2, SHX7_2, SHX8_2, SHX9_2, SHX10_2, SHX11_2, SHX12_2, SHX13_2, SHX14_2
  SHX4_2 = SHX1_2
  SHX3_2 = SHX1_2.gsub
  SHX5_2 = "%s"
  SHX6_2 = ""
  SHX3_2 = SHX3_2(SHX4_2, SHX5_2, SHX6_2)
  SHX4_2 = SHX3_2
  SHX3_2 = SHX3_2.lower
  SHX3_2 = SHX3_2(SHX4_2)
  SHX4_2 = nil
  SHX5_2 = ServerIdToGang
  SHX5_2 = SHX5_2[SHX0_2]
  if not SHX5_2 then
    return
  end
  SHX5_2 = pairs
  SHX6_2 = Gangs
  SHX5_2, SHX6_2, SHX7_2, SHX8_2 = SHX5_2(SHX6_2)
  for SHX9_2, SHX10_2 in SHX5_2, SHX6_2, SHX7_2, SHX8_2 do
    SHX11_2 = SHX10_2.tag
    SHX12_2 = SHX11_2
    SHX11_2 = SHX11_2.gsub
    SHX13_2 = "%s"
    SHX14_2 = ""
    SHX11_2 = SHX11_2(SHX12_2, SHX13_2, SHX14_2)
    SHX12_2 = SHX11_2
    SHX11_2 = SHX11_2.lower
    SHX11_2 = SHX11_2(SHX12_2)
    if SHX11_2 ~= SHX3_2 then
      SHX11_2 = SHX10_2.name
      SHX12_2 = SHX11_2
      SHX11_2 = SHX11_2.gsub
      SHX13_2 = "%s"
      SHX14_2 = ""
      SHX11_2 = SHX11_2(SHX12_2, SHX13_2, SHX14_2)
      SHX12_2 = SHX11_2
      SHX11_2 = SHX11_2.lower
      SHX11_2 = SHX11_2(SHX12_2)
      if SHX11_2 ~= SHX3_2 then
        goto SHX_LABEL_37
      end
    end
    SHX4_2 = SHX10_2
    do break end
    -- [FIX IF ERROR] Move ::SHX_LABEL_37:: outside nested blocks until all 'goto SHX_LABEL_37' can see it
    ::SHX_LABEL_37::
  end
  if not SHX4_2 then
    return
  end
  SHX6_2 = SHX4_2.id
  SHX5_2 = SHX0_1
  SHX5_2 = SHX5_2[SHX6_2]
  if SHX5_2 then
    SHX6_2 = SHX4_2.id
    SHX5_2 = SHX0_1
    SHX5_2 = SHX5_2[SHX6_2]
    SHX6_2 = Config
    SHX6_2 = SHX6_2.ZoneOptions
    SHX6_2 = SHX6_2.maximumSprays
    if SHX5_2 > SHX6_2 then
      return
    end
  end
  SHX5_2 = GetZoneAtPosition
  SHX6_2 = SHX2_2
  SHX5_2 = SHX5_2(SHX6_2)
  if SHX5_2 then
    SHX7_2 = SHX4_2.id
    SHX6_2 = SHX0_1
    SHX6_2 = SHX6_2[SHX7_2]
    if not SHX6_2 then
      SHX7_2 = SHX4_2.id
      SHX6_2 = SHX0_1
      SHX6_2[SHX7_2] = 0
    end
    SHX6_2 = 1.0
    SHX7_2 = 1
    SHX9_2 = SHX4_2.id
    SHX8_2 = SHX0_1
    SHX8_2 = SHX8_2[SHX9_2]
    SHX9_2 = 1
    for SHX10_2 = SHX7_2, SHX8_2, SHX9_2 do
      SHX6_2 = SHX6_2 * 0.9
    end
    SHX7_2 = ServerIdToGang
    SHX7_2 = SHX7_2[SHX0_2]
    SHX7_2 = SHX7_2.id
    SHX8_2 = SHX4_2.id
    if SHX7_2 == SHX8_2 then
      SHX8_2 = SHX4_2.id
      SHX7_2 = SHX0_1
      SHX9_2 = SHX7_2[SHX8_2]
      SHX9_2 = SHX9_2 + 1
      SHX7_2[SHX8_2] = SHX9_2
      SHX7_2 = SetTimeout
      SHX8_2 = 3600000
      function SHX9_2()
        -- [AI CLEANUP] Decompiled Lua - Fix these:
        -- 1. Move ::SHX_LABEL_XX:: outside nested blocks if 'no visible label' error
        -- 2. Rename SHX0_1, SHX1_2 variables to meaningful names
        -- 3. Replace goto/label with while/repeat-until where possible
        -- 4. Remove decompiler comments, add meaningful ones
        -- 5. Fix indentation and formatting
        
        local SHX0_3, SHX1_3, SHX2_3
        SHX1_3 = SHX4_2.id
        SHX0_3 = SHX0_1
        SHX0_3 = SHX0_3[SHX1_3]
        if SHX0_3 then
          SHX1_3 = SHX4_2.id
          SHX0_3 = SHX0_1
          SHX0_3 = SHX0_3[SHX1_3]
          if SHX0_3 > 0 then
            SHX1_3 = SHX4_2.id
            SHX0_3 = SHX0_1
            SHX2_3 = SHX0_3[SHX1_3]
            SHX2_3 = SHX2_3 - 1
            SHX0_3[SHX1_3] = SHX2_3
          end
        end
      end
      SHX7_2(SHX8_2, SHX9_2)
      SHX7_2 = GetRivalry
      SHX8_2 = SHX5_2.name
      SHX7_2 = SHX7_2(SHX8_2)
      SHX8_2 = Config
      SHX8_2 = SHX8_2.IncreaseMultipliers
      SHX8_2 = SHX8_2.SPRAY
      if SHX7_2 then
        SHX9_2 = Config
        SHX9_2 = SHX9_2.IncreaseMultipliersRivalry
        SHX8_2 = SHX9_2.SPRAY
      end
      SHX9_2 = IncreaseLoyalty
      SHX10_2 = SHX0_2
      SHX11_2 = SHX5_2
      SHX12_2 = "SPRAY"
      SHX13_2 = SHX6_2
      SHX14_2 = SHX8_2
      SHX9_2(SHX10_2, SHX11_2, SHX12_2, SHX13_2, SHX14_2)
    end
  end
end
SHX1_1(SHX2_1, SHX3_1)
SHX1_1 = AddEventHandler
SHX2_1 = "rcore_sprays:removeSpray"
function SHX3_1(SHX0_2, SHX1_2, SHX2_2)
  -- [AI CLEANUP] Decompiled Lua - Fix these:
  -- 1. Move ::SHX_LABEL_XX:: outside nested blocks if 'no visible label' error
  -- 2. Rename SHX0_1, SHX1_2 variables to meaningful names
  -- 3. Replace goto/label with while/repeat-until where possible
  -- 4. Remove decompiler comments, add meaningful ones
  -- 5. Fix indentation and formatting
  
  local SHX3_2, SHX4_2, SHX5_2, SHX6_2, SHX7_2, SHX8_2, SHX9_2, SHX10_2, SHX11_2, SHX12_2, SHX13_2, SHX14_2, SHX15_2, SHX16_2, SHX17_2, SHX18_2, SHX19_2
  SHX4_2 = SHX1_2
  SHX3_2 = SHX1_2.gsub
  SHX5_2 = "%s"
  SHX6_2 = ""
  SHX3_2 = SHX3_2(SHX4_2, SHX5_2, SHX6_2)
  SHX4_2 = SHX3_2
  SHX3_2 = SHX3_2.lower
  SHX3_2 = SHX3_2(SHX4_2)
  SHX4_2 = nil
  SHX5_2 = ServerIdToGang
  SHX5_2 = SHX5_2[SHX0_2]
  if not SHX5_2 then
    return
  end
  SHX5_2 = pairs
  SHX6_2 = Gangs
  SHX5_2, SHX6_2, SHX7_2, SHX8_2 = SHX5_2(SHX6_2)
  for SHX9_2, SHX10_2 in SHX5_2, SHX6_2, SHX7_2, SHX8_2 do
    SHX11_2 = SHX10_2.tag
    SHX12_2 = SHX11_2
    SHX11_2 = SHX11_2.gsub
    SHX13_2 = "%s"
    SHX14_2 = ""
    SHX11_2 = SHX11_2(SHX12_2, SHX13_2, SHX14_2)
    SHX12_2 = SHX11_2
    SHX11_2 = SHX11_2.lower
    SHX11_2 = SHX11_2(SHX12_2)
    if SHX11_2 ~= SHX3_2 then
      SHX11_2 = SHX10_2.name
      SHX12_2 = SHX11_2
      SHX11_2 = SHX11_2.gsub
      SHX13_2 = "%s"
      SHX14_2 = ""
      SHX11_2 = SHX11_2(SHX12_2, SHX13_2, SHX14_2)
      SHX12_2 = SHX11_2
      SHX11_2 = SHX11_2.lower
      SHX11_2 = SHX11_2(SHX12_2)
      if SHX11_2 ~= SHX3_2 then
        goto SHX_LABEL_37
      end
    end
    SHX4_2 = SHX10_2
    do break end
    -- [FIX IF ERROR] Move ::SHX_LABEL_37:: outside nested blocks until all 'goto SHX_LABEL_37' can see it
    ::SHX_LABEL_37::
  end
  if not SHX4_2 then
    return
  end
  SHX5_2 = GetZoneAtPosition
  SHX6_2 = SHX2_2
  SHX5_2 = SHX5_2(SHX6_2)
  if SHX5_2 then
    SHX6_2 = GetRivalry
    SHX7_2 = SHX5_2.name
    SHX6_2 = SHX6_2(SHX7_2)
    SHX7_2 = Config
    SHX7_2 = SHX7_2.DecreaseMultipliers
    SHX7_2 = SHX7_2.SPRAY
    if SHX6_2 then
      SHX8_2 = Config
      SHX8_2 = SHX8_2.DecreaseMultipliersRivalry
      SHX7_2 = SHX8_2.SPRAY
    end
    SHX8_2 = ipairs
    SHX9_2 = SHX4_2.members
    SHX8_2, SHX9_2, SHX10_2, SHX11_2 = SHX8_2(SHX9_2)
    for SHX12_2, SHX13_2 in SHX8_2, SHX9_2, SHX10_2, SHX11_2 do
      SHX14_2 = PlayerIdToServerId
      SHX15_2 = SHX13_2.identifier
      SHX14_2 = SHX14_2[SHX15_2]
      if SHX14_2 then
        SHX14_2 = DecreaseLoyalty
        SHX15_2 = PlayerIdToServerId
        SHX16_2 = SHX13_2.identifier
        SHX15_2 = SHX15_2[SHX16_2]
        SHX16_2 = SHX5_2
        SHX17_2 = "SPRAY"
        SHX18_2 = 1.0
        SHX19_2 = SHX7_2
        SHX14_2(SHX15_2, SHX16_2, SHX17_2, SHX18_2, SHX19_2)
        break
      end
    end
  end
end
SHX1_1(SHX2_1, SHX3_1)
