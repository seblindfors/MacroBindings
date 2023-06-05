----------------------------------------------------------------
-- Macro Bindings
----------------------------------------------------------------
-- 
-- Author:  Sebastian Lindfors (Munk / MunkDev)
-- Website: https://github.com/seblindfors/MacroBindings
-- Licence: GPL version 2 (General Public License)
-- 
-- Description:
--  This library adds support for executing macros based on macro
--  conditions. Bindings can be dynamically mapped to macros based
--  on where the macros are placed on the action bars.
-- 
-- Example usage in macro:
--  /binding [@target,nodead,harm] FOCUSTARGET; [@anyinteract,exists] INTERACTTARGET
--
--  One macro can contain multiple bindings, separated by semicolon.
--  One macro can contain multiple lines, each line containing multiple bindings.
--  If any of the conditions apply, the binding will be executed instead
--  of the other actions (if any) in the macro.
--
-- API functions:
--  @param body        : The body of the macro to parse.
--  @return conditions : A table containing all conditions found in the macro.
--  MacroBindings:ParseBody(body)
-- 
--  @param barID       : The ID of the bar to drive.
--  @param condition   : The condition to execute the response on.
--  @param response    : The response to execute. Optional. Defaults to result of condition.
--  MacroBindings:SetPageDriver(barID, condition, response)
--
--  @param barID       : The ID of the bar to get binding keys for.
--  @param template    : The binding template to use, e.g. ACTIONBUTTON%d
--  MacroBindings:SetBindingTemplate(barID, template)

local API = LibStub:NewLibrary('MacroBindings', 1)
if not API then return end
local Engine = CreateFrame('Frame', nil, nil, 'SecureHandlerStateTemplate')

local API_SLASH_CMD = '/binding'

-- Conditions to apply bindings
local DRIVER_COND_SIGNATURE = '_onstate-%d';
local DRIVER_COND_TEMPLATE  = [[self:RunAttribute('SetStateForMacro', %d, newstate)]];

-- Conditions to handle bar swapping
local DRIVER_PAGE_SIGNATURE = '_onstate-page-%d';
local DRIVER_PAGE_CONDITION = '_page-condition-%d';
local DRIVER_PAGE_TEMPLATE  = [[
	local barID = %d;
	%s -- (1) Execute response (optional)
	self:SetAttribute(tostring(barID), newstate) -- (2) Store state
	self:RunAttribute('RefreshBindingsForActionBar', newstate) -- (3) Refresh bindings
]];

local BAR_TO_BINDING_TEMPLATE = {
	[01] = 'ACTIONBUTTON%d';
	[02] = 'ACTIONBUTTON%d';
	[03] = 'MULTIACTIONBAR3BUTTON%d';
	[04] = 'MULTIACTIONBAR4BUTTON%d';
	[05] = 'MULTIACTIONBAR2BUTTON%d';
	[06] = 'MULTIACTIONBAR1BUTTON%d';
	[07] = 'ACTIONBUTTON%d';
	[08] = 'ACTIONBUTTON%d';
	[09] = 'ACTIONBUTTON%d';
	[10] = 'ACTIONBUTTON%d';
	[13] = 'MULTIACTIONBAR5BUTTON%d';
	[14] = 'MULTIACTIONBAR6BUTTON%d';
	[15] = 'MULTIACTIONBAR7BUTTON%d';
};

-- Some restricted environment helpers
local ConvertSecureBody, GetSecureBodySignature, GetNewtableSignature;
function GetSecureBodySignature(obj, func, args)
	return ConvertSecureBody(
		('%s:RunAttribute(\'%s\'%s%s)'):format(
			obj, func, args:trim():len() > 0 and ', ' or '', args));
end

function GetNewtableSignature(contents)
	return ('newtable(%s)'):format(contents:sub(2, -2))
end

function ConvertSecureBody(body)
	return (body
		:gsub('(%w+)::(%w+)%((.-)%)', GetSecureBodySignature)
		:gsub('%b{}', GetNewtableSignature)
	);
end

function Engine:__(body, ...)
	self:Execute(ConvertSecureBody(body:format(...)))
end

-- Prepare environment
Engine:__([[
	BARS     = {};
	SLOTS    = {};
	KEYS     = {};
	BINDINGS = {};
	DRIVERS  = {};
	STATES   = {};
]])

