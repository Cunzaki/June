--[[
    Vector full-mode grid:
      menu.add_group(tab, name)           -> left column, new row
      menu.add_group(tab, name, 0, true) -> right column, same row as previous left
]]

local M = {}

M.TAB = "Operation One"

M.G = {
    COMBAT = "Combat",
    PLAYERS = "Players",
    WORLD = "World",
    SETTINGS = "Settings",
}

M._tab_ready = false
M._groups_ready = false
M._groups = {}

function M.ensure_tab()
    if M._tab_ready then
        return
    end
    if not (OperationOne and OperationOne._menu_tab_ready) and menu and menu.add_tab then
        menu.add_tab(M.TAB, "O", "full")
    end
    M._tab_ready = true
end

function M.ensure_groups()
    if M._groups_ready then
        return
    end
    M.ensure_tab()

    local rows = {
        { M.G.COMBAT, M.G.PLAYERS },
        { M.G.WORLD, M.G.SETTINGS },
    }

    for _, row in ipairs(rows) do
        menu.add_group(M.TAB, row[1])
        M._groups[row[1]] = true
        if row[2] then
            menu.add_group(M.TAB, row[2], 0, true)
            M._groups[row[2]] = true
        end
    end

    M._groups_ready = true
end

return M
