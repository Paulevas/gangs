if not Config.Dispatch or Config.Dispatch == 0 then
    if GetResourceState('lb-tablet') == 'starting' or GetResourceState('lb-tablet') == 'started' then
        Config.Dispatch = 8
    end
end

if Config.Dispatch and Config.Dispatch == 8 then
    Dispatch = function(source, drug)
        local dispatchData = {
            priority = "medium",
            code = "10-52",
            title = "Drugs sold",
            description = "",
            location = {label = "", coords = GetEntityCoords(GetPlayerPed(source)).xy},
            time = 5000,
            job = "police",
        }
        local dispatchId = exports["lb-tablet"]:AddDispatch(dispatchData)
    end
end