-- kobold/ui/mybooks/collections.lua — Kobold
-- Collections on the My Books screen: the collection menus (Manage,
-- Rename, Delete), New collection, and the filter, sort and cover view kept
-- for each collection.
-- Adds methods to the My Books screen class (see mybooks.lua, which
-- installs this with the values it shares).

local ConfirmBox        = require("ui/widget/confirmbox")
local InfoMessage       = require("ui/widget/infomessage")
local InputDialog       = require("ui/widget/inputdialog")
local UIManager         = require("ui/uimanager")
local _                 = require("kobold.l10n")
local KoboldPrefs       = require("kobold.data.prefs")
local KoboldMyBooksData = require("kobold.data.mybooks")

return function(KoboldMyBooks, shared)
    local FILTER_LABELS = shared.FILTER_LABELS
    local SORT_LABELS = shared.SORT_LABELS

    local function readCollection()
        local ok, ReadCollection = pcall(require, "readcollection")
        if ok and ReadCollection and ReadCollection.coll then return ReadCollection end
        return nil
    end

    -- Saves KOReader's collections file. KOReader itself only writes it when its
    -- collections screen closes, so changes made here are written right away.
    local function saveCollections(RC, names)
        pcall(function() RC:write(names) end)
    end


    -- A collection's menu, beside its row with the arrow pointing at it:
    -- Manage, Rename, Delete. KOReader's built-in Favorites cannot be renamed
    -- or deleted, as in KOReader.
    function KoboldMyBooks:showCollectionOptions(group, anchor)
        local RC = readCollection()
        if not RC then return end
        local items = {
            { text = _("Manage"), callback = function() self:manageCollection(group.key) end },
        }
        if group.key ~= RC.default_collection_name then
            items[#items + 1] = { text = _("Rename"), callback = function() self:renameCollection(group) end }
            items[#items + 1] = { text = _("Delete"), callback = function() self:confirmRemoveCollection(group) end }
        end
        require("kobold.ui.menu").show{ items = items, anchor = anchor, place = "right" }
    end

    -- Manage collection panel (collection_manage.lua) for collection `name`.
    -- `create` makes a new collection with that name when saved.
    function KoboldMyBooks:manageCollection(name, create)
        require("kobold.ui.collection_manage").show{
            collection = name, books = self.books, create = create,
            on_done = function(saved)
                self:reload()
                if create then self:openCollection(saved) end
            end,
        }
    end

    -- New collection: the "Create new collection" dialog (a name, Cancel /
    -- Next), then the Manage collection panel to add books; the collection is
    -- created when that is saved.
    function KoboldMyBooks:newCollection()
        local RC = readCollection()
        if not RC or not RC.addCollection then
            UIManager:show(InfoMessage:new{ text = _("KOReader's collections are not available.") })
            return
        end
        local dialog
        dialog = InputDialog:new{
            title = _("Create new collection"),
            input_hint = _("Collection name"),
            buttons = {{
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local name = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                        if name == "" then return end
                        if RC.coll[name] then
                            UIManager:show(InfoMessage:new{
                                text = _("A collection with that name already exists."),
                                timeout = 3,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        self:manageCollection(name, true)
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function KoboldMyBooks:renameCollection(group)
        local RC = readCollection()
        if not RC then return end
        local old = group.key
        local dialog
        dialog = InputDialog:new{
            title = _("Rename collection"),
            input = old,
            input_hint = old,
            buttons = {{
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                        if new == "" or new == old then return end
                        if RC.coll[new] then
                            UIManager:show(InfoMessage:new{
                                text = _("A collection with that name already exists."),
                                timeout = 3,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        RC:renameCollection(old, new)
                        saveCollections(RC, nil)  -- also drops the old name from the file
                        self:scheduleReload()
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function KoboldMyBooks:confirmRemoveCollection(group)
        local RC = readCollection()
        if not RC then return end
        UIManager:show(ConfirmBox:new{
            text = _("Remove collection?") .. "\n\n" .. group.name
                .. "\n\n" .. _("The books stay in your library."),
            ok_text = _("Remove"),
            ok_callback = function()
                RC:removeCollection(group.key)
                saveCollections(RC, nil)
                self:scheduleReload()
            end,
        })
    end

    -- Filter, sort and cover view inside a collection, kept for each collection.
    local COLL_VIEWS_KEY = "coll_views"

    local function collView(name)
        local all = KoboldPrefs.get(COLL_VIEWS_KEY)
        local v = type(all) == "table" and all[name] or nil
        return {
            filter = v and v.filter or "all",
            sort = v and v.sort or "opened_desc",
            view = v and v.view or "list",
        }
    end

    function KoboldMyBooks:setCollView(field, value)
        local name = self.group and self.group.key
        if not name then return end
        local all = KoboldPrefs.get(COLL_VIEWS_KEY)
        all = type(all) == "table" and all or {}
        all[name] = all[name] or {}
        all[name][field] = value
        KoboldPrefs.set(COLL_VIEWS_KEY, all)
        self.page = 1
        self:applyList()
        self:refresh()
    end

    function KoboldMyBooks:collView()
        return collView(self.group and self.group.key or "")
    end

    function KoboldMyBooks:showCollFilterDialog()
        self:showChoiceDialog(_("Filter"), KoboldMyBooksData.FILTERS, self:collView().filter,
            function(id) return FILTER_LABELS[id] end,
            function(id) self:setCollView("filter", id) end)
    end

    function KoboldMyBooks:showCollSortDialog()
        self:showChoiceDialog(_("Sort"), KoboldMyBooksData.SORTS, self:collView().sort,
            function(id) return SORT_LABELS[id].menu end,
            function(id) self:setCollView("sort", id) end)
    end

    -- The "..." on the Collections tab: New collection on the list; Cover view
    -- (or List view) and Manage collection inside a collection.
    function KoboldMyBooks:showCollectionsMenu(anchor)
        local items
        if self.group then
            local grid = self:collView().view == "grid"
            items = {
                { text = grid and _("List view") or _("Cover view"), callback = function()
                    self:setCollView("view", grid and "list" or "grid")
                end },
                { text = _("Manage collection"), callback = function() self:manageCollection(self.group.key) end },
            }
        else
            items = { { text = _("New collection"), callback = function() self:newCollection() end } }
        end
        require("kobold.ui.menu").show{ items = items, anchor = anchor, align = "right" }
    end

    -- Shows collection `name` (by its ReadCollection key) inside the
    -- Collections tab, with the back pill returning to the list.
    function KoboldMyBooks:openCollection(name)
        self.group_page = self.page
        self.group = nil
        for _i, g in ipairs(KoboldMyBooksData.getGroups(self.books, "collections")) do
            if g.key == name then self.group = g break end
        end
        self.page = 1
        self:applyList()
        self:refresh()
    end
end
