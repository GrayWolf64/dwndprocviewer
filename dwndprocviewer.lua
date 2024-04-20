--- Derma Window Process Viewer, or dwpv
-- I learned about `Process Explorer` by Sysinternals a while ago,
-- and decided to make one similiar for gmod.
--
-- You can view all the panel processes(vgui objects) locally, or take a look
-- at other players' processes(planned) in the same server with you(admin).
--
-- I found some advice on perf related to large tables here:
-- 1. https://forums.civfanatics.com/threads/optimizing-your-lua-code-for-speed.463488/
-- 2. https://www.lua.org/gems/sample.pdf
-- 3. https://springrts.com/wiki/Lua_Performance
-- Some helpful instructions on hooking, since the `debug` related hooking helpers
-- are 'deprecated' according to GMod Wiki.
-- https://forums.kleientertainment.com/forums/topic/129557-tutorial-function-hooking-and-you/
--
-- TODO: docs(detailed comments)
--
-- @script dwndprocviewer
-- @author Tairikuookami(GrayWolf)
-- @copyright Tairikuookami(GrayWolf)
-- @license GNU GENERAL PUBLIC LICENSE VERSION 3

if not CLIENT then return end

local inf = math.huge

local viewer           = nil
local viewer_tip       = nil
local viewer_name      = "DWndProcViewer"
local viewer_name_full = "Derma Window Process Viewer"

local get_world_panel = vgui.GetWorldPanel
local get_kb_focus    = vgui.GetKeyboardFocus
local get_cursor_pos  = input.GetCursorPos
local get_debug_info  = debug.getinfo
local get_hud_panel   = GetHUDPanel

local set_draw_color = surface.SetDrawColor
local draw_rect      = surface.DrawRect
local derma_skinhook = derma.SkinHook
local cur_time       = CurTime
local pcall          = pcall
local tostring       = tostring
local print_table    = PrintTable
local is_valid       = IsValid
local str_format     = string.format

local function is_timer_over(start, limit)
    return cur_time() - start > limit
end

local function ico16(name)
    return "icon16/" .. name .. ".png"
end

local function remove_accessors(_panel, key, name)
    _panel[key]           = nil
    _panel["Get" .. name] = nil
    _panel["Set" .. name] = nil
end

local icon_map = {
    ["GModBase"]          = ico16"anchor",
    ["HudGMOD"]           = ico16"monitor",

    ["Panel"]             = ico16"application_xp",
    ["DPanel"]            = ico16"application_osx",

    ["DMenu"]             = ico16"text_list_bullets",
    ["DMenuOption"]       = ico16"tick",
    ["DMenuOptionCVar"]   = ico16"brick",

    ["DSizeToContents"]   = ico16"arrow_inout",

    ["DCategoryList"]     = ico16"application_view_list",
    ["DCategoryHeader"]   = ico16"tab_add",

    ["DMenuBar"]          = ico16"drive",

    ["DButton"]           = ico16"shape_move_forwards",
    ["DExpandButton"]     = ico16"bullet_add",

    ["DTree"]             = ico16"text_indent",
    ["DTree_Node"]        = ico16"bullet_toggle_plus",
    ["DTree_Node_Button"] = ico16"bullet_blue",

    ["DLabel"]            = ico16"text_dropcaps",
    ["DImage"]            = ico16"image",
    ["DImageButton"]      = ico16"image_add",
    ["DDragBase"]         = ico16"plugin_link",
    ["DTileLayout"]       = ico16"application_view_gallery",
    ["DIconLayout"]       = ico16"application_view_tile",

    ["DPropertySheet"]    = ico16"page_copy",
    ["DTab"]              = ico16"tab",

    ["DScrollBarGrip"]    = ico16"timeline_marker",
    ["DVScrollBar"]       = ico16"shape_align_top",

    ["DTextEntry"]        = ico16"textfield",

    ["ControlPanel"]      = ico16"cog",

    ["ContextMenu"]       = ico16"overlays",
    ["SpawnMenu"]         = ico16"application_view_icons",
    ["SpawnIcon"]         = ico16"photo",
    ["ModelImage"]        = ico16"picture",
    ["ContentIcon"]       = ico16"photo",
    ["ContentContainer"]  = ico16"photos",
    ["NoticePanel"]       = ico16"information",

    ["DHTML"]             = ico16"html",

    ["DHorizontalScroller"] = ico16"shape_align_left",
    ["DHorizontalDivider"]  = ico16"application_tile_horizontal"
}

