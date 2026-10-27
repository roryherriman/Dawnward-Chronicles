-- Character section: the profile fields, family and history, readable at a
-- glance. Deliberately small: it is not a copy of Total RP 3's editor.
local _, ns = ...
local Widgets, MainWindow, Schema, Themes = ns.Widgets, ns.MainWindow, ns.Schema, ns.Themes

local CharacterView = {}
ns.CharacterView = CharacterView

CharacterView.FAMILY_HINT = "Parents, siblings, a lost cousin: anyone your character counts as family."
CharacterView.HISTORY_HINT = "Moments from before the story Dawnward records, in your own words."

local INSET = 8
local LABEL_WIDTH = 110
local VIS_WIDTH = 72
local EDIT_WIDTH = 56
local EMPTY_VALUE = "Not set"

--- Display text for a family member.
function CharacterView.FamilyText(item)
	local relation = item.relation and (item.relation:sub(1, 1):upper() .. item.relation:sub(2)) or "Relative"
	local status = item.status and item.status ~= "unknown" and (" (" .. item.status .. ")") or ""
	return relation .. ": " .. (item.name or "unnamed") .. status
end

function CharacterView.HistoryText(item)
	return (item.when and (item.when .. ": ") or "") .. (item.text or "")
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {} }
	local f = section.frame

	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("CharacterScroll"), f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", INSET, -INSET)
	scroll:SetPoint("BOTTOMRIGHT", -(INSET + 22), INSET)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(100, 100)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child

	local function getRow(index)
		local row = section.rows[index]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, child)
		row.label = Widgets.Label(row, "GameFontNormal", true)
		row.label:SetPoint("TOPLEFT", 4, -4)
		row.value = Widgets.Label(row, "GameFontHighlight", true)
		row.detail = Widgets.Label(row, "GameFontHighlightSmall", true)
		row.visText = Widgets.Label(row, "GameFontHighlightSmall")
		row.visText:SetJustifyH("RIGHT")
		row.visText:SetPoint("TOPRIGHT", -4, -6)
		row.visText:SetWidth(VIS_WIDTH)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.rows[index] = row
		return row
	end

	local function hideExtras(row)
		row.detail:Hide()
		row.visText:Hide()
		if row.vis then row.vis:Hide() end
		if row.edit then row.edit:Hide() end
	end

	-- Kinds: "heading", "field", "item", "hint", "add". Returns the row height.
	local function layoutRow(row, spec, y, width, theme)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.spec = spec
		hideExtras(row)
		local height

		if spec.kind == "heading" or spec.kind == "hint" or spec.kind == "add" then
			row.label:SetWidth(width - 8 - (spec.kind == "add" and EDIT_WIDTH + 8 or 0))
			row.label:SetText(spec.text)
			Widgets.TextColor(row.label, spec.kind == "heading" and theme.accent or theme.muted)
			row.value:Hide()
			height = row.label:GetStringHeight() + (spec.kind == "heading" and 14 or 10)
			if spec.kind == "add" and row.edit then
				row.edit:SetText("Add")
				row.edit:Show()
				height = math.max(height, 26)
			end
		elseif spec.kind == "field" then
			local entry = spec.entry
			row.label:SetWidth(LABEL_WIDTH - 8)
			row.label:SetText(spec.field.label)
			Widgets.TextColor(row.label, theme.accent)
			local valueWidth = width - LABEL_WIDTH - VIS_WIDTH - EDIT_WIDTH - 16
			row.value:Show()
			row.value:ClearAllPoints()
			row.value:SetPoint("TOPLEFT", LABEL_WIDTH, -4)
			row.value:SetWidth(valueWidth)
			row.value:SetText(entry and entry.value or EMPTY_VALUE)
			Widgets.TextColor(row.value, entry and theme.text or theme.muted)
			if section.updateFieldActions then
				section.updateFieldActions(row, spec)
			elseif entry then
				row.visText:Show()
				row.visText:SetText(Themes.VISIBILITY_LABELS[entry.visibility])
				Widgets.TextColor(row.visText, Themes.VISIBILITY_COLORS[entry.visibility])
			end
			height = math.max(row.value:GetStringHeight(), 22) + 10
		else -- item (family member or history entry)
			local item = spec.item
			row.label:SetWidth(width - VIS_WIDTH - 16)
			row.label:SetText(spec.text)
			Widgets.TextColor(row.label, theme.text)
			row.value:Hide()
			if row.vis then
				row.label:SetWidth(width - VIS_WIDTH - EDIT_WIDTH - 16)
				row.vis:Show()
				row.vis:SetLevel(item.visibility)
				row.edit:SetText("Edit")
				row.edit:Show()
			else
				row.visText:Show()
				row.visText:SetText(Themes.VISIBILITY_LABELS[item.visibility])
				Widgets.TextColor(row.visText, Themes.VISIBILITY_COLORS[item.visibility])
			end
			height = math.max(row.label:GetStringHeight() + 8, 26)
			if spec.detail then
				row.detail:Show()
				row.detail:ClearAllPoints()
				row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 12, -2)
				row.detail:SetWidth(width - VIS_WIDTH - 28)
				row.detail:SetText(spec.detail)
				Widgets.TextColor(row.detail, theme.muted)
				height = height + row.detail:GetStringHeight() + 2
			end
		end
		row:SetHeight(height)
		row:Show()
		return height
	end

	--- Rows to show, in order (pure; tested).
	function section.BuildSpecs(char)
		local specs = { { kind = "heading", text = "Profile" } }
		for _, field in ipairs(Schema.FIELDS) do
			specs[#specs + 1] = { kind = "field", field = field, entry = char and char.fields[field.key] }
		end
		specs[#specs + 1] = { kind = "heading", text = "Family" }
		for _, item in ipairs(char and char.family or {}) do
			specs[#specs + 1] = { kind = "item", list = "family", item = item, text = CharacterView.FamilyText(item),
				detail = item.notes }
		end
		specs[#specs + 1] = { kind = "add", list = "family", text = CharacterView.FAMILY_HINT }
		specs[#specs + 1] = { kind = "heading", text = "History" }
		for _, item in ipairs(char and char.history or {}) do
			specs[#specs + 1] = { kind = "item", list = "history", item = item, text = CharacterView.HistoryText(item) }
		end
		specs[#specs + 1] = { kind = "add", list = "history", text = CharacterView.HISTORY_HINT }
		return specs
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		if self.form then self.form:ApplyTheme(theme) end
	end

	function section:RenderList(view)
		local specs = section.BuildSpecs(view.char)
		local width = view.contentWidth - 2 * INSET - 22 -- scroll bar sits inside the right inset
		self.child:SetWidth(width)
		local y = 0
		for i, spec in ipairs(specs) do
			y = y + layoutRow(getRow(i), spec, y, width, view.theme)
		end
		for i = #specs + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.child:SetHeight(math.max(y, 1))
		self.specs = specs
	end

	function section:Refresh(view)
		self.theme = view.theme
		if self.editor:IsShown() then
			self.ThemeEditor(view.theme)
			return
		end
		self:RenderList(view)
	end

	section.getRow = getRow
	CharacterView.AttachEditing(section)
	CharacterView.section = section
	return section
end

--- Editing ---------------------------------------------------------------------

--- Adds per-field Edit and visibility buttons and the field editor.
function CharacterView.AttachEditing(section)
	local f = section.frame
	local Actions = ns.Actions

	function section.decorateRow(row)
		row.vis = Widgets.VisibilityButton(row, function(level)
			local spec, message = row.spec
			if spec.kind == "item" then
				_, message = section.ChangeItem(function(char, now)
					return ns.Character.SetItemVisibility(char, spec.list, spec.item.id, level, now)
				end)
			else
				_, message = Actions.SetFieldVisibility(ns.ctx, spec.field.key, level)
			end
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		row.vis:SetPoint("TOPRIGHT", -2, -2)
		row.edit = Widgets.Button(row, "Edit", EDIT_WIDTH - 4, 20)
		row.edit:SetPoint("TOPRIGHT", -(VIS_WIDTH + 6), -2)
		row.edit:SetScript("OnClick", function()
			local spec = row.spec
			if spec.kind == "field" then
				section:OpenEditor(spec.field)
			else
				section:OpenItemForm(spec.list, spec.item)
			end
		end)
	end

	--- Family and history: one form for adding and editing (#17). -------------

	section.form = ns.Forms.Create(f, MainWindow.ContentWidth())

	function section.ChangeItem(fn)
		return Actions.WithCharacter(ns.ctx, function(char)
			local r, err = fn(char, ns.ctx.now())
			if not r then return Actions.Fail(err) end
			return r, "Saved."
		end)
	end

	local STATUS = { { "unknown", "Unknown" }, { "living", "Living" }, { "deceased", "Deceased" },
		{ "missing", "Missing" } }
	CharacterView.ITEM_FORMS = {
		family = {
			noun = "family member",
			hint = "Only you write this. New entries start private.",
			fields = {
				{ key = "relation", label = "Relation", kind = "line" },
				{ key = "name", label = "Name", kind = "line" },
				{ key = "status", label = "Status", kind = "cycle", values = STATUS },
				{ key = "notes", label = "Notes", kind = "area" },
			},
		},
		history = {
			noun = "history entry",
			hint = "When it happened, in any words (\"as a child\", \"the Third War\"), and what happened. "
				.. "New entries start private.",
			fields = {
				{ key = "when", label = "When", kind = "line" },
				{ key = "text", label = "What happened", kind = "area" },
			},
		},
	}

	-- Saves an edited item field by field; refuses to leave it empty.
	local function updateItem(char, listName, item, values, now)
		local content = false
		for _, field in ipairs(CharacterView.ITEM_FORMS[listName].fields) do
			local v = values[field.key]
			if field.kind ~= "cycle" and type(v) == "string" and v:match("%S") then content = true end
		end
		if not content then return nil, "nothing to save; use Remove to delete it" end
		for _, field in ipairs(CharacterView.ITEM_FORMS[listName].fields) do
			local ok, err = ns.Character.UpdateItem(char, listName, item.id, field.key, values[field.key], now)
			if not ok then return nil, err end
		end
		return item
	end

	function section:OpenItemForm(listName, item)
		local def = CharacterView.ITEM_FORMS[listName]
		local values = {}
		for _, field in ipairs(def.fields) do
			values[field.key] = item and item[field.key]
		end
		self.form:Open({
			title = (item and "Edit " or "Add ") .. def.noun,
			hint = def.hint,
			fields = def.fields,
			values = values,
			deleteLabel = "Remove",
			onDelete = item and function()
				return section.ChangeItem(function(char, now)
					return ns.Character.RemoveItem(char, listName, item.id, now)
				end)
			end or nil,
			onSave = function(v)
				return section.ChangeItem(function(char, now)
					if item then return updateItem(char, listName, item, v, now) end
					return ns.Character.AddItem(char, listName, v, now)
				end)
			end,
		})
	end

	-- Fields always offer Edit; visibility only once a value exists.
	function section.updateFieldActions(row, spec)
		row.edit:Show()
		if spec.entry then
			row.vis:Show()
			row.vis:SetLevel(spec.entry.visibility)
		else
			row.vis:Hide()
		end
	end

	local editor = CreateFrame("Frame", nil, f)
	editor:SetAllPoints(f)
	editor:Hide()
	section.editor = editor

	editor.heading = Widgets.Label(editor, "GameFontNormalLarge")
	editor.heading:SetPoint("TOPLEFT", INSET, -10)
	editor.hint = Widgets.Label(editor, "GameFontHighlightSmall", true)
	editor.hint:SetPoint("TOPLEFT", INSET, -36)
	editor.hint:SetWidth(540)

	editor.line = Widgets.EditLine(editor, 101)
	editor.line:SetPoint("TOPLEFT", INSET + 6, -64)
	editor.line:SetPoint("TOPRIGHT", -INSET, -64)
	editor.area = Widgets.TextArea(editor, 2001, MainWindow.ContentWidth() - 2 * INSET)
	editor.area.frame:SetPoint("TOPLEFT", INSET, -64)
	editor.area.frame:SetPoint("BOTTOMRIGHT", -INSET, 44)

	editor.cancel = Widgets.Button(editor, "Cancel", 90, 22)
	editor.cancel:SetPoint("BOTTOMRIGHT", -INSET, 12)
	editor.save = Widgets.Button(editor, "Save", 90, 22)
	editor.save:SetPoint("RIGHT", editor.cancel, "LEFT", -6, 0)
	editor.clear = Widgets.Button(editor, "Clear", 90, 22)
	editor.clear:SetPoint("BOTTOMLEFT", INSET, 12)

	function section.ThemeEditor(theme)
		Widgets.TextColor(editor.heading, theme.accent)
		Widgets.TextColor(editor.hint, theme.muted)
		Widgets.SetColor(editor.area.well, { 0, 0, 0 })
		editor.area.edit:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
		editor.line:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
	end

	local function input()
		return editor.field.kind == "long" and editor.area.edit or editor.line
	end

	function section:OpenEditor(field)
		local char = Actions.Character(ns.ctx)
		local entry = char and char.fields[field.key]
		editor.field = field
		editor.heading:SetText(field.label)
		editor.hint:SetText(field.kind == "long"
			and "A few sentences are plenty. New fields start private; change visibility from the list."
			or "One line. New fields start private; change visibility from the list.")
		local long = field.kind == "long"
		editor.area.frame:SetShown(long)
		editor.line:SetShown(not long)
		editor.clear:SetShown(entry ~= nil)
		input():SetText(entry and entry.value or "")
		section.scroll:Hide()
		editor:Show()
		if self.theme then
			self.ThemeEditor(self.theme)
		end
		input():SetFocus()
		MainWindow.SetStatus("")
	end

	function section.CloseEditor()
		editor:Hide()
		editor.line:ClearFocus()
		editor.area.edit:ClearFocus()
		section.scroll:Show()
		MainWindow.Refresh()
	end

	function section.SaveEditor()
		local ok, message = Actions.SetField(ns.ctx, editor.field.key, input():GetText())
		if ok then
			section.CloseEditor()
		end
		MainWindow.SetStatus(message)
	end

	function section.ConfirmClear()
		local field = editor.field
		Widgets.Confirm("Clear " .. field.label .. "?\n\nThis removes the saved value.", "Clear", function()
			local _, message = Actions.ClearField(ns.ctx, field.key)
			section.CloseEditor()
			MainWindow.SetStatus(message)
		end)
	end

	editor.save:SetScript("OnClick", section.SaveEditor)
	editor.cancel:SetScript("OnClick", section.CloseEditor)
	editor.clear:SetScript("OnClick", section.ConfirmClear)
	editor.line:SetScript("OnEnterPressed", section.SaveEditor)
end

MainWindow.RegisterSection({ id = "character", label = "Character", order = 2, create = create })
