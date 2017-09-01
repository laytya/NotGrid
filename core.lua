local L = AceLibrary("AceLocale-2.2"):new("NotGrid")
NotGrid = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0")
NotGridOptions = {} -- After the addon is fully initialized WoW will fill this up with its saved variables if any

function NotGrid:OnInitialize()
	self.RosterLib = AceLibrary("RosterLib-2.0")
	self.HealComm = AceLibrary("HealComm-1.0")
	self.Banzai = AceLibrary("Banzai-1.0") -- only reports as having aggro if someone with this library is targetting the mob and reporting that the mob is targeting said unit
	self.NPL = AceLibrary("NotProximityLib-1.0")
	self.NRL = AceLibrary("NotRosterLib-1.0")
	self.Gratuity = AceLibrary("Gratuity-2.0")
	self.UnitFrames = {}
	self.Container = self:CreateContainerFrame()
	self.PrevTarget = nil -- for target highlighting
end

function NotGrid:OnEnable()
	self.o = NotGridOptions -- Need to wait for addon to be fully initialized and saved variables loaded before I set this
	self:SetDefaultOptions() -- if NotGridOptions is empty(no saved varoables) this will fill it up with defaults
	self:DoDropDown()
	self:RegisterEvent("NotRosterLib_UnitChanged")
	self:RegisterEvent("NotRosterLib_RosterChanged")
    self:RegisterEvent("HealComm_Healupdate")
    self:RegisterEvent("HealComm_Ressupdate")
    self:ScheduleRepeatingEvent("UnitBuffs", self.UnitBuffs, 0.2, self)
	--self:RegisterEvent("UNIT_HEALTH") -- handled with frame OnUpdate
	--self:RegisterEvent("PLAYER_TARGET_CHANGED") -- handled with frame OnUpdate
	--self:RegisterEvent("Banzai_UnitGainedAggro") -- handled with frame OnUpdate
	--self:RegisterEvent("Banzai_UnitLostAggro") -- handled with frame OnUpdate
	--self:RegisterEvent("UNIT_MANA") -- handled with frame OnUpdate
	if 1==1 then
		self:RegisterEvent("NotProximityLib_RangeUpdate", "RangeHandle")
		self:RegisterEvent("NotProximityLib_WorldRangeUpdate", "RangeHandle")
	end
	if Clique then
		self.CliqueProfile = string.format(L["%s of %s"],GetUnitName("player"),GetRealmName())
	end
end

------------------
-- NotRosterLib --
------------------

function NotGrid:NotRosterLib_UnitChanged(unitobj,oldunitobj)
	if unitobj and not oldunitobj and not (unitobj.class == "PET") then
		unitobj.ngframe = self:AssignUnitFrame()
		self:UpdateUnitFrame(unitobj)
	elseif oldunitobj and oldunitobj.ngframe and not unitobj then
		self:ClearUnitFrame(oldunitobj)
	elseif unitobj and unitobj.ngframe then -- was throwing errors in relation to pet saying no unitobj found. Not sure why?
		self:UpdateUnitFrame(unitobj)
	end
		--DEFAULT_CHAT_FRAME:AddMessage("trigger.. but no ngframe?")
	--end
end

function NotGrid:NotRosterLib_RosterChanged() -- All the units have been updated so position the frames
	self:PositionFrames()
end

-----------------
-- UNIT_HEALTH --
-----------------