for name, body in pairs({
	-- Constants required in environment
	NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS;

	DRIVER_COND_SIGNATURE = DRIVER_COND_SIGNATURE;
	DRIVER_COND_TEMPLATE  = DRIVER_COND_TEMPLATE;

	DRIVER_PAGE_SIGNATURE = DRIVER_PAGE_SIGNATURE;
	DRIVER_PAGE_TEMPLATE  = DRIVER_PAGE_TEMPLATE;

	-- API
	GetBindingIDForSlot = [[
		local slotID = ...
		local barID = ceil(slotID / NUM_ACTIONBAR_BUTTONS)
		local btnID = slotID % NUM_ACTIONBAR_BUTTONS;
		if ( btnID == 0 ) then btnID = NUM_ACTIONBAR_BUTTONS end;

		local currentPage = self:GetAttribute(tostring(barID))
		local bindingTemplate = currentPage and BARS[currentPage];
		if bindingTemplate then
			return bindingTemplate:format(btnID), barID, btnID;
		end
	]];
	SetStateForMacro = [[
		local macroID, override = ...;
		STATES[macroID] = override;
		self::SetBindingsForMacro(macroID, override)
	]];
	SetBindingsForMacro = [[
		local macroID, override = ...;
		self::ClearBindingsForMacro(macroID)
		for slot, slottedMacroID in pairs(SLOTS) do
			if ( slottedMacroID == macroID ) then
				local bindingID = self::GetBindingIDForSlot(slot)
				if bindingID then
					self::SetBindingForMacro(bindingID, macroID, override)
				end
			end
		end
	]];
	SetBindingForMacro = [[
		local bindingID, macroID, override = ...;
		local keys = {GetBindingKey(bindingID)};
		BINDINGS[macroID] = BINDINGS[macroID] or newtable();
		for i, key in pairs(keys) do
			BINDINGS[macroID][key] = override;
			self::SetBinding(key, override)
		end
	]];
	ClearBindingsForMacro = [[
		local macroID = ...;
		local bindings = BINDINGS[macroID];
		if bindings then
			for key in pairs(bindings) do
				self::SetBinding(key, nil)
			end
			wipe(bindings)
		end
	]];
	RefreshBindingsForActionBar = [[
		local barID = ...;
		local low, high = self::GetBarRange(barID)
		for i = low, high do
			self::RefreshBindingsForActionSlot(i)
		end
	]];
	RefreshBindingsForActionSlot = [[
		local slotID = ...;
		local macroID = self::GetCurrentMacroInSlot(slotID)
		if macroID then
			self::StoreMacroInSlot(slotID, macroID)
			self::ClearBindingsForMacro(macroID)
			self::SetBindingsForMacro(macroID, STATES[macroID])
		end
	]];
	RefreshActionSlot = [[
		local slotID = ...;
		local oldMacroID = self::GetStoredMacroInSlot(slotID)
		local newMacroID = self::GetCurrentMacroInSlot(slotID)
		if ( oldMacroID ~= newMacroID ) then
			self::StoreMacroInSlot(slotID, newMacroID)
			if oldMacroID then
				self::ClearBindingsForMacro(oldMacroID)
				self::SetBindingsForMacro(oldMacroID, STATES[oldMacroID])
			end
			if newMacroID then
				self::ClearBindingsForMacro(newMacroID)
				self::SetBindingsForMacro(newMacroID, STATES[newMacroID])
			end
		end
	]];
	ReindexActionBars = [[
		wipe(SLOTS);
		for barID in pairs(BARS) do
			self::ReindexActionBar(barID)
			self::RefreshBindingsForActionBar(barID)
		end
	]];
	ReindexActionBar = [[
		local low, high = self::GetBarRange(...)
		for i = low, high do
			self::ReindexActionSlot(i)
		end
	]];
	ReindexActionSlot = [[
		local slotID = ...;
		local macroID = self::GetCurrentMacroInSlot(slotID)
		if macroID then
			self::StoreMacroInSlot(slotID, macroID)
		end
	]];
	GetCurrentMacroInSlot = [[
		local type, macroID = GetActionInfo(...)
		if ( type == 'macro' and self::HasDriver(macroID)) then
			return macroID;
		end
	]];
	GetBarRange = [[
		local low = ((...) - 1) * NUM_ACTIONBAR_BUTTONS + 1;
		local high = low + (NUM_ACTIONBAR_BUTTONS - 1);
		return low, high;
	]];
	SetBinding = [[
		local key, override = ...;
		self:SetBinding(true, key, override)
		KEYS[key] = override;
	]];
	StoreMacroInSlot = [[
		local slotID, macroID = ...;
		SLOTS[slotID] = macroID;
	]];
	GetStoredMacroInSlot = [[
		return SLOTS[...];
	]];
	HasDriver = [[
		return DRIVERS[...];
	]];
}) do
	local body = type(body) == 'string' and ConvertSecureBody(body) or body;
	Engine:SetAttribute(name, body)
	Engine:Execute(('%s = self:GetAttribute(%q)'):format(name, name))
