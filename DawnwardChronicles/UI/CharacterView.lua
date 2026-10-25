-- Character section: the profile fields, family and history, readable at a
-- glance. Deliberately small: it is not a copy of Total RP 3's editor.
local _, ns = ...
local Widgets, MainWindow, Schema, Themes = ns.Widgets, ns.MainWindow, ns.Schema, ns.Themes

local CharacterView = {}
ns.CharacterView = CharacterView

CharacterView.FAMILY_HINT = "Add or change family with /dawnward family (see /dawnward help)."
CharacterView.HISTORY_HINT = "Add or change history with /dawnward history (see /dawnward help)."

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

	-- Kinds: "heading", "field", "item", "hint". Returns the row height.
	local function layoutRow(row, spec, y, width, theme)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.spec = spec
		hideExtras(row)
		local height

		if spec.kind == "heading" or spec.kind == "hint" then
			row.label:SetWidth(width - 8)
			row.label:SetText(spec.text)
			Widgets.TextColor(row.label, spec.kind == "heading" and theme.accent or theme.muted)
			row.value:Hide()
			height = row.label:GetStringHeight() + (spec.kind == "heading" and 14 or 10)
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
			row.visText:Show()
			row.visText:SetText(Themes.VISIBILITY_LABELS[item.visibility])
			Widgets.TextColor(row.visText, Themes.VISIBILITY_COLORS[item.visibility])
			height = row.label:GetStringHeight() + 8
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
			specs[#specs + 1] = { kind = "item", item = item, text = CharacterView.FamilyText(item), detail = item.notes }
		end
		specs[#specs + 1] = { kind = "hint", text = CharacterView.FAMILY_HINT }
		specs[#specs + 1] = { kind = "heading", text = "History" }
		for _, item in ipairs(char and char.history or {}) do
			specs[#specs + 1] = { kind = "item", item = item, text = CharacterView.HistoryText(item) }
		end
		specs[#specs + 1] = { kind = "hint", text = CharacterView.HISTORY_HINT }
		return specs
	end

	function section:ApplyTheme(theme)
		self.theme = theme
	end

	function section:RenderList(view)
		local specs = section.BuildSpecs(view.char)
		local width = math.max(200, self.scroll:GetWidth())
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
		self:RenderList(view)
	end

	section.getRow = getRow
	CharacterView.section = section
	return section
end

MainWindow.RegisterSection({ id = "character", label = "Character", order = 2, create = create })