local icon_default = ico16"application"
local function fetch_icon(name)
    local _icon = icon_map[name]

    if not _icon then _icon = icon_default end

    return _icon
end

--- These items can be very rich sometimes
local complicated = {
    ["GModMouseInput"]   = true,
    ["SpawnMenu"]        = true,
    ["ControlPanel"]     = true,
    ["ContextMenu"]      = true,
    ["ContentContainer"] = true,
    ["DMenu"]            = true,
    ["DTree"]            = true,
    ["DListView"]        = true,
    ["DCategoryList"]    = true,
    ["DListLayout"]      = true,
    ["DPropertySheet"]   = true,
    ["DScrollPanel"]     = true,
    [viewer_name]        = true
}

-- {child(input panel), parent, parent's parent, ..., one of root's child}
-- at the present, `root` is just the `WorldPanel`(GModBase)
local function get_parental_queue(_panel, root)
    local _queue = {
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil
    }
    -- 8 x 8 = 64

    for i = 1, inf do
        if _panel == root then break end
        _queue[i] = _panel
        _panel = _panel:GetParent()
    end

    return _queue
end

local function diff_new_elements(t1, t2)
    local bool_list = {
        nil, nil, nil, nil, nil, nil, nil, nil
    }

    for i = 1, #t1 do
        bool_list[t1[i]] = true
    end

    local delta_new = {}
    local pos = 0
    local val

    for i = 1, #t2 do
        val = t2[i]

        if not bool_list[val] then
            pos = pos + 1

            delta_new[pos] = val
        end
    end

    return delta_new, pos
end

--- https://www.hello-algo.com/chapter_stack_and_queue/stack/
-- A simpler and faster stack impl compared to garry's `util.Stack()`
local array_stack = {_size = 0}

function array_stack:push(item)
    self._size = self._size + 1
    self[self._size] = item
end

function array_stack:pop()
    local size = self._size
    if size == 0 then return end
    local item = self[size]
    self[size] = nil
    self._size = size - 1

    return item
end

function array_stack:clear()
    local size = self._size
    if size == 0 then return end

    for i = 1, size do self[i] = nil end

    self._size = 0
end