function NotGrid:UNIT_HEALTH(unitid)
	local unitobj = self.NRL:GetUnitObjectFromUnit(unitid)
	if unitobj and unitobj.ngframe then
		local f = unitobj.ngframe
		if UnitIsConnected(unitid) then
			local healamount = self.HealComm:getHeal(f.name) --We have to check healcomm as well cause if the unit takes damage or gains health or something during the heal I have to adjust what the final heal will look like.
			local currhealth = UnitHealth(unitid)
			local maxhealth = UnitHealthMax(unitid)
			local deficit = maxhealth - currhealth
			f.healthbar:SetMinMaxValues(0, maxhealth)
			f.healthbar:SetValue(currhealth)
			if UnitIsDead(unitid) then
				self:UnitHealthZero(f, L["Dead"])
			elseif UnitIsGhost(unitid) or (deficit >= maxhealth) then -- we can't detect unitisghost if he's not in range so we do the additional conditional. It won't false report for "dead" because that's checked first. Still a lot of false reports. In BGs.
				self:UnitHealthZero(f, L["Ghost"])
			elseif currhealth/maxhealth*100 <= self.o.healththreshhold then
				local deficittext
				if deficit > 999 then
					deficittext = string.format("-%.1fk", deficit/1000.0)
				else
					deficittext = string.format("-%d", deficit)
				end
				f.namehealthtext:SetText(deficittext)
			else
				f.namehealthtext:SetText(f.shortname)
			end
			if healamount and healamount > 0 then
				self:SetIncHealFrame(f, healamount, currhealth, maxhealth)
			else
				f.incheal:SetBackdropColor(0,0,0,0)
				f.healcommtext:Hide() -- should be covered by healcomm triggers but lets have this in too
			end
		else
			self:UnitHealthZero(f, "Offline")
		end
	end
end

function NotGrid:UnitHealthZero(f, state)
	--f:SetBackdropBorderColor(unpack(self.o.unitbordercolor)) -- shouldn't have to do this after I've rewritten the border to run on OnUpdate
	f.namehealthtext:SetText(f.shortname.."\n"..state)
	f.incheal:SetBackdropColor(0,0,0,0)
	f.healthbar:SetMinMaxValues(0, 1)
	f.healthbar:SetValue(0)
	f.healcommtext:Hide() -- make sure healcommtext gets hidden too
	-- for i=1,8 do -- we'll see if we need this .. theoritically SEA should be sending buff/debuff lost in this condition
	-- 	f.healthbar["trackingicon"..i].active = nil
	-- 	f.healthbar["trackingicon"..i]:Hide()
	-- end
end

-----------------
-- UNIT_BORDER --
-----------------

