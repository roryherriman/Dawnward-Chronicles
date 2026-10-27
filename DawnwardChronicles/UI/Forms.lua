-- A small form panel shared by the sections, so common actions (adding a
-- memory, editing a goal, naming a family member) never need a slash
-- command. It covers its section while open and blocks clicks beneath.
--
-- form:Open({
--   title, hint,
--   fields = { { key, label, kind = "line" | "area" | "cycle" | "number",
--                values = { {value, label}, ... } (cycle), max = bytes } },
--   values = { key = current value },
--   onSave = function(values) return ok, message end,   -- ok closes the form
--   onDelete = function() return ok, message end,       -- optional, confirmed
--   deleteLabel = "Remove",
-- })
local _, ns = ...
local Widgets, MainWindow = ns.Widgets, ns.MainWindow

local Forms = {}
ns.Forms = Forms

local INSET = 10
local LABEL_WIDTH = 120
local LINE_HEIGHT = 30
local AREA_HEIGHT = 74
Forms.MAX_FIELDS = 7

--- Next value in a cycle field (pure; tested).
function Forms.NextValue(field, value)
	for i, v in ipairs(field.values) do
		if v[1] == value then
			return field.values[i % #field.values + 1][1]
		end
	end
	return field.values[1][1]
end

function Forms.LabelOf(field, value)
	for _, v in ipairs(field.values or {}) do
		if v[1] == value then return v[2] end
	end
	return tostring(value)
end

function Forms.Create(parent, width)
	local form = { rows = {} }
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	if f.SetFrameLevel and parent.GetFrameLevel then
		f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	end
	if f.EnableMouse then f:EnableMouse(true) end
	f:Hide()
	form.frame = f
	form.background = Widgets.Solid(f, "BACKGROUND")
	form.background:SetAllPoints(f)
	width = width or 560

	form.title = Widgets.Label(f, "GameFontNormalLarge")
	form.title:SetPoint("TOPLEFT", INSET, -8)
	form.hint = Widgets.Label(f, "GameFontHighlightSmall", true)
	form.hint:SetPoint("TOPLEFT", INSET, -32)
	form.hint:SetWidth(width - 2 * INSET)
	form.message = Widgets.Label(f, "GameFontHighlightSmall", true)
	form.message:SetPoint("BOTTOMLEFT", INSET, 40)
	form.message:SetWidth(width - 2 * INSET)

	for i = 1, Forms.MAX_FIELDS do
		local row = { }
		row.label = Widgets.Label(f, "GameFontNormal")
		row.label:SetWidth(LABEL_WIDTH - 8)
		row.line = Widgets.EditLine(f, 300)
		row.line:SetWidth(width - LABEL_WIDTH - 2 * INSET - 6)
		row.area = Widgets.TextArea(f, 1000, width - LABEL_WIDTH - 2 * INSET)
		row.cycle = Widgets.Button(f, "", width - LABEL_WIDTH - 2 * INSET, 22)
		row.cycle:SetScript("OnClick", function(self)
			row.value = Forms.NextValue(row.field, row.value)
			self:SetText(Forms.LabelOf(row.field, row.value))
		end)
		form.rows[i] = row
	end

	form.cancel = Widgets.Button(f, "Cancel", 90, 22)
	form.cancel:SetPoint("BOTTOMRIGHT", -INSET, 10)
	form.save = Widgets.Button(f, "Save", 90, 22)
	form.save:SetPoint("RIGHT", form.cancel, "LEFT", -6, 0)
	form.delete = Widgets.Button(f, "Remove", 90, 22)
	form.delete:SetPoint("BOTTOMLEFT", INSET, 10)

	local function layout()
		local y = 56
		for i, row in ipairs(form.rows) do
			local field = form.spec.fields[i]
			row.field = field
			local shown = field ~= nil
			row.label:SetShown(shown)
			row.line:SetShown(shown and (field.kind == "line" or field.kind == "number"))
			row.area.frame:SetShown(shown and field.kind == "area")
			row.cycle:SetShown(shown and field.kind == "cycle")
			if shown then
				local value = form.spec.values and form.spec.values[field.key]
				row.label:SetText(field.label)
				row.label:ClearAllPoints()
				row.label:SetPoint("TOPLEFT", INSET, -(y + 4))
				if field.kind == "area" then
					row.area.frame:ClearAllPoints()
					row.area.frame:SetPoint("TOPLEFT", INSET + LABEL_WIDTH, -y)
					row.area.frame:SetPoint("TOPRIGHT", -INSET, -y)
					row.area.frame:SetHeight(AREA_HEIGHT)
					row.area.edit:SetText(value and tostring(value) or "")
					y = y + AREA_HEIGHT + 8
				elseif field.kind == "cycle" then
					row.value = value ~= nil and value or field.values[1][1]
					row.cycle:ClearAllPoints()
					row.cycle:SetPoint("TOPLEFT", INSET + LABEL_WIDTH, -y)
					row.cycle:SetText(Forms.LabelOf(field, row.value))
					y = y + LINE_HEIGHT
				else
					row.line:ClearAllPoints()
					row.line:SetPoint("TOPLEFT", INSET + LABEL_WIDTH + 6, -y)
					row.line:SetText(value and tostring(value) or "")
					y = y + LINE_HEIGHT
				end
			end
		end
	end

	--- Current values of the open form.
	function form:Values()
		local out = {}
		for _, row in ipairs(self.rows) do
			local field = row.field
			if field then
				if field.kind == "area" then
					out[field.key] = row.area.edit:GetText()
				elseif field.kind == "cycle" then
					out[field.key] = row.value
				elseif field.kind == "number" then
					out[field.key] = tonumber(row.line:GetText())
				else
					out[field.key] = row.line:GetText()
				end
			end
		end
		return out
	end

	function form:Open(spec)
		assert(#spec.fields <= Forms.MAX_FIELDS, "too many form fields")
		self.spec = spec
		self.title:SetText(spec.title or "")
		self.hint:SetText(spec.hint or "")
		self.message:SetText("")
		self.delete:SetShown(spec.onDelete ~= nil)
		self.delete:SetText(spec.deleteLabel or "Remove")
		layout()
		f:Show()
		local first = self.rows[1]
		if first.field and (first.field.kind == "line" or first.field.kind == "number") then
			first.line:SetFocus()
		end
	end

	function form:Close()
		for _, row in ipairs(self.rows) do
			row.line:ClearFocus()
			row.area.edit:ClearFocus()
		end
		f:Hide()
		MainWindow.Refresh()
	end

	function form.IsOpen()
		return f:IsShown()
	end

	function form:Save()
		local ok, message = self.spec.onSave(self:Values())
		MainWindow.SetStatus(message)
		if ok then
			self:Close()
		else
			self.message:SetText(message or "Not saved.")
		end
		return ok
	end

	function form:ApplyTheme(theme)
		Widgets.SetColor(self.background, theme.panel)
		Widgets.TextColor(self.title, theme.accent)
		Widgets.TextColor(self.hint, theme.muted)
		Widgets.TextColor(self.message, theme.accent)
		for _, row in ipairs(self.rows) do
			Widgets.TextColor(row.label, theme.accent)
			Widgets.SetColor(row.area.well, { 0, 0, 0 })
			row.area.edit:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
			row.line:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
		end
	end

	form.save:SetScript("OnClick", function() form:Save() end)
	form.cancel:SetScript("OnClick", function() form:Close() end)
	form.delete:SetScript("OnClick", function()
		Widgets.Confirm((form.spec.title or "This record") .. ": remove it?", form.spec.deleteLabel or "Remove",
			function()
				local ok, message = form.spec.onDelete()
				MainWindow.SetStatus(message)
				if ok then form:Close() end
			end)
	end)
	return form
end