--- This algo must be as fast as possible(I can't come up with a faster one with no tricks & hacks)
-- In sandbox mode, we usually generate about 850 parental queues(with only this addon installed)
-- pre-alloc, make compiler more informed(tested with LuaJIT)
--
-- Some notable changes:
-- 1. this is one of the places where I replaced ipairs with pure 'for', getting `update_tree dt = 0.83s` reduced to roughly 0.44s
-- 2. I replaced `next(children)` with `_panel:HasChildren()`, and got `update_tree dt` reduced to roughly 0.38s
--
-- I later decided to change recursion into simulated recursion(deepth-first-search) to avoid
-- potential stack overflow, algo: https://juejin.cn/post/7043390405240422414#heading-5
-- Tested, they produce the same size of _parental_queues

--- Below is the og algo, then you call `_traverse(root_panel)` to fill the table
-- local function _traverse(_panel)

--     if not _panel:HasChildren() then
--         pos = pos + 1
--         _parental_queues[pos] = get_parental_queue(_panel, root_panel)

--         return
--     end

--     local children = _panel:GetChildren()

--     for i = 1, #children do
--         _traverse(children[i])
--     end
-- end
local function make_data(root_panel)
    local _parental_queues = {
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,

        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,

        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    }
    -- 3 x 16 x 16 = 768

    array_stack:push(root_panel)

    local current_panel
    local children
    local pos = 0
    for _ = 1, inf do
        if array_stack._size == 0 then break end

        current_panel = array_stack:pop()
        if current_panel:HasChildren() then
            children = current_panel:GetChildren()

            for i = #children, 1, -1 do
                array_stack:push(children[i])
            end
        else
            pos = pos + 1
            _parental_queues[pos] = get_parental_queue(current_panel, root_panel)
        end
    end

    array_stack:clear()

    return _parental_queues, pos
end

local function safe_getname(_panel)
    local name = _panel:GetName()
    if name == nil or name == "" then name = tostring(_panel) end
    return name
end

local function safe_setvisible(_panel, is_visible)
    if is_valid(_panel) then _panel:SetVisible(is_visible) end
end

local dock_enums = {
    [0] = "NODOCK",
    [1] = "FILL",
    [2] = "LEFT",
    [3] = "RIGHT",
    [4] = "TOP",
    [5] = "BOTTOM"
}

local function ret_func() return end
local function false_ret_func() return false end

local function open_viewer()
    if is_valid(viewer) then viewer:Remove() end

    viewer = vgui.Create("DFrame", nil, viewer_name)
    viewer:SetSize(ScrW() / 1.75, ScrH() / 1.7)
    viewer:Center()
    viewer:MakePopup()

    local function make_title(client)
        return viewer_name_full
            .. " ["
            .. client:GetName()
            .. "@"
            .. game.GetIPAddress():gsub("loopback", "Singleplayer", 1)
            .. "]"
    end

    viewer:SetTitle(make_title(LocalPlayer()))
    viewer:SetIcon(ico16"application_form_magnify")

    if is_valid(viewer_tip) then viewer_tip:Remove() end

    viewer_tip = vgui.Create("DLabel")
    viewer_tip:SetName(viewer_name .. "Tip")
    viewer_tip:SetFont("Trebuchet18")
    viewer_tip:SetDrawOnTop(true)
    viewer_tip:SetVisible(false)

    function viewer_tip:UpdateColours(skin) return self:SetTextStyleColor(skin.Colours.TooltipText) end
    function viewer_tip:Paint(w, h) derma.SkinHook("Paint", "Tooltip", self, w, h) end

    local function get_func_pos(f)
        if not f then return "Unknown" end
        return get_debug_info(f, "S").source
    end

    local function get_dock_info(_panel)
        local left, top, right, bottom = _panel:GetDockMargin()
        return str_format(dock_enums[_panel:GetDock()] .. " [%d, %d, %d, %d]", left, top, right, bottom)
    end

    local function generate_tip_text(_panel)
        if not _panel:IsValid() then return " Pointed Panel Is Invalid " end

        return " Init()\n   "      .. get_func_pos(_panel.Init or _panel.IsValid)                .. "\n"
            .. " Paint()\n   "     .. get_func_pos(_panel.Paint)                                 .. "\n"
            .. " Size: "           .. str_format("[%u, %u]", _panel:GetWide(), _panel:GetTall()) .. "\n"
            .. " Z Pos: "          .. tostring(_panel:GetZPos())                                 .. "\n"
            .. " Children Count: " .. tostring(#_panel:GetChildren())                            .. "\n"
            .. " Dock: "           .. get_dock_info(_panel)                                      .. " "
    end

    local menu_bar = vgui.Create("DMenuBar", viewer)
    menu_bar:Dock(TOP)
    menu_bar:DockMargin(-1, -4, -1, 0)

    local file_menu     = menu_bar:AddMenu("File")
    local settings_menu = menu_bar:AddMenu("Settings")
    local view_menu     = menu_bar:AddMenu("View")

    local property_sheet = vgui.Create("DPropertySheet", viewer)
    property_sheet:SetPadding(4)
    property_sheet:Dock(FILL)
    property_sheet:DockMargin(-2, 0, -2, -2)

    --- All the `time` related vars are in seconds
    -- This `do-end` block indicates a new sheet
    -- TODO: A more detailed tree, columns and so on
    do
        local treeview = vgui.Create("DTree", property_sheet)
        treeview:Dock(FILL)
        treeview:DockMargin(3, -5, 3, 3)
        treeview.VBar:SetWide(12)

        property_sheet:AddSheet("Local Processes", treeview, ico16"application_side_tree")

        local colors = {
            none       = {255, 255, 255, 0},    -- Transparent white
            disabled   = {130, 130, 130, 175},  -- Gray
            invisible  = {207, 207, 207, 125},  -- Slight gray
            marked_del = {255, 48, 48, 200},    -- Red
            kb_focus   = {152, 245, 255, 225},  -- Light blue(a bit like cyan)
            focused    = {255, 193, 37, 225},   -- Orange
            new        = {0, 238, 0, 200},      -- Bright green
            modal      = {255, 48, 255, 200}    -- Slightly dark pink
        }

        local function update_tree() return end

        local new_panel_list = {
            nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil
        }
        -- 4 x 8 = 32

        local dummy_animslide = {
            Stop = ret_func, Start = ret_func,
            Run = ret_func, Active = false_ret_func
        }

        local _node_menu
        local function kill_node_menu()
            if not is_valid(_node_menu) then return end

            RegisterDermaMenuForClose(_node_menu)
            CloseDermaMenus()
        end

        --- cleans, modifies the node's behavior
        -- trying my best not to alter user-defined panels' behaviors
        local function __node_mod(_node, _panel, is_new_node, _ignore_new)
            function _node:DoRightClick()
                _node_menu = DermaMenu(false, viewer)

                --- This may create a bunch of closures, too bad
                _node_menu:AddOption("Kill", function() _panel:Remove() end):SetIcon(ico16"cross")
                _node_menu:AddOption("Dump Lua Table to Console", function()
                    print_table(_panel:GetTable())
                end):SetIcon(ico16"printer")

                --- Don't leave the tip visible when the menu opens
                safe_setvisible(viewer_tip, false)
                _node_menu:Open()
            end

            --- This frees me from updating each node's color manually
            -- can also act as a panel creation & removal listener which allows for
            -- automated node updates
            -- start_t: When the action starts
            -- color_dt: How long the color will remain unchanged
            local deleted = {start_t = nil, color_dt = 1}
            local new     = {start_t = nil, color_dt = 1.25}

            local children
            if not _ignore_new then
                children = {previous = _panel:GetChildren(), present = {}}
            end

            if is_new_node then
                new_panel_list[_panel] = true
            end

            local label = _node.Label
            label.GenerateExample = nil

            _node.Expander.GenerateExample = nil

            --- Disables animation
            _node.animSlide = dummy_animslide
            _node.AnimSlide = nil
            _node.Think     = ret_func

            do
                local previous_on_cursor_entered = label.OnCursorEntered
                function label:OnCursorEntered()
                    previous_on_cursor_entered(self)

                    --- Don't show tip when right-click menu is visible,
                    -- or the menu bar has any open menus
                    if is_valid(_node_menu) or menu_bar:GetOpenMenu() then return end

                    local x, y = get_cursor_pos()
                    viewer_tip:SetPos(x, y)

                    safe_setvisible(viewer_tip, true)
                end

                local previous_on_cursor_exited = label.OnCursorExited
                function label:OnCursorExited()
                    previous_on_cursor_exited(self)

                    safe_setvisible(viewer_tip, false)
                end
            end

            label:SetVisible(true)

            local _color = colors.none
            function label:Think()
                --- turns into `Panel [NULL]`, who still has certain methods
                -- a direct call to `_panel.IsMarkedForDeletion` will emit an error
                if not pcall(_panel.IsMarkedForDeletion, _panel) then
                    _color = colors.marked_del

                    deleted.start_t = deleted.start_t or cur_time()

                    if is_timer_over(deleted.start_t, deleted.color_dt) then
                        _node:Remove()

                        kill_node_menu()
                    end
                else
                    if _ignore_new then goto no_new_logic end

                    --- When the tree is updated for the first time / forced to refresh, all the created
                    -- nodes are not seen as 'new nodes'. Their children tables are compared when they
                    -- think(a table before Think, another table on Think). When any new children are
                    -- detected, they are added, tagged as 'new nodes' and then modded(`is_new_node` = true).
                    -- After these nodes are added, `update_tree` will be called in their Think, treating one node as root node
                    -- (`is_new_subtree` = true, which later will be passed into this function as `is_new_node`,
                    -- leading to a recursion, where the newly added nodes' children will be properly & fully created).
                    -- The recursion is likely to be pretty 'mild'.
                    if not is_new_node then
                        children.present = _panel:GetChildren()

                        local new_node
                        local new_panel
                        local new_panels, num = diff_new_elements(children.previous, children.present)
                        for i = 1, num do
                            new_panel = new_panels[i]
                            new_node = _node:AddNode(safe_getname(new_panel))

                            __node_mod(new_node, new_panel, true)
                        end

                        children.previous = children.present
                    else
                        update_tree(true, _panel, _node, true)
                    end

                    :: no_new_logic ::

                    if     not _panel:IsEnabled()   then _color = colors.disabled
                    elseif not _panel:IsVisible()   then _color = colors.invisible
                    elseif _panel:IsModal()         then _color = colors.modal
                    elseif _panel == get_kb_focus() then _color = colors.kb_focus
                    elseif _panel:HasFocus()        then _color = colors.focused
                    else _color = colors.none       end

                    --- This panel is newly created, highlight it
                    if new_panel_list[_panel] then
                        new.start_t = new.start_t or cur_time()

                        if not is_timer_over(new.start_t, new.color_dt) then
                            _color = colors.new
                        else
                            new_panel_list[_panel] = nil
                        end
                    end
                end

                --- In case that user accidentally removes the viewer tip panel
                -- Must tell users of this tool not to remove certain panels that
                -- make this tool function as expected
                if not self:IsHovered() or not is_valid(viewer_tip) then return end

                viewer_tip:SetText(generate_tip_text(_panel))
                viewer_tip:SizeToContents()
            end

            function label:Paint(w, h)
                set_draw_color(_color[1], _color[2], _color[3], _color[4])
                draw_rect(self:GetX(), self:GetY(), w, h)

                derma_skinhook("Paint", "TreeNodeButton", self, w, h)

                return false
            end

            --- We don't need these file related crap
            remove_accessors(_node, "m_strFolder", "Folder")
            remove_accessors(_node, "m_strFileName", "FileName")
            remove_accessors(_node, "m_strPathID", "PathID")
            remove_accessors(_node, "m_strWildCard", "WildCard")
            remove_accessors(_node, "m_bShowFiles", "ShowFiles")
            remove_accessors(_node, "m_bNeedsPopulating", "NeedsPopulating")

            _node.AddFolder               = nil
            _node.MakeFolder              = nil
            _node.FilePopulateCallback    = nil
            _node.PopulateChildren        = nil
            _node.Copy                    = nil
            _node.SetupCopy               = nil
            _node.PopulateChildrenAndSelf = false_ret_func

            local _name = safe_getname(_panel)

            _node:SetExpanded(not complicated[_name], true)
            _node:SetIcon(fetch_icon(_name))
        end

        --- The logic behind this took me a long while to come up with.
        -- Previously I used recursion when creating nodes at the same time,
        -- but that leads to 'Engine Error' which means too much memory being occupied(even in x64).
        -- so I decided to seperate the procedure into two: make data & populate tree
        function update_tree(do_expand, root_panel, _tree, is_new_subtree)
            -- {[panel1] = node1, [panel2] = node2, ...}
            local solved_panels = {
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,

                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
            }
            -- 2 x 16 x 16 = 512

            local root_node
            if root_panel == get_world_panel() or root_panel == get_hud_panel() then
                root_node = _tree:AddNode(safe_getname(root_panel))
                root_node:SetExpanded(true, true)
            else
                root_node = _tree
            end

            local queue
            local panel
            local parent_node
            local function _new_node(ignore_new)
                if not solved_panels[panel] then
                    parent_node = parent_node:AddNode(safe_getname(panel))
                    parent_node:SetExpanded(do_expand, true)

                    __node_mod(parent_node, panel, is_new_subtree, ignore_new)

                    solved_panels[panel] = parent_node
                else
                    parent_node = solved_panels[panel]
                end
            end

            local data, data_size = make_data(root_panel)

            local queue_size
            for i = 1, data_size do
                queue = data[i]
                queue_size = #queue
                parent_node = root_node

                --- This makes the children panels of this viewer not shown,
                -- since when shown, refreshing the tree may give rise to serious issues
                if queue[queue_size] == viewer then
                    panel = viewer
                    _new_node(true)

                    goto outer_loop_end
                end

                for j = queue_size, 1, -1 do
                    panel = queue[j]

                    _new_node(false)
                end

                :: outer_loop_end ::
            end

            __node_mod(root_node, root_panel)
        end

        --- First time update occurs mostly when you open the viewer for the first time
        local function refresh_tree()
            treeview:Clear()

            update_tree(true, get_world_panel(), treeview)
            update_tree(true, get_hud_panel(), treeview)
        end

        do
            --- Makes right-click menu disappear when user is going to click the buttons
            -- on the menu bar
            for i = 1, menu_bar:ChildCount() do
                -- weird index starting from 0
                local button = menu_bar:GetChild(i - 1)

                local previous_on_cursor_entered = button.OnCursorEntered
                function button:OnCursorEntered()
                    previous_on_cursor_entered(self)

                    kill_node_menu()
                end
            end

            view_menu:AddOption("Force Refresh", refresh_tree):SetIcon(ico16"arrow_refresh")

            local opacity_menu, opacity_option = view_menu:AddSubMenu("Opacity")
            opacity_menu:SetDeleteSelf(false)
            opacity_option:SetIcon(ico16"shading")

            for i = 1, 9 do
                opacity_menu:AddOption(tostring(i) .. "0%", function()
                    viewer:SetAlpha(i / 10 * 255)
                end)
            end

            opacity_menu:AddOption("Opaque", function() viewer:SetAlpha(255) end)
        end

        refresh_tree()
    end
end

concommand.Add("dwndprocviewer", open_viewer)
