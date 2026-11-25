-- TemucraftThreat: threat bars for your group on the current target (3.3.5a).
-- Uses the client's own threat numbers (UnitDetailedThreatSituation), so no addon comms are needed.

local addonName = ...
local floor, format, sort, wipe, pairs, ipairs, max = math.floor, string.format, table.sort, wipe, pairs, ipairs, math.max

local defaults = {
	locked = false,
	scale = 1,
	width = 220,
	bars = 8,
	barHeight = 16,
	alpha = 0.9,
	hideOutOfCombat = true,
	onlyInGroup = false,
	warn = true,
	warnAt = 90,
	warnSound = true,
	showPets = true,
	point = { "CENTER", "UIParent", "CENTER", 300, -100 },
}

local db
local frame, header, bars = nil, nil, {}
local list, pool = {}, {}
local warned = false
local elapsed = 0

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function shortNumber(n)
	if n >= 1000000 then return format("%.1fm", n / 1000000) end
	if n >= 1000 then return format("%.1fk", n / 1000) end
	return tostring(floor(n))
end

-- The mob whose threat we show: your target, or your target's target when you target a friend.
local function threatTarget()
	if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then return "target" end
	if UnitExists("targettarget") and UnitCanAttack("player", "targettarget") and not UnitIsDead("targettarget") then return "targettarget" end
end

local function classColor(unit)
	local _, class = UnitClass(unit)
	local c = class and RAID_CLASS_COLORS[class]
	if c and UnitIsPlayer(unit) then return c.r, c.g, c.b end
	return 0.5, 0.5, 0.5
end

