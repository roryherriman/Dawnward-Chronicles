-- Connects the core to the WoW client: saved variables, events and /dawnward.
-- Loaded last. Event-driven only; nothing polls.
local addonName, ns = ...
local Migrations, Store, Commands, Detect, CopyBox, TRP3Status, MainWindow, Events, TRP3Bridge, Observers, SafeTime =
	ns.Migrations, ns.Store, ns.Commands, ns.Detect, ns.CopyBox, ns.TRP3Status, ns.MainWindow, ns.Events,
	ns.TRP3Bridge, ns.Observers, ns.SafeTime

local PREFIX = "|cffe6c35cDawnward:|r "

local function chatPrint(line)
	-- Escape pipes so no text (player-entered or from errors) is read as UI markup.
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(line):gsub("|", "||"))
end

local function addonMetadata(field)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return get and get(addonName, field) or nil
end

local function characterKey()
	local name = UnitName("player") or "Unknown"
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if not realm or realm == "" then
		realm = (GetRealmName() or ""):gsub("[%s%-]", "")
	end
	return name .. "-" .. realm
end

local loadInfo

local function loadSavedVariables()
	local realDB, realInfo = Migrations.Load(DawnwardChroniclesDB)
	local simDB, simInfo = Migrations.Load(DawnwardChroniclesSimDB)
	-- Read-only data stays exactly as saved: the globals are only replaced
	-- when loading succeeded, and the in-memory copy refuses writes.
	if realInfo.status ~= "readOnly" then
		DawnwardChroniclesDB = realDB
	end
	if simInfo.status ~= "readOnly" then
		DawnwardChroniclesSimDB = simDB
	end
	loadInfo = { real = realInfo, sim = simInfo }
	TRP3Bridge.Load()
	ns.store = Store.new(realDB, simDB, {
		realReadOnly = realInfo.status == "readOnly" and realInfo.reason or nil,
		simReadOnly = simInfo.status == "readOnly" and simInfo.reason or nil,
	})
end

local function buildContext()
	local ctx = {
		store = ns.store,
		characterKey = characterKey(),
		now = time,
		print = chatPrint,
		version = addonMetadata("Version") or "?",
		formatDate = ns.Widgets.FormatDate,
		client = Detect.Client(_G),
		trp3Status = function()
			return TRP3Status.Read(_G)
		end,
		zone = function()
			return (Events.Location())
		end,
		-- Full location (zone, subzone, map, area, client), for diagnostics.
		location = function()
			return ns.Observers.Location()
		end,
	}
	ctx.ui = {
		ShowExport = CopyBox.ShowExport,
		ShowImport = function()
			CopyBox.ShowImport(
				function(text) return Commands.StageImport(ctx, text) end,
				function()
					Commands.Execute(ctx, "import confirm")
					MainWindow.Refresh()
				end,
				function() ctx.pendingImport = nil end
			)
		end,
		ToggleJournal = MainWindow.Toggle,
		ShowGuide = function() ns.GuidePanel.Open(1) end,
		ShowSetup = function(opts) ns.SetupWizard.Open(opts) end,
		ShowStory = function()
			if not MainWindow.IsShown() then MainWindow.Show() end
			MainWindow.Select("story")
		end,
	}
	return ctx
end

local function announceLoad()
	if loadInfo.real.status == "readOnly" then
		chatPrint("Saved data could not be loaded safely (" .. loadInfo.real.reason
			.. "). It has been left untouched and Dawnward is read-only this session.")
	elseif loadInfo.real.status == "migrated" then
		chatPrint("Saved data upgraded from schema " .. tostring(loadInfo.real.from) .. ".")
	end
	if loadInfo.real.notes and #loadInfo.real.notes > 0 then
		chatPrint(#loadInfo.real.notes .. " saved-data issue(s) were repaired on load.")
	end
	if loadInfo.sim.status == "readOnly" then
		chatPrint("Simulation data is read-only this session (" .. loadInfo.sim.reason .. ").")
	end
	if TRP3Bridge.readOnly then
		chatPrint("Total RP 3 sync is paused: " .. TRP3Bridge.readOnly .. ". Its saved data was left untouched.")
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		self:UnregisterEvent("ADDON_LOADED")
		loadSavedVariables()
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if not ns.store then
			-- ADDON_LOADED always precedes PLAYER_LOGIN; guard against surprises anyway.
			loadSavedVariables()
		end
		ns.ctx = buildContext()
		Events.Init(ns.ctx, MainWindow.Refresh)
		Observers.Init(ns.ctx, function()
			MainWindow.Refresh()
			SafeTime.Schedule(ns.ctx)
		end)
		SafeTime.ShowCard = ns.ReactionCard.Show
		SafeTime.Init(ns.ctx)
		TRP3Bridge.Attach(ns.ctx)
		ns.MinimapButton.Init(ns.ctx)
		announceLoad()
	end
end)

SLASH_DAWNWARD1 = "/dawnward"
SLASH_DAWNWARD2 = "/dwc"
SlashCmdList.DAWNWARD = function(message)
	if not ns.ctx then
		chatPrint("Still loading - try again in a moment.")
		return
	end
	Commands.Execute(ns.ctx, message)
	-- Commands may change data the open journal is showing, or the public
	-- facts an opted-in TRP3 profile mirrors.
	MainWindow.Refresh()
	TRP3Bridge.Request()
end