function NotGrid:UNIT_BORDER(unitid) -- because of the way this is written its prone to minor(or major, but I don't notice it at all so I dunno) flickering. I don't think its a big deal, but its something to address at some point
	local unitobj = self.NRL:GetUnitObjectFromUnit(unitid)
	if unitobj and unitobj.ngframe then
		local name = UnitName("Target") -- could get erronous with pets
		local currmana = UnitMana(unitid)
		local maxmana = UnitManaMax(unitid)
		if self.o.tracktarget and name and name == unitobj.ngframe.name then
			--unitobj.ngframe.borderstate = "target"
			unitobj.ngframe:SetBackdropBorderColor(unpack(self.o.targetcolor))
		elseif self.o.trackaggro and self.Banzai:GetUnitAggroByUnitId(unitid) then
			--unitobj.ngframe.borderstate = "aggro"
			unitobj.ngframe:SetBackdropBorderColor(unpack(self.o.aggrowarningcolor))
		elseif self.o.trackmana and UnitPowerType(unitid) == 0 and currmana/maxmana*100 < self.o.manathreshhold and not UnitIsDeadOrGhost(unitid) then
			--unitobj.ngframe.borderstate = "mana"
			unitobj.ngframe:SetBackdropBorderColor(unpack(self.o.manawarningcolor))
		else
			--unitobj.ngframe.borderstate = nil
			unitobj.ngframe:SetBackdropBorderColor(unpack(self.o.unitbordercolor))
		end
	end
end

-------------------
-- Buffs/Debuffs --
-------------------

function NotGrid:UnitBuffs()
	for _,f in self.UnitFrames do
		if f.unit then -- if the frame has unit info and thus is active then
			local unitid = f.unit

			--activate buffs -- loop through every buff and match them against every option, if I find a match then activate the frame
			local bi = 1
			while (UnitBuff(unitid,bi) ~= nil) do
				self.Gratuity:SetUnitBuff(unitid,bi)
				local buffname = self.Gratuity:GetLine(1)
				for i=1,8 do
					if self:CheckAura(self.o["trackingicon"..i], buffname) then
						self:SetIconFrame(f.healthbar["trackingicon"..i], buffname, nil, i)
					end
				end
				bi = bi + 1;
			end

			--activate debuffs -- same as above
			local di = 1
			while (UnitDebuff(unitid,di) ~= nil) do
				self.Gratuity:SetUnitDebuff(unitid,di)
				local debuffname = self.Gratuity:GetLine(1)
				local _, _, spelltype =  UnitDebuff(unitid,di) -- texture, applications, type
				for i=1,8 do
					if self:CheckAura(self.o["trackingicon"..i], debuffname) then
						self:SetIconFrame(f.healthbar["trackingicon"..i], debuffname, nil, i)
					elseif spelltype and self:CheckAura(self.o["trackingicon"..i], spelltype) then
						self:SetIconFrame(f.healthbar["trackingicon"..i], spelltype, spelltype, i)
					end
				end
				di = di + 1;
			end

			--clear buffs&debuffs -- loop through every option and match them against every buff, if its never found then clear the frame
			for i=1,8 do
				local fi = f.healthbar["trackingicon"..i]
				if fi.active then
					local found = false
					local bi = 1
					while (UnitBuff(unitid,bi) ~= nil) do
						self.Gratuity:SetUnitBuff(unitid,bi)
						local buffname = self.Gratuity:GetLine(1)
						if self:CheckAura(self.o["trackingicon"..i], buffname) then -- i can probably reduce this, but its workign for now
							found = true
						end
						bi = bi + 1;
					end
					local di = 1
					while (UnitDebuff(unitid,di) ~= nil) do
						self.Gratuity:SetUnitDebuff(unitid,di)
						local debuffname = self.Gratuity:GetLine(1)
						local _, _, spelltype =  UnitDebuff(unitid,di) -- texture, applications, type
						if self:CheckAura(self.o["trackingicon"..i], buffname) or (spelltype and self:CheckAura(self.o["trackingicon"..i], spelltype)) then
							found = true
						end
						di = di + 1
					end
					if found == false then
						self:ClearIconFrame(fi)
					end
				end
			end
		end
	end
end

function NotGrid:CheckAura(str, aura)
	if str and aura then
		for text in string.gfind(str, "([^|]+)") do
			if text == aura then
				return true
			end
		end
	end
end

--------------
-- HealComm --
--------------

function NotGrid:HealComm_Healupdate(unitname)
	local unitobj = self.NRL:GetUnitObjectFromName(unitname)
	if unitobj and unitobj.ngframe then
		local f = unitobj.ngframe
		local healamount = self.HealComm:getHeal(unitname)
		local currhealth = UnitHealth(unitobj.unitid) -- Althrough I could use rosterlibs sent unitid
		local maxhealth = UnitHealthMax(unitobj.unitid)
		local healtext
		if healamount > 999 then
			healtext = string.format("+%.1fk", healamount/1000.0)
		else
			healtext = string.format("+%d", healamount)
		end

		if healamount > 0 then
			self:SetIncHealFrame(f, healamount, currhealth, maxhealth)
			if self.o.showhealcommtext then
				f.healcommtext:SetText(healtext)
				f.healcommtext:Show()
			end
		else
			f.incheal:SetBackdropColor(0,1,0,0)
			f.healcommtext:Hide()
		end
	end
end

function NotGrid:HealComm_Ressupdate(unitname)
	local unitobj = self.NRL:GetUnitObjectFromName(unitname)
	if unitobj and unitobj.ngframe then
		if self.HealComm:UnitisResurrecting(unitname) then
			unitobj.ngframe.incres:Show()
		else
			unitobj.ngframe.incres:Hide()
		end
	end
	--DEFAULT_CHAT_FRAME:AddMessage(unitname.." "..resstime)
end

---------------------
-- NotProximityLib --
---------------------

function NotGrid:RangeHandle(unitid, range, lastseen, confirmed) -- ranges that should normally be nil will be 1000 so we don't have to check for the existane or range
	local unitobj = self.NRL:GetUnitObjectFromUnit(unitid)
	if unitobj and unitobj.ngframe then
		local f = unitobj.ngframe
		local time = GetTime()
		if self.o.usemapdistances == true and (self.NPL.v.instance == "none" or self.NPL.v.instance == "pvp") then
			if event == "NotProximityLib_WorldRangeUpdate" then
				self:RangeToggle(f, range)
			end
		elseif event == "NotProximityLib_RangeUpdate" then
			if confirmed then
				self:RangeToggle(f, range)
			elseif not confirmed and f.inrange and self.o.proximityleeway < time-lastseen then -- if he's not already set as oor and the last seen time is < than leeway
				self:RangeToggle(f, 100) -- send 100 dummy data in this case to toggle it off
			end
		end
	end
end

-------------------
-- On Unit Click --
-------------------

function NotGrid:ClickHandle(button)
	if button == "RightButton" and SpellIsTargeting() then
		SpellStopTargeting()
		return
	end
	if button == "LeftButton" then
		if SpellIsTargeting() then
			SpellTargetUnit(this.unit)
		elseif CursorHasItem() then
			DropItemOnUnit(this.unit)
		else
			TargetUnit(this.unit)
		end
	else --Thanks Luna :^)
		local name = UnitName(this.unit)
		local id = string.sub(this.unit,5)
		local unit = this.unit
		local menuFrame = FriendsDropDown
		menuFrame.displayMode = "MENU"
		menuFrame.initialize = function() UnitPopup_ShowMenu(getglobal(UIDROPDOWNMENU_OPEN_MENU), "PARTY", unit, name, id) end
		ToggleDropDownMenu(1, nil, FriendsDropDown, "cursor")
	end