end

local ENGINE_EVENTS = {
	'UPDATE_MACROS',
	'UPDATE_BINDINGS',
	'ACTIONBAR_SLOT_CHANGED',
	'PLAYER_REGEN_ENABLED',
	'PLAYER_LOGIN',
};

-- Set up event handler
for i, event in ipairs(ENGINE_EVENTS) do Engine:RegisterEvent(event) end
Engine.Pending = {};
function Engine:OnEvent(event, ...)
	if InCombatLockdown() then tinsert(self.Pending, {event, ...}) return end
	if self[event] then self[event](self, ...) end
end
Engine:SetScript('OnEvent', Engine.OnEvent)

function Engine:PLAYER_REGEN_ENABLED()
	for i, event in ipairs(self.Pending) do
		self:OnEvent(unpack(event))
	end
	wipe(self.Pending)
end

-- Bar indexing
for barID, bindingTemplate in pairs(BAR_TO_BINDING_TEMPLATE) do
	Engine:Execute(([[
		local barID = %d;
		BARS[barID] = %q;
		self:SetAttribute(tostring(barID), barID)
	]]):format(barID, bindingTemplate))
end

-- Insecure driver management because we can't create state drivers in restricted environments
Engine.Drivers = {};

function Engine:AddDriver(macroID, driver)
	RegisterStateDriver(self, tostring(macroID), driver)
	self:SetAttribute(DRIVER_COND_SIGNATURE:format(macroID), DRIVER_COND_TEMPLATE:format(macroID))
	self:__('DRIVERS[%d] = %q', macroID, driver)
end

function Engine:RemoveDrivers()
	self:__([[
		self:ClearBindings()
		wipe(BINDINGS)
		wipe(KEYS)
		for macroID in pairs(DRIVERS) do
			self:CallMethod('RemoveDriver', macroID, true)
		end
		wipe(DRIVERS)
	]])
end

function Engine:RemoveDriver(macroID, keepTableEntry)
	UnregisterStateDriver(self, tostring(macroID))
	self:SetAttribute(DRIVER_COND_SIGNATURE:format(macroID), nil)
	if not keepTableEntry then
		self:__('DRIVERS[%d] = nil', macroID)
	end
end

-- Engine updates
function Engine:PLAYER_LOGIN()
	self:__('self::ReindexActionBars()')
end

function Engine:ACTIONBAR_SLOT_CHANGED(slotID)
	self:__('self::RefreshActionSlot(%d)', slotID)
end

function Engine:UPDATE_MACROS()
	self:RemoveDrivers()
	for i=1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
		local conditions = API:ParseBody(GetMacroBody(i))
		if conditions then
			self:AddDriver(i, table.concat(conditions, '; '))
		end
	end
end

