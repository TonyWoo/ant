local imgui             = require "imgui_wrap"
local widget            = imgui.widget
local flags             = imgui.flags
local windows           = imgui.windows
local util              = imgui.util
local cursor            = imgui.cursor
local enum              = imgui.enum
local IO                = imgui.IO

local pm                = require "antpm"
local gui_input         = require "gui_input"
local gui_mgr         = require "gui_mgr"
local gui_util          = require "editor.gui_util"
local fs                = require "filesystem"
local lfs               = require "filesystem.local"

local GuiProjectList    = require "editor.projects.gui_project_list"

local hub = import_package("ant.editor").hub
local Event = require "hub_event"

local GuiBase           = require "gui_base"
local GuiPackageView    = GuiBase.derive("GuiGuiPackageView")
GuiPackageView.GuiName  = "GuiPackageView"

local FileOpenEvent = setmetatable(
    {
        scene = Event.ETE.OpenScene,
    },
    {   __index = function(tab,key)
            return Event.ETE.OpenRes
        end
    })


function GuiPackageView:_init()
    GuiBase._init(self)
    self.win_flags = flags.Window { "MenuBar" }
    self.title_id = string.format("Project###%s",self.GuiName)
    self.default_size = {800,700}
    self.left_precent = 0.3
    self:_init_subcribe()
    self.cur_pkg_name = nil
    self.pkg_list = {nil,nil,nil}
    self.selection = {list={},map={}} --pathstr
    self.focus_path_obj = nil
    self.is_directory_cache = {}
    self.cur_project_name = nil
    self.cur_project_data = nil
end

function GuiPackageView:_init_subcribe()
    hub.subscribe(Event.ETE.OpenProject,self.on_project_change,self)
    hub.subscribe(Event.ETE.CloseProject,self.on_project_change,self)
end

function GuiPackageView:on_project_change()
    local project_ins = GuiProjectList:get_ins()
    local p_data = project_ins and project_ins:get_cur_project()
    if p_data then
        self.cur_project_name = p_data.name
        self.cur_project_data = p_data
        self.title_id = string.format("Project - %s###%s",p_data.name,self.GuiName)
    else
        self.cur_project_name = nil
        self.cur_project_data = nil
        self.title_id = string.format("Project - Not Project###%s",self.GuiName)
    end
    self:update_package_list_data(true)
end

function GuiPackageView:on_update(delta)
    local winw,h = windows.GetContentRegionAvail()
    local menu_height = self:_update_menu_bar()
    local fh = cursor.GetFrameHeightWithSpacing()
    h = h - fh - menu_height
    local left_w = math.floor(winw * self.left_precent+0.5)
    cursor.Columns(2)
    cursor.Separator()
    -- if windows.BeginChild("left_part",left_w,h,false,0) then
    if windows.BeginChild("left_part",0,0,false,0) then
        self:on_dir_update()
    end
    windows.EndChild()
    cursor.NextColumn()
    -- windows.PushStyleVar(enum.StyleVar.ItemSpacing,0,0)
    -- widget.InvisibleButton("vsplitter",5,h)
    -- if util.IsItemActive() then
    --     cursor.SetMouseCursor(enum.MouseCursor.ResizeEW)
    --     local new_left_w = left_w + gui_input.get_mouse_delta().x
    --     self.left_precent = new_left_w/winw
    --     self.left_precent = math.min(0.9,self.left_precent)
    --     self.left_precent = math.max(0.1,self.left_precent)
    -- end
    -- if util.IsItemHovered() then
    --     cursor.SetMouseCursor(enum.MouseCursor.ResizeEW)
    -- end
    -- cursor.SameLine()
    -- windows.PopStyleVar()
    -- if windows.BeginChild("right_part",winw-left_w-7,h,false,0) then
    if windows.BeginChild("right_part",0,0,false,0) then
        self:on_file_update(delta)
    end
    windows.EndChild()
    cursor.Columns(1)

end