end

function NotGrid:CliqueHandle(button) -- if/else for Clique handling is done in the frames.lua when creating the frame
	local a,c,s = IsAltKeyDown() or 0, IsControlKeyDown() or 0, IsShiftKeyDown() or 0
	local modifiers = a*1+c*2+s*4
	local foundspell = nil
	for _,value in CliqueDB["chars"][self.CliqueProfile][L["Default Friendly"]] do
		if value["button"] == button and value["modifiers"] == modifiers then
			if value["rank"] then
				foundspell = value["name"]..L["(Rank "]..value["rank"]..")" -- wew
			else
				foundspell = value["name"]
			end
			break
		end
	end
	if foundspell then
		local LastTarget = UnitName("target") -- I use this as a boolean because targetting by name can be erronous
		ClearTarget()
		if LazySpell then --_LazySpell quick and dirty fix
			local lsSpell,lsRank = LazySpell:ExtractSpell(foundspell)
			if self.HealComm.Spells[lsSpell] and lsRank == 1 then
				local lsRank = LazySpell:CalculateRank(lsSpell, this.unit)
				foundspell = lsSpell.."(Rank "..lsRank..")"
			end
		end
		CastSpellByName(foundspell) -- then cast it, but note that because we've cleared target to cast it we're just "spelltargeting"
		self.NPL:UpdateSpellCanTarget() -- Send ourselves off to NPL to run through the roster and check/update ranges
		if SpellIsTargeting() and SpellCanTargetUnit(this.unit) then -- then come back to our own func and see if they can cast on the unit they wanted to cast on
			SpellTargetUnit(this.unit) -- if they can, cast on them
		elseif SpellIsTargeting() then
			SpellStopTargeting() -- otherwise stop targetting
		end
		if LastTarget then -- remember, use it as a boolean.
			TargetLastTarget() -- and finally, if they actually had an old target, then target it
		end
	else
		self:ClickHandle(button) -- if it failed to find anything in clique then we send it to the regular handler
	end
end
