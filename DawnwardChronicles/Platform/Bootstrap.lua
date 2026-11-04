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
	return ns.Compat.AddOnMetadata(addonName, field)
end

-- Returns the character's key ("Name-Realm") and, when the name or the
-- realm could not be read (nil, empty, or a secret value), why: such a key
-- ("Unknown-Realm", "Name-") could be shared by other characters, so the
-- session must not write under it (see identityLock).
local function characterKey()
	local Compat = ns.Compat
	local unknown
	local name = Compat.Plain(Compat.Call(UnitName, "player"))
	if type(name) ~= "string" or name == "" then
		name = "Unknown"
		unknown = "this character's name could not be read"
	end
	local realm = Compat.Plain(Compat.Call(GetNormalizedRealmName))
	if type(realm) ~= "string" or realm == "" then
		realm = Compat.Plain(Compat.Call(GetRealmName))
		realm = (type(realm) == "string" and realm or ""):gsub("[%s%-]", "")
	end
	if realm == "" and not unknown then
		unknown = "this character's realm could not be read"
	end
	return name .. "-" .. realm, unknown
end

-- When the character cannot be identified, nothing may be written: another
-- character's record (or Total RP 3 connection) could sit under the same
-- key. The session works on detached copies, read-only, so the saved
-- variables and Total RP 3 stay exactly as they were.
local function identityLock(why)
	local reason = why .. " (Dawnward cannot tell whose data this is)"
	local Util = ns.Util
	ns.store = Store.new(Util.DeepCopy(ns.store.real), Util.DeepCopy(ns.store.sim),
		{ realReadOnly = reason, simReadOnly = reason })
	TRP3Bridge.ledger = Util.DeepCopy(TRP3Bridge.ledger)
	TRP3Bridge.readOnly = TRP3Bridge.readOnly or reason
	return reason
end

local loadInfo
local identityLocked -- why this session cannot write (character not identified), or nil

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
	local key, unknown = characterKey()
	if unknown then
		identityLocked = identityLock(unknown)
	end
	local ctx = {
		store = ns.store,
		characterKey = key,
		now = time,
		print = chatPrint,
		version = addonMetadata("Version") or "?",
		-- The release name a package declares (packaging, tools/package.py):
		-- "1.0.0 Beta" for the Forever package; the version otherwise.
		displayVersion = addonMetadata("X-Display-Version") or addonMetadata("Version") or "?",
		-- Which client the package was built for ("classic" or "forever").
		packageTarget = addonMetadata("X-Dawnward-Target"),
		formatDate = ns.Widgets.FormatDate,
		-- The narrative clock (Core/NarrativeClock.lua, Platform/PlayClock.lua).
		monotonic = ns.PlayClock.Monotonic,
		narrative = ns.NarrativeClock.NewSession(),
		client = Detect.Client(_G, addonName),
		-- What this client lacks (Platform/Compat.lua), for /dawnward status; nil when nothing.
		compatSummary = ns.Compat.Summary,
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
		ShowStoryImport = function() ns.ImportWizard.Open({ from = "chat" }) end,
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
	if identityLocked then
		chatPrint("Saved data is read-only this session: " .. identityLocked .. ". Nothing will be saved or "
			.. "sent to Total RP 3; log in again to retry.")
	end
	if loadInfo.sim.status == "readOnly" then
		chatPrint("Simulation data is read-only this session (" .. loadInfo.sim.reason .. ").")
	end
	if TRP3Bridge.readOnly then
		chatPrint("Total RP 3 sync is paused: " .. TRP3Bridge.readOnly .. ". Its saved data was left untouched.")
	end
	-- Client compatibility (Platform/Detect.lua, Platform/Compat.lua): said
	-- once at login, only when something is off; nothing stops loading.
	local targetWarning = Detect.TargetWarning(ns.ctx and ns.ctx.client)
	if targetWarning then
		chatPrint(targetWarning)
	end
	local missing = ns.Compat.Summary()
	if missing then
		chatPrint(missing .. ". See /dawnward status.")
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
		ns.PlayClock.Init(ns.ctx)
		Events.Init(ns.ctx, MainWindow.Refresh)
		Observers.Init(ns.ctx, function()
			MainWindow.Refresh()
			SafeTime.Schedule(ns.ctx)
		end)
		SafeTime.ShowCard = ns.ReactionCard.Show
		SafeTime.ShownId, SafeTime.SetMore = ns.ReactionCard.ShownId, ns.ReactionCard.SetMore
		ns.ReactionCard.OnClosed = function(id, how) SafeTime.Closed(ns.ctx, id, how) end
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