function GuiPackageView:_update_menu_bar()
    local _,y1 = cursor.GetCursorPos()
    if widget.BeginMenuBar() then
        if widget.MenuItem("New") then
            self:open_new_package_box()
        end
        widget.EndMenuBar()
    end
    local _,y2 = cursor.GetCursorPos()
    return y2-y1
end

local function get_parent_list(path_obj)
    local list = {}
    while ( path_obj:string() ~= "" ) do
        table.insert(list,path_obj)
        path_obj = path_obj:parent_path()
    end
    return list
end

function GuiPackageView:list_directory(path_obj)
    local now = os.clock()
    if path_obj == self.last_call_list_directory_arg then
        if now - self.last_call_list_directory_t < 3 then
            return self.last_call_list_directory_result
        end
    end
    self.is_directory_cache = {}
    self.last_call_list_directory_t = now
    self.last_call_list_directory_arg = path_obj
    local childs =  path_obj:list_directory()
    local result = {}
    for child_obj in childs do
        if child_obj:filename():string() ~= "_build" then
            table.insert(result,child_obj)
        end
    end
    local function cmp_path_obj(a,b)
        return string.lower(a:string())<string.lower(b:string())
    end 
    table.sort(result,cmp_path_obj)
    self.last_call_list_directory_result = result
    return result
end

function GuiPackageView:on_files_refresh()
    self.last_call_list_directory_arg = nil
end

function GuiPackageView:is_directory(path_obj)
    if self.is_directory_cache[path_obj] ~= nil then
        return self.is_directory_cache[path_obj]
    else
        local d = fs.is_directory(path_obj)
        self.is_directory_cache[path_obj] = d
        return d
    end
end

function GuiPackageView:on_dir_update(delta)
    -- if self.pkg_list = 
    self:on_pkglist_update()
    if not self.cur_pkg_name then
        widget.Text("Not package selected.")
        return 
    end

    local root_dir = fs.path("/pkg/"..self.cur_pkg_name)
    if not fs.exists(root_dir) then
        widget.Text("Package not exists:"..self.cur_pkg_name)
    end
    ---
    local cur_dir = root_dir
    --do
    if self:push_open_tree_node(root_dir,true,false) then
        local count = 1
        local is_break = false
        if self.focus_path_obj then
            local foucs_path_tbl = get_parent_list(self.focus_path_obj)
            for i = #foucs_path_tbl-2,1,-1 do
                local open = self:push_open_tree_node(foucs_path_tbl[i],true,false)
                if open then
                    count = count + 1
                else
                    is_break = true
                    break
                end
            end
            cur_dir = foucs_path_tbl[1]
        else
            self.focus_path_obj =  cur_dir
        end

        if not is_break then
            local childs =  self:list_directory(self.focus_path_obj)
            for _,child_obj in ipairs(childs) do
                if self:is_directory(child_obj)then
                    if self:push_open_tree_node(child_obj,true,true) then
                        self:push_tree_end()
                    end
                end
            end
        end
        for i = 1,count do
            self:push_tree_end()
        end
    end
end

function GuiPackageView:on_path_click(path_obj)
    local path_str = path_obj:string()
    local ctrl = gui_input.get_ctrl_state(gui_input.KeyCtrl)
    if ctrl then
        --mult select
        if not self.selection.map[path_str] then
            table.insert(self.selection.list,path_str)
            self.selection.map[path_str] = true
        end
    else
        --single select
        self.selection.list = {path_str}
        local map = self.selection.map
        for k,_ in pairs(map) do
            map[k] = nil
        end
        map[path_str] = true
    end
    hub.publish(Event.ETE.InspectRes,self.selection.list)
end


function GuiPackageView:on_path_double_click(path_obj,is_dir)
    if is_dir then
        self.focus_path_obj = path_obj
        log.info_a("focus_path_obj",self.focus_path_obj)
    else
        log.trace("Double click file",path_obj:string())
        local function get_ext(path_obj)
            local ext = path_obj:extension():string():sub(2):lower()
            return ext
        end
        local _,ext = pcall(get_ext,path_obj)
        log("path ext:",ext)
        local event = FileOpenEvent[ext]
        hub.publish(event,path_obj:string())
    end
