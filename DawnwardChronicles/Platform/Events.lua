-- Observes game events and turns them into journal milestones.
-- Event-driven only: one frame, registered for the events in HANDLERS.
--
-- To add a milestone later (quests, discoveries): register a type in
-- Core/Milestones.lua and add a handler here that gathers its data.
local _, ns = ...
local Actions = ns.Actions

local Events = {}
ns.Events = Events

--- Current zone and subzone names (nil when the client has none).
function Events.Location()
	local zone = GetRealZoneText and GetRealZoneText() or nil
	local subzone = GetSubZoneText and GetSubZoneText() or nil
	if zone == "" then zone = nil end
	if subzone == "" then subzone = nil end
	return zone, subzone
end

Events.HANDLERS = {
	-- PLAYER_LEVEL_UP: arg1 is the new level.
	PLAYER_LEVEL_UP = function(level)
		local zone, subzone = Events.Location()
		return "levelup", { level = level, zone = zone, subzone = subzone, source = "PLAYER_LEVEL_UP" }
	end,
}

local warnedReadOnly = false

--- Records a milestone and reports it. Duplicates are ignored quietly.
-- onRecorded(entry) lets the window refresh.
function Events.Handle(ctx, event, onRecorded, ...)
	local handler = Events.HANDLERS[event]
	if not handler then
		return nil
	end
	local typeName, data = handler(...)
	local entry, message = Actions.RecordRealMilestone(ctx, typeName, data)
	if entry then
		ctx.print(message)
		if onRecorded then
			onRecorded(entry)
		end
	elseif message ~= "duplicate" and message ~= "invalid level" then
		if message == "saved data is read-only" then
			if not warnedReadOnly then
				warnedReadOnly = true
				ctx.print("A milestone was not recorded because saved data is read-only this session.")
			end
		else
			ctx.print("Milestone not recorded: " .. tostring(message))
		end
	end
	return entry
end

function Events.Init(ctx, onRecorded)
	local frame = CreateFrame("Frame")
	for event in pairs(Events.HANDLERS) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		Events.Handle(ctx, event, onRecorded, ...)
	end)
	Events.frame = frame
	return frame
end
