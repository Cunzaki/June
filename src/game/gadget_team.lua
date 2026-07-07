--[[ Gadget ownership — mirrors Util.ownership from game scripts (UserId / Team attributes). ]]

local env = OperationOne.require("core.env")

local M = {}

local function get_attr(inst, name)
    if not inst or type(inst.GetAttribute) ~= "function" then
        return nil
    end
    return inst:GetAttribute(name)
end

local function local_identity()
    local lp = env.get_local_player()
    if not lp then
        return nil
    end

    local user_id = lp.user_id or lp.UserId or lp.userid
    local team = lp.team or lp.Team
    local spectator = nil

    if type(lp.GetAttribute) == "function" then
        team = team or lp:GetAttribute("Team")
        spectator = lp:GetAttribute("Spectator")
    end

    local char = lp.character or lp.Character
    if char and type(char.GetAttribute) == "function" then
        team = team or char:GetAttribute("Team")
        if spectator == nil then
            spectator = char:GetAttribute("Spectator")
        end
    end

    return {
        user_id = user_id,
        team = team,
        spectator = spectator == true,
    }
end

function M.ownership_level(obj)
    if not obj then
        return nil
    end

    local gadget_uid = get_attr(obj, "UserId")
    local gadget_team = get_attr(obj, "Team")
    if gadget_uid == nil and gadget_team == nil then
        return nil
    end

    local me = local_identity()
    if not me then
        return nil
    end

    if gadget_uid ~= nil and me.user_id ~= nil and gadget_uid == me.user_id then
        return 3
    end
    if me.spectator then
        return 2
    end
    if gadget_team and me.team and gadget_team == me.team then
        return 2
    end
    return 0
end

function M.is_friendly_gadget(obj)
    local level = M.ownership_level(obj)
    return level == 2 or level == 3
end

return M
