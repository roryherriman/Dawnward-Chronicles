-- A small form panel shared by the sections, so common actions (adding a
-- memory, editing a goal, naming a family member) never need a slash
-- command. It covers its section while open and blocks clicks beneath.
--
-- form:Open({
--   title, hint,
--   fields = { { key, label, kind = "line" | "area" | "cycle" | "number",
--                values = { {value, label}, ... } (cycle), max = bytes,
--                errors = { "text", ... } } },   -- refusals that belong to this field
--   values = { key = current value },
--   onSave = function(values) return ok, message end,   -- ok closes the form
--   locate = function(values, message) return key end,  -- optional: the field a refusal concerns
--   onDelete = function() return ok, message end,       -- optional, confirmed
--   deleteLabel = "Remove",
-- })
--
-- Keyboard (Widgets.FocusChain): opening focuses the first editable field;
-- Tab / Shift+Tab move between editable fields; Enter moves on, and on the
-- last one-line field saves; Escape cancels, asking first if anything was
-- typed. Multi-line fields keep Enter for new lines.
--
-- Validation (Widgets.FieldError): the rules stay in the core. When a save
-- is refused, the message is shown under the field it concerns (matched by
-- the field's `errors` texts, else the first editable field), that field is
-- highlighted and focused, everything typed is kept, and the form stays
-- open. Number fields also check that what was typed is a number. An error
-- clears as soon as its field is changed.
local _, ns = ...
local Widgets, MainWindow, Style = ns.Widgets, ns.MainWindow, ns.Style

local Forms = {}
ns.Forms = Forms

local INSET = 10
local LABEL_WIDTH = 120
local LINE_HEIGHT = 30
local AREA_HEIGHT = 74
Forms.MAX_FIELDS = 7
-- Default input limits in bytes; a field's own max (its stored limit)
-- replaces them, so editing never cuts saved text short.
Forms.LINE_MAX = 300
Forms.AREA_MAX = 2000
Forms.NOT_A_NUMBER = "Enter a whole number, or leave it empty"

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

--- Index of the field a refusal message belongs to, or nil. Pure.
function Forms.FieldFor(fields, message)
	local lower = tostring(message or ""):lower()
	for i, field in ipairs(fields) do
		for _, text in ipairs(field.errors or {}) do
			if lower:find(text:lower(), 1, true) then return i end
		end
	end
	return nil
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
	form.background = Style.Fill(f, "panel", "BACKGROUND")
	form.background:SetAllPoints(f)
	width = width or 560
	local inputWidth = width - LABEL_WIDTH - 2 * INSET

	form.title = Widgets.Label(f, "GameFontNormalLarge", false, "title")
	form.title:SetPoint("TOPLEFT", INSET, -8)
	form.hint = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	form.hint:SetPoint("TOPLEFT", INSET, -32)
	form.hint:SetWidth(width - 2 * INSET)

	local relayout -- set below; repositions the rows when an error appears or clears
	for i = 1, Forms.MAX_FIELDS do
		local row = { }
		row.label = Widgets.Label(f, "GameFontNormal", false, "muted")
		row.label:SetWidth(LABEL_WIDTH - 8)
		row.line = Widgets.EditLine(f, 300)
		row.line:SetWidth(inputWidth - 6)
		row.area = Widgets.TextArea(f, 1000, inputWidth)
		row.cycle = Widgets.Button(f, "", inputWidth, 22, "choice")
		row.cycle:SetScript("OnClick", function(self)
			row.value = Forms.NextValue(row.field, row.value)
			self:SetText(Forms.LabelOf(row.field, row.value))
		end)
		Widgets.FieldError(row.line, inputWidth - 6)
		Widgets.FieldError(row.area.edit, inputWidth)
		row.line.onErrorChanged = function() relayout() end
		row.area.edit.onErrorChanged = function() relayout() end
		form.rows[i] = row
	end

	form.cancel = Widgets.Button(f, "Cancel", 90, 22)
	form.cancel:SetPoint("BOTTOMRIGHT", -INSET, 10)
	form.save = Widgets.Button(f, "Save", 90, 22, "primary")
	form.save:SetPoint("RIGHT", form.cancel, "LEFT", -6, 0)
	form.delete = Widgets.Button(f, "Remove", 90, 22, "danger")
	form.delete:SetPoint("BOTTOMLEFT", INSET, 10)

	-- The editable input of a row (nil for a cycle or an unused row).
	local function inputOf(row)
		local field = row.field
		if not field then return nil end
		if field.kind == "area" then return row.area.edit end
		if field.kind == "line" or field.kind == "number" then return row.line end
		return nil
	end
	form.InputOf = inputOf

	-- Positions every row; fill also loads the spec's values (on Open only,
	-- so a relayout never touches what the player typed).
	local function layout(fill)
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
					if fill then
						-- SetMaxBytes counts the terminating byte.
						row.area.edit:SetMaxBytes((field.max or Forms.AREA_MAX) + 1)
						row.area.edit:SetText(value and tostring(value) or "")
					end
					y = y + AREA_HEIGHT + 8 + Widgets.ErrorHeight(row.area.edit)
				elseif field.kind == "cycle" then
					if fill then
						row.value = value ~= nil and value or field.values[1][1]
						row.cycle:SetText(Forms.LabelOf(field, row.value))
					end
					row.cycle:ClearAllPoints()
					row.cycle:SetPoint("TOPLEFT", INSET + LABEL_WIDTH, -y)
					y = y + LINE_HEIGHT
				else
					row.line:ClearAllPoints()
					row.line:SetPoint("TOPLEFT", INSET + LABEL_WIDTH + 6, -y)
					if fill then
						row.line:SetMaxBytes((field.max or Forms.LINE_MAX) + 1)
						row.line:SetText(value and tostring(value) or "")
					end
					y = y + LINE_HEIGHT + Widgets.ErrorHeight(row.line)
				end
			end
		end
		form.contentBottom = y
	end
	relayout = function()
		if form.spec then layout(false) end
	end

	local function clearErrors()
		for _, row in ipairs(form.rows) do
			if row.line.invalid then Widgets.SetFieldError(row.line, nil) end
			if row.area.edit.invalid then Widgets.SetFieldError(row.area.edit, nil) end
		end
	end

	form.chain = Widgets.FocusChain({
		onSubmit = function() form:Save() end,
		onEscape = function(dirty) form.chain.ConfirmDiscard(dirty, function() form:Close() end) end,
	})

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

	--- Shows message under field i (or the first editable field), focuses it.
	function form:ShowError(i, message)
		local row = i and self.rows[i]
		local input = row and inputOf(row)
		if not input then
			for _, r in ipairs(self.rows) do
				input = inputOf(r)
				if input then break end
			end
		end
		if input then
			Widgets.SetFieldError(input, message)
			input:SetFocus()
		end
		return input
	end

	function form:Open(spec)
		assert(#spec.fields <= Forms.MAX_FIELDS, "too many form fields")
		self.spec = spec
		self.title:SetText(spec.title or "")
		self.hint:SetText(spec.hint or "")
		clearErrors()
		self.delete:SetShown(spec.onDelete ~= nil)
		self.delete:SetText(spec.deleteLabel or "Remove")
		layout(true)
		f:Show()
		local inputs = {}
		for _, row in ipairs(self.rows) do
			inputs[#inputs + 1] = inputOf(row)
		end
		self.chain.SetFields(inputs)
		self.chain.FocusFirst()
	end

	function form:Close()
		for _, row in ipairs(self.rows) do
			row.line:ClearFocus()
			row.area.edit:ClearFocus()
		end
		clearErrors()
		f:Hide()
		MainWindow.Refresh()
	end

	function form.IsOpen()
		return f:IsShown()
	end

	--- Saves, or shows why not beside the field concerned (form stays open,
	-- nothing typed is lost). Returns ok.
	function form:Save()
		clearErrors()
		-- Number fields: what was typed must be a number (empty is allowed).
		for i, row in ipairs(self.rows) do
			local field = row.field
			if field and field.kind == "number" then
				local text = row.line:GetText() or ""
				if text:match("%S") and not tonumber(text) then
					self:ShowError(i, Forms.NOT_A_NUMBER)
					return false
				end
			end
		end
		local values = self:Values()
		local ok, message = self.spec.onSave(values)
		if ok then
			MainWindow.SetStatus(message)
			self:Close()
		else
			local index = Forms.FieldFor(self.spec.fields, message)
			local key = self.spec.locate and self.spec.locate(values, message)
			for i, field in ipairs(self.spec.fields) do
				if key and field.key == key then index = i end
			end
			self:ShowError(index, message or "Not saved.")
		end
		return ok
	end

	-- Every part paints itself (UI/Style.lua); kept for callers.
	function form.ApplyTheme() end

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