do -- Macro parsing
	local MACRO_EOL     = '%s+([^\n]+)'
	local MACRO_CMD     =  API_SLASH_CMD..MACRO_EOL
	local MACRO_PATTERN = '((%b[])%s*([^;]+))'          
	local MACRO_DEFAULT = '([^;%s]+)'

	local bindingNameIndex, indexedBindings = {}, 0;
	local function UpdateBindingNameIndex()
		local numBindings = GetNumBindings()
		if indexedBindings == numBindings then
			return
		end
		indexedBindings = numBindings;
		for i=1, numBindings do
			local command = GetBinding(i)
			local bindingName = GetBindingName(command)
			bindingNameIndex[bindingName] = command;
		end
	end

	local function ConvertBindingNameToID(bindingName)
		UpdateBindingNameIndex()
		return bindingNameIndex[bindingName] or bindingName;
	end

	function API:ParseBody(body)
		if not body then return end
		local default, conditions;
		for line in body:gmatch(MACRO_CMD) do
			for _, conditionals, binding in line:gmatch(MACRO_PATTERN) do
				local bindingID = ConvertBindingNameToID(binding)
				conditions = conditions or {};
				conditions[#conditions + 1] = ('%s %s'):format(conditionals, bindingID)
			end
			if not default then
				local fallbacks = line:gsub(MACRO_PATTERN, '');
				for fallback in fallbacks:gmatch(MACRO_DEFAULT) do
					default = fallback;
					break;
				end
			end
		end
		if conditions then
			conditions[#conditions + 1] = default or 'nil';
		end
		return conditions;
	end
end

function API:SetPageDriver(barID, condition, response)
	assert(not InCombatLockdown(), 'Cannot change page driver in combat')
	Engine:SetAttribute(DRIVER_PAGE_SIGNATURE:format(barID), DRIVER_PAGE_TEMPLATE:format(barID, response or ''))
	Engine:SetAttribute(DRIVER_PAGE_CONDITION:format(barID), condition)
	RegisterStateDriver(Engine, ('page-%d'):format(barID), condition)
end

function API:SetBindingTemplate(barID, template)
	assert(not InCombatLockdown(), 'Cannot change binding template in combat')
	local stateHandler = Engine:GetAttribute(DRIVER_PAGE_SIGNATURE:format(barID))
	local condition = Engine:GetAttribute(DRIVER_PAGE_CONDITION:format(barID))
	local stateRefresh;
	if stateHandler then
		stateRefresh = condition and ([[
			local newstate = SecureCmdOptionParse(%q)
			if (newstate == 'nil') then
				newstate = nil;
			else
				newstate = tonumber(newstate) or newstate;
			end
			%s
		]]):format(condition, stateHandler) or ([[
			local newstate = %d;
			%s
		]]):format(barID, stateHandler)
	else
		stateRefresh = ('local newstate = %d; %s'):format(barID, DRIVER_PAGE_TEMPLATE:format(barID, ''))
	end
	Engine:__([[BARS[%d] = %q; %s]], barID, template, stateRefresh)
end


do  -- Set default page driver to match Blizzard's default for the main action bar.
	-- NOTE: this macro condition does not assume the correct page from the state driver.
	-- The generic values are used to push an update to the handler, which uses a secure
	-- replica of ActionBarController_UpdateAll to set the actual page attribute.
	local conditionFormat = '[%s] %d; '
	local count, cond = 0, ''
	for i, macroCondition in ipairs({
		----------------------------------
		'vehicleui', 'possessbar', 'overridebar', 'shapeshift',
		'bar:2', 'bar:3', 'bar:4', 'bar:5', 'bar:6',
		'bonusbar:1', 'bonusbar:2', 'bonusbar:3', 'bonusbar:4', 'bonusbar:5'
		----------------------------------
	}) do cond = cond .. conditionFormat:format(macroCondition, i) count = i end
	-- append the list for the default bar (1) when none of the conditions apply.
	cond = cond .. (count + 1)

	-- Replicate ActionBarController_UpdateAll:
	API:SetPageDriver(1, cond, ([[
		if HasVehicleActionBar and HasVehicleActionBar() then
			newstate = GetVehicleBarIndex()
		elseif HasOverrideActionBar and HasOverrideActionBar() then
			newstate = GetOverrideBarIndex()
		elseif HasTempShapeshiftActionBar() then
			newstate = GetTempShapeshiftBarIndex()
		elseif GetBonusBarOffset() > 0 then
			newstate = GetBonusBarOffset() + %s
		else
			newstate = GetActionBarPage()
		end
	]]):format(NUM_ACTIONBAR_PAGES))
end

-- Add some error handling for when macros are clicked
_G['SLASH_BINDING1'] = API_SLASH_CMD;
SlashCmdList['BINDING'] = function(message)
	local result = tostring(SecureCmdOptionParse(message) or nil)
	if (result == '' or result == 'nil') then return end;
	print('Failed to intercept macro binding. Macro bindings cannot be triggered from mouse clicks.'
		..'\nCondition called:\n' .. BLUE_FONT_COLOR:WrapTextInColorCode(message)
		..'\nExpected binding:\n' .. YELLOW_FONT_COLOR:WrapTextInColorCode(GetBindingName(result))
	)
end
