-- robbery.lua

RegisterNetEvent("esx_holdup:robberyComplete")
AddEventHandler("esx_holdup:robberyComplete", function()
  TriggerServerEvent("esx_holdup:robberyComplete")
end)