local function addUnit(unit, mob)
	if not UnitExists(unit) then return end
	local isTanking, status, scaled, raw, value = UnitDetailedThreatSituation(unit, mob)
	if not value or value <= 0 then return end
	local e = tremove(pool) or {}
	e.unit, e.name, e.tanking, e.status, e.scaled, e.value = unit, UnitName(unit), isTanking, status or 0, scaled or 0, value / 100
	list[#list + 1] = e
end

local function byValue(a, b) return a.value > b.value end

local function collect(mob)
	for _, e in ipairs(list) do pool[#pool + 1] = e end
	wipe(list)
	local raid = GetNumRaidMembers()
	if raid > 0 then
		for i = 1, raid do
			addUnit("raid" .. i, mob)
			if db.showPets then addUnit("raidpet" .. i, mob) end
		end
	else
		addUnit("player", mob)
		if db.showPets then addUnit("pet", mob) end
		for i = 1, GetNumPartyMembers() do
			addUnit("party" .. i, mob)
			if db.showPets then addUnit("partypet" .. i, mob) end
		end
	end
	sort(list, byValue)
end

local function tankValue()
	for _, e in ipairs(list) do if e.tanking then return e.value end end
	return list[1] and list[1].value or 0
end

local function updateWarning()
	if not db.warn then return end
	local mine
	for _, e in ipairs(list) do if UnitIsUnit(e.unit, "player") then mine = e break end end
	local danger = mine and not mine.tanking and mine.scaled >= db.warnAt
	if danger and not warned then
		warned = true
		if db.warnSound then PlaySoundFile("Sound\\Interface\\RaidWarning.wav") end
		RaidNotice_AddMessage(RaidWarningFrame, format("|cffff4040Threat %d%%|r", floor(mine.scaled)), ChatTypeInfo.RAID_WARNING)
	elseif not danger and warned and (not mine or mine.scaled < db.warnAt - 10 or mine.tanking) then
		warned = false
	end
end

local function shouldShow(mob)
	if db.onlyInGroup and GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then return false end
	if db.hideOutOfCombat and not InCombatLockdown() and not UnitAffectingCombat("player") then return false end
	return mob ~= nil
end

local lastRender = 0
local function render()
	lastRender = GetTime()
	local mob = threatTarget()
	if not frame.preview and not shouldShow(mob) then
		frame:Hide()
		return
	end
	frame:Show()
	if mob then
		collect(mob)
	else
		for _, e in ipairs(list) do pool[#pool + 1] = e end
		wipe(list)
	end
	if frame.preview and #list == 0 then
		header:SetText("Threat (drag to move, /tthreat lock)")
	else
		header:SetText(mob and UnitName(mob) or "Threat")
	end
	local top = tankValue()
	for i = 1, db.bars do
		local bar, e = bars[i], list[i]
		if e then
			local r, g, b = classColor(e.unit)
			bar:SetStatusBarColor(r, g, b)
			bar:SetMinMaxValues(0, max(top, list[1].value, 1))
			bar:SetValue(e.value)
			bar.left:SetText(format("%d. %s%s", i, e.name or "?", e.tanking and " |cffffd100(tank)|r" or ""))
			local pct = top > 0 and floor(e.value / top * 100 + 0.5) or 0
			bar.right:SetText(format("%s  %d%%", shortNumber(e.value), pct))
			bar:Show()
		elseif frame.preview and #list == 0 and i <= 3 then
			bar:SetStatusBarColor(0.4, 0.4, 0.4)
			bar:SetMinMaxValues(0, 3)
			bar:SetValue(4 - i)
			bar.left:SetText(i .. ". ---")
			bar.right:SetText("")
			bar:Show()
		else
			bar:Hide()
		end
	end
	updateWarning()
end

local function layout()
	frame:SetScale(db.scale)
	frame:SetAlpha(db.alpha)
	frame:SetWidth(db.width)
	frame:SetHeight(20 + db.bars * (db.barHeight + 1))
	for i = 1, max(db.bars, #bars) do
		local bar = bars[i]
		if not bar and i <= db.bars then
			bar = CreateFrame("StatusBar", nil, frame)
			bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
			local bg = bar:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetTexture(0, 0, 0, 0.4)
			bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			bar.left:SetPoint("LEFT", 4, 0)
			bar.left:SetJustifyH("LEFT")
			bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			bar.right:SetPoint("RIGHT", -4, 0)
			bar.left:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
			bars[i] = bar
		end
		if bar then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", 2, -18 - (i - 1) * (db.barHeight + 1))
			bar:SetPoint("TOPRIGHT", -2, -18 - (i - 1) * (db.barHeight + 1))
			bar:SetHeight(db.barHeight)
			if i > db.bars then bar:Hide() end
		end
	end
	frame:EnableMouse(not db.locked)
	render()
end

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	db.point = { point, "UIParent", relPoint, x, y }
end

local function createFrame()
	frame = CreateFrame("Frame", "TemucraftThreatFrame", UIParent)
	frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
	local p = db.point
	frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 6, -5)
	header:SetPoint("TOPRIGHT", -6, -5)
	header:SetJustifyH("LEFT")
	frame:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed > 0.25 then elapsed = 0; render() end
	end)
	frame.bars = bars
	frame.preview = not db.locked
	layout()
end

-- Options -----------------------------------------------------------------

local function checkbox(panel, key, label, x, y)
	local cb = CreateFrame("CheckButton", "TemucraftThreatOpt_" .. key, panel, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	_G[cb:GetName() .. "Text"]:SetText(label)
	cb:SetScript("OnShow", function(self) self:SetChecked(db[key]) end)
	cb:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		if key == "locked" then frame.preview = not db.locked end
		layout()
	end)
end

local function slider(panel, key, label, minV, maxV, step, x, y, fmt)
	local s = CreateFrame("Slider", "TemucraftThreatOpt_" .. key, panel, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", x, y)
	s:SetWidth(200)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	_G[s:GetName() .. "Low"]:SetText(minV)
	_G[s:GetName() .. "High"]:SetText(maxV)
	local function setText(v) _G[s:GetName() .. "Text"]:SetText(format("%s: " .. (fmt or "%d"), label, v)) end
	s:SetScript("OnShow", function(self) self:SetValue(db[key]); setText(db[key]) end)
	s:SetScript("OnValueChanged", function(self, v)
		v = floor((tonumber(v) or db[key]) / step + 0.5) * step
		db[key] = v
		setText(v)
		layout()
	end)
end

local panel
local function buildOptions()
	panel = CreateFrame("Frame", "TemucraftThreatOptions", UIParent)
	panel.name = "Temucraft Threat"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Temucraft Threat")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", 16, -40)
	sub:SetText("Threat of your group on your target. Untick Lock to move the window. /tthreat")
	checkbox(panel, "locked", "Lock the window", 16, -64)
	checkbox(panel, "hideOutOfCombat", "Hide out of combat", 16, -92)
	checkbox(panel, "onlyInGroup", "Only in a group", 16, -120)
	checkbox(panel, "showPets", "Show pets", 16, -148)
	checkbox(panel, "warn", "Warn when you are close to pulling", 16, -176)
	checkbox(panel, "warnSound", "Play a sound with the warning", 16, -204)
	slider(panel, "warnAt", "Warn at", 50, 100, 5, 24, -250, "%d%%")
	slider(panel, "bars", "Bars", 3, 20, 1, 24, -295)
	slider(panel, "barHeight", "Bar height", 10, 30, 1, 24, -340)
	slider(panel, "width", "Width", 150, 400, 10, 24, -385)
	slider(panel, "scale", "Scale", 0.5, 2, 0.05, 24, -430, "%.2f")
	slider(panel, "alpha", "Opacity", 0.2, 1, 0.05, 24, -475, "%.2f")
	InterfaceOptions_AddCategory(panel)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		TemucraftThreatDB = TemucraftThreatDB or {}
		db = TemucraftThreatDB
		copyDefaults(defaults, db)
		createFrame()
		buildOptions()
		self:UnregisterEvent("ADDON_LOADED")
		for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
			"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
			self:RegisterEvent(e)
		end
	elseif db then
		if event == "PLAYER_REGEN_ENABLED" then warned = false end
		-- threat updates come once per unit, dozens a second in a raid: while the window is shown the 0.25 s
		-- OnUpdate draws them; while it is hidden they show it at most every 0.25 s
		if event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
			if frame:IsShown() or GetTime() - lastRender < 0.25 then return end
		end
		render()
	end
end)

SLASH_TEMUCRAFTTHREAT1 = "/tthreat"
SlashCmdList.TEMUCRAFTTHREAT = function(msg)
	msg = (msg or ""):lower()
	if msg == "lock" or msg == "unlock" then
		db.locked = msg == "lock"
		frame.preview = not db.locked
		layout()
	elseif msg == "reset" then
		db.point = { "CENTER", "UIParent", "CENTER", 300, -100 }
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, -100)
	else
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