end

--return double clicked
function GuiPackageView:push_open_tree_node(path_obj,is_dir,is_leaf)
    local my_path = path_obj:string()
    local my_name = (path_obj:filename()):string()
    local selected = self.selection.map[my_path]
    local flags_tbl = {}
    if seelcted then table.insert(flags_tbl,"Selected") end
    if is_leaf then table.insert(flags_tbl,"Leaf") end
    local my_flag = flags.TreeNode(flags_tbl)
    widget.SetNextItemOpen(true)
    local open = widget.TreeNode(my_name,my_flag)
    local is_click = util.IsItemClicked()
    local is_dclick = is_click and util.IsMouseDoubleClicked(0)
    if is_dclick then
        self:on_path_double_click(path_obj,is_dir)
    elseif is_click then
        self:on_path_click(path_obj)
    end
    return open
end

function GuiPackageView:push_tree_end()
    widget.TreePop()
end

local function get_pkg_list()
    local fs = require "filesystem"
    local res = {}
    for pkg in fs.path('/pkg'):list_directory() do
        res[#res+1] = pkg:filename():string()
    end
    return res
end

function GuiPackageView:update_package_list_data(force)
    self.pkg_update_t = (self.pkg_update_t or 0)+1
    if force or (not self.pkg_list[1]) or (self.pkg_update_t > 160) then
        self.pkg_update_t = 0
        local list = get_pkg_list()
        --todo
        local project_data,project_detail = GuiProjectList:get_ins():get_cur_project()
        local engine_pkgs = {}
        local external_packages = {}
        local inner_packages = {}
        for i,pkg_name in ipairs(list) do
            local pkg_path = fs.path(string.format("/pkg/%s",pkg_name))
            local local_path = pkg_path:localpath():string()
            if string.sub(local_path,1,9) == "packages/" then
                table.insert(engine_pkgs,pkg_name)
            elseif project_detail then
                if project_detail.external_packages[pkg_name] then
                    table.insert(external_packages,pkg_name)
                elseif project_detail.inner_packages[pkg_name] then
                    table.insert(inner_packages,pkg_name)
                end
            end
        end
        table.sort(engine_pkgs)
        table.sort(external_packages)
        self.pkg_list[1] = engine_pkgs
        self.pkg_list[2] = external_packages
        self.pkg_list[3] = inner_packages
    end
end

function GuiPackageView:on_pkglist_update()
    --check pkg list every minute
    self:update_package_list_data(false)
    local engine_pkgs = self.pkg_list[1]
    local external = self.pkg_list[2]
    local inner = self.pkg_list[3]
    if not self.pkg_ui_tbl then
        self.pkg_ui_tbl = {engine_pkgs[1]}
        self.cur_pkg_name = self.pkg_ui_tbl[1]
    end
    local change = false
    local w,h = windows.GetContentRegionAvail()
    cursor.SetNextItemWidth(w)
    if widget.BeginCombo("###PKG_LIST",self.pkg_ui_tbl) then
        if self.cur_project_name then
            if widget.Selectable(string.format("[Project]project"),self.pkg_ui_tbl) then
                change = true
            end
        end
        if inner then
            for i,pname in ipairs(inner) do
                if widget.Selectable(string.format("[Inner]%s",pname),self.pkg_ui_tbl) then
                    change = true
                end
            end
        end
        if external then
            for i,pname in ipairs(external) do
                if widget.Selectable(string.format("[External]%s",pname),self.pkg_ui_tbl) then
                    change = true
                end
            end
        end
        if self.cur_project_name then
            cursor.Spacing()
            cursor.Separator()
            cursor.Spacing()

        end
        for i,pname in ipairs(engine_pkgs) do
            if widget.Selectable(pname,self.pkg_ui_tbl) then
                change = true
            end
        end
        widget.EndCombo()
        if change then
            self.cur_pkg_name = string.match(self.pkg_ui_tbl[1],"([^]]+)$")
            self.focus_path_obj = nil
            log.trace("cur_pkg",self.cur_pkg_name)
        end
    end
    cursor.Separator()
    return change
end

function GuiPackageView:on_file_update(delta)
    if self.focus_path_obj then
        local childs =  self:list_directory(self.focus_path_obj)
        local map = self.selection.map
        for _,child_obj in ipairs(childs) do
            if (not self:is_directory(child_obj)) and(not child_obj:equal_extension(".lk")) then
                local name = (child_obj:filename()):string()
                local click,double_click = nil
                if widget.Selectable(name,map[child_obj:string()]) then
                end
                if util.IsItemClicked(0) and util.IsMouseDoubleClicked(0) then
                    double_click = true
                elseif util.IsItemClicked(0) or util.IsItemClicked(1) then
                    click = true
                end

                if click then
                    self:on_path_click(child_obj,false)
                elseif double_click then
                    self:on_path_double_click(child_obj,false)
                end
                self:show_file_selected_menu(name)
            end
        end
    end
    local dropfiles = gui_input.get_dropfiles()
    if windows.IsWindowHovered() and dropfiles then
        log.info_a("gui_project_view:",dropfiles)
        self:on_dropfiles(dropfiles)
    end
end

function GuiPackageView:show_file_selected_menu(name)
    local open = windows.BeginPopupContextItem("file_selected_menu"..name)
    if open then
        if widget.Button("Delete") then
            for i,path_str in ipairs(self.selection.list) do
                log.info("select",path_str)
                local local_path = gui_util.pkg_path_to_local(path_str,true)
                log.info_a("remove"..local_path,lfs.remove_all(lfs.path(local_path)))
            end
            self:on_files_refresh()
        end
        windows.EndPopup()
    end
end


function GuiPackageView:on_dropfiles(files)
    local cur_pkg = self.cur_pkg_name
    if not cur_pkg then
        log.warning("Select package first!")
        return 
    end
    local focus_path_obj = self.focus_path_obj
    if not focus_path_obj then
        log.warning("Select folder first!")
        return
    end
    local root_dir_obj = fs.path("/pkg/"..self.cur_pkg_name)
    local local_package_root = gui_util.pkg_path_to_local(root_dir_obj,true)
    local root_dir_local_obj = lfs.path(local_package_root)

    local local_folder_str = gui_util.pkg_path_to_local(focus_path_obj,true)
    local local_folder_obj = lfs.path(local_folder_str)

    local function is_in_dir(file_obj,dir_obj)
        file_str = file_obj:string()
        dir_str = dir_obj:string()
        log.info("is_in_dir:",file_str,dir_str)
        local len_dir = #dir_str
        if #file_str>#dir_str then
            if file_str:sub( 1, len_dir ) == dir_str then
                if file_str:sub(len_dir+1,len_dir+1) == "/" or dir_str:sub(len_dir,len_dir) == "/" then
                    return true
                end
            end
        end
    end 
    local function dropfile(file_obj)
        local file_name = file_obj:filename()
        local target_path = local_folder_obj / file_name
        local action = function(result_code)
            if result_code == 2 then
                local raw_name = file_obj:stem()
                local ext_with_dot = file_obj:extension()
                local id = 1
                local new_file = local_folder_obj / string.format( "%s_%d%s", raw_name,id,ext_with_dot)
                while lfs.exists(new_file) do
                    id = id + 1
                    new_file = local_folder_obj / string.format( "%s_%d%s", raw_name,id,ext_with_dot)
                end
                target_path = new_file
            end
            if result_code == 1 or result_code == 2 then
                if is_in_dir(file_obj,root_dir_local_obj) then
                    lfs.rename(file_obj,target_path,true)
                else
                    lfs.copy(file_obj,target_path,true)
                end
            end
            self:on_files_refresh()
        end
        if lfs.exists(target_path) then
            local arg = {
                msg = string.format("File or folder already exist:\"%s\"",
                target_path:string()),
                btn1 = "Overwrite",
                btn2 = "Rename New File",
                title = "Alter",
                close_cb = action,
            }
            gui_util.message(arg)
        else
            action(1)
        end
    end
    for _,file in  ipairs(files) do
        local file_obj = lfs.path(file)
        dropfile(file_obj)
    end
end

local function check_input_args(name_text,location_text,entry_text)
    if #name_text == 0 then
        gui_util.notice({msg="Need to input package name"})
        return false
    end
    if #location_text == 0 then
        gui_util.notice({msg="Need to input package location"})
        return false
    end
    if #entry_text == 0 then
        gui_util.notice({msg="Need to input entry name"})
        return false
    end
    log(name_text,location_text,entry_text)
    return true
end

local function create_package_at(name,location,entry)
    local pm = require "antpm"
    local Editor = require "editor_info"
    local dir_obj = lfs.path(location)
    if lfs.exists(dir_obj) then
        gui_util.notice({msg="create package failed,same name exists"})
        return false
    end

    -- local current_path = lfs.current_path()
    local package_temp_path = fs.path(Editor.PackageFSPath.."/package_temp.lua")
    -- local local_path = package_temp_path:localpath()
    local package_temp_str = nil
    do
        local f = fs.open(package_temp_path,"r")
        package_temp_str = f:read("*a")
        f:close()
    end
    log("f",package_temp_str)
    lfs.create_directory(dir_obj)
    local package_file_path = dir_obj / "package.lua"
    do
        local f = lfs.open(package_file_path,"w")
        f:write(string.format(package_temp_str,{pkg_name = name,pkg_entry=entry}))
        f:close()
    end
    do
        local f = lfs.open(dir_obj/string.format("%s.lua",entry),"w")
        f:write("return {}")
        f:close()
    end
    return true
end

function GuiPackageView:open_new_package_box( )
    local name_tbl = {hint = "package_name" }
    local entry_tbl = {text = "entry",hint="will create {entry}.lua"}
    local project_data = self.cur_project_data
    local _meta_location_in_project = nil
    local location_tbl = {}
    local inside_project = not not project_data
    local function refresh_location_hint()
        if inside_project then
            location_tbl.hint = project_data.path.."/package_dir"
        else
            location_tbl.hint = "./package_dir"
        end
    end
    refresh_location_hint(location_tbl)
    local result = 0
    local function cb()
        local name = tostring(name_tbl.text)
        local location = tostring(location_tbl.text)
        local entry = tostring(entry_tbl.text)
        log("callback name:",name,"location:",location)
        if not check_input_args(name,location,entry) then
            return false
        end
        if inside_project then
            if string.sub(location,1,#(project_data.path))~=project_data.path then
                gui_util.notice({msg="'Inside Project' is choosen,package path mush inside project!"})
                return false
            end
        end
        local success_path = create_package_at(name,location,entry)
        if inside_project then
            local package_relative_path = string.sub(location,#(project_data.path)+2)
            hub.publish(Event.ETE.RequestAddPackageToProject,"inner",package_relative_path)
        else
            hub.publish(Event.ETE.RequestAddPackageToProject,"external",location)
        end
        return success_path
    end

    local function update_func()
        widget.Text("PackageName")
        cursor.SameLine()
        cursor.SetCursorPos(120,nil)
        widget.InputText("##Name",name_tbl)
        widget.Text("Entry      ")
        cursor.SameLine()
        cursor.SetCursorPos(120,nil)
        widget.InputText("##Entry",entry_tbl)
        if project_data then
            widget.Text("In Project  ")
            cursor.SameLine()
            cursor.SetCursorPos(120,nil)
            local change,nv
            log("inside_project",inside_project)
            change,nv = widget.Checkbox("##InProject",inside_project)
            if change then
                inside_project = nv
                refresh_location_hint()
            end
        end
        widget.Text("Location")
        cursor.SameLine()
        cursor.SetCursorPos(120,nil)
        widget.InputText("##Location",location_tbl)
        if widget.Button("Confirm") then
            if cb() then
                windows.CloseCurrentPopup()
            end
        end
        cursor.SameLine()
        if widget.Button("Cancel") then
            windows.CloseCurrentPopup()
        end
    end
    gui_util.popup(update_func,"New Package")
end

return GuiPackageView