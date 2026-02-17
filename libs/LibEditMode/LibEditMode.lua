--[[
	LibEditMode
	Library that allows integration with Blizzard's Edit Mode.
	Based on the API by p3lim (https://github.com/p3lim-wow/LibEditMode)

	This implementation is taint-safe: it does NOT call any Blizzard-protected
	EditModeManager functions. Instead it hooks OnShow/OnHide on EditModeManagerFrame
	from addon code (untainted) to drive the enter/exit cycle.
]]

local MAJOR, MINOR = "LibEditMode", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

lib.frames       = lib.frames       or {} -- frame -> { callback, default, settings, buttons }
lib.callbacks    = lib.callbacks    or {} -- eventName -> list of functions
lib.isInEditMode = false
lib.currentLayout = nil

-- Internal sub-table exposed as lib.internal (Glider accesses lib.internal.dialog)
lib.internal = lib.internal or {}

---------------------------------------------------------------------------
-- SettingType enum  (mirrors p3lim's API exactly)
---------------------------------------------------------------------------

lib.SettingType = {
	Checkbox  = "Checkbox",
	Slider    = "Slider",
	Dropdown  = "Dropdown",
	ColorPicker = "ColorPicker",
}

---------------------------------------------------------------------------
-- Callback system
---------------------------------------------------------------------------

---@param event string  "enter"|"exit"|"layout"|"create"|"rename"|"delete"
---@param callback function
function lib:RegisterCallback(event, callback)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], callback)
end

local function FireCallback(event, ...)
	local list = lib.callbacks[event]
	if list then
		for _, fn in ipairs(list) do
			fn(...)
		end
	end
end

---------------------------------------------------------------------------
-- Selection frame (the native-looking blue box LEM draws on each frame)
---------------------------------------------------------------------------

local SELECTION_COLOR  = {0.18, 0.6, 1, 1}
local SELECTION_BG     = {0.18, 0.6, 1, 0.12}

local function BuildSelectionFrame(owner)
	if owner.Selection then return end

	local sel = CreateFrame("Button", nil, owner)
	sel:SetAllPoints(owner)
	sel:SetFrameLevel(owner:GetFrameLevel() + 5)
	sel:Hide()
	sel.isSelected = false
	owner.Selection = sel

	-- Highlight background
	local center = sel:CreateTexture(nil, "BACKGROUND")
	center:SetAllPoints()
	center:SetColorTexture(unpack(SELECTION_BG))
	center:SetAlpha(0)
	sel.Center = center

	-- Border
	local function Edge(parent)
		local t = parent:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(unpack(SELECTION_COLOR))
		return t
	end
	local top = Edge(sel) ; top:SetHeight(2)    ; top:SetPoint("TOPLEFT")     ; top:SetPoint("TOPRIGHT")
	local bot = Edge(sel) ; bot:SetHeight(2)    ; bot:SetPoint("BOTTOMLEFT")  ; bot:SetPoint("BOTTOMRIGHT")
	local lft = Edge(sel) ; lft:SetWidth(2)     ; lft:SetPoint("TOPLEFT")     ; lft:SetPoint("BOTTOMLEFT")
	local rgt = Edge(sel) ; rgt:SetWidth(2)     ; rgt:SetPoint("TOPRIGHT")    ; rgt:SetPoint("BOTTOMRIGHT")

	-- Resize corners (decorative only)
	local function Corner(parent, p1, p2)
		local c = parent:CreateTexture(nil, "OVERLAY")
		c:SetSize(8, 8)
		c:SetColorTexture(unpack(SELECTION_COLOR))
		c:SetPoint(p1)
		c:SetPoint(p2)
		return c
	end
	Corner(sel, "TOPLEFT",     "TOPLEFT")
	Corner(sel, "TOPRIGHT",    "TOPRIGHT")
	Corner(sel, "BOTTOMLEFT",  "BOTTOMLEFT")
	Corner(sel, "BOTTOMRIGHT", "BOTTOMRIGHT")

	-- Label shown above the frame
	local label = sel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("BOTTOMLEFT", sel, "TOPLEFT", 0, 2)
	label:SetTextColor(unpack(SELECTION_COLOR))
	label:Hide()
	sel.Label = label

	-- Drag to move
	sel:RegisterForDrag("LeftButton")
	sel:SetScript("OnDragStart", function(self) self:GetParent():StartMoving() end)
	sel:SetScript("OnDragStop",  function(self)
		local frame = self:GetParent()
		frame:StopMovingOrSizing()
		local data = lib.frames[frame]
		if data then
			local point, _, _, x, y = frame:GetPoint(1)
			if point then
				data.callback(frame, lib.currentLayout, point, math.floor(x + 0.5), math.floor(y + 0.5))
			end
		end
	end)

	-- Mouse enter/leave
	sel:SetScript("OnEnter", function(self)
		self.Center:SetAlpha(1)
		self.Label:Show()
		if lib.internal.dialog and lib.internal.dialog.owner == self:GetParent() then
			-- dialog already visible, keep it
		end
	end)
	sel:SetScript("OnLeave", function(self)
		if not self.isSelected then
			self.Center:SetAlpha(0)
			self.Label:Hide()
		end
	end)

	-- Click to select / show settings dialog
	sel:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			lib:SelectFrame(self:GetParent())
		end
	end)
end

---------------------------------------------------------------------------
-- Settings dialog
---------------------------------------------------------------------------

local dialog = CreateFrame("Frame", "GroupInfoEditModeDialog", UIParent, "BackdropTemplate")
dialog:SetSize(220, 40)
dialog:Hide()
dialog:SetFrameLevel(200)
dialog:SetBackdrop({
	bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile     = true, tileEdge = true, tileSize = 32,
	edgeSize = 18,
	insets   = {left = 5, right = 5, top = 5, bottom = 5},
})
lib.internal.dialog = dialog

local function RebuildDialog(owner)
	local data = lib.frames[owner]
	if not data then return end

	-- Clear previous widgets
	for _, child in ipairs(dialog.widgets or {}) do
		child:Hide()
		child:SetParent(nil)
	end
	dialog.widgets = {}

	local settings = data.settings
	if not settings or #settings == 0 then
		dialog:Hide()
		return
	end

	local yOff = -12
	local W = 200

	local function AddWidget(w)
		table.insert(dialog.widgets, w)
	end

	for _, setting in ipairs(settings) do
		local kind    = setting.kind
		local name    = setting.name
		local layoutName = lib.currentLayout

		if kind == lib.SettingType.Checkbox then
			local cb = CreateFrame("CheckButton", nil, dialog, "InterfaceOptionsCheckButtonTemplate")
			cb:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)
			cb.Text:SetText(name)
			cb.Text:SetTextColor(1, 1, 1)
			local ok, val = pcall(setting.get, layoutName)
			cb:SetChecked(ok and val or false)
			cb:SetScript("OnClick", function(self)
				pcall(setting.set, layoutName, self:GetChecked())
			end)
			AddWidget(cb)
			yOff = yOff - 26

		elseif kind == lib.SettingType.Slider then
			local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)
			label:SetText(name)
			label:SetTextColor(1, 1, 1)
			AddWidget(label)
			yOff = yOff - 14

			local slider = CreateFrame("Slider", nil, dialog, "OptionsSliderTemplate")
			slider:SetWidth(W - 20)
			slider:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)
			slider:SetMinMaxValues(setting.minValue or 0, setting.maxValue or 1)
			slider:SetValueStep(setting.valueStep or 0.01)
			slider:SetObeyStepOnDrag(true)
			_G[slider:GetName().."Low"]:SetText(tostring(setting.minValue or 0))
			_G[slider:GetName().."High"]:SetText(tostring(setting.maxValue or 1))

			local ok, val = pcall(setting.get, layoutName)
			slider:SetValue(ok and val or (setting.default or 0))

			local valLabel = _G[slider:GetName().."Text"]
			local function UpdateLabel(v)
				if setting.formatter then
					valLabel:SetText(setting.formatter(v))
				else
					valLabel:SetText(string.format("%.2f", v))
				end
			end
			UpdateLabel(ok and val or (setting.default or 0))

			slider:SetScript("OnValueChanged", function(self, value)
				UpdateLabel(value)
				pcall(setting.set, layoutName, value)
			end)
			AddWidget(slider)
			yOff = yOff - 30

		elseif kind == lib.SettingType.Dropdown then
			local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)
			label:SetText(name)
			label:SetTextColor(1, 1, 1)
			AddWidget(label)
			yOff = yOff - 14

			local dropdown = CreateFrame("Frame", nil, dialog, "UIDropDownMenuTemplate")
			dropdown:SetPoint("TOPLEFT", dialog, "TOPLEFT", 0, yOff)
			UIDropDownMenu_SetWidth(dropdown, 120)

			local function OnClick(self)
				pcall(setting.set, layoutName, self.value)
				UIDropDownMenu_SetSelectedValue(dropdown, self.value)
				UIDropDownMenu_SetText(dropdown, self.arg1)
			end

			UIDropDownMenu_Initialize(dropdown, function()
				local info = UIDropDownMenu_CreateInfo()
				for _, opt in ipairs(setting.values or {}) do
					info.text = opt.text
					info.value = opt.value or opt.text
					info.arg1 = opt.text
					info.func = OnClick
					local ok, current = pcall(setting.get, layoutName)
					info.checked = (ok and current == info.value)
					UIDropDownMenu_AddButton(info)
				end
			end)

			local ok, current = pcall(setting.get, layoutName)
			if ok then
				for _, opt in ipairs(setting.values or {}) do
					if (opt.value or opt.text) == current then
						UIDropDownMenu_SetText(dropdown, opt.text)
						break
					end
				end
			end

			AddWidget(dropdown)
			yOff = yOff - 34

		elseif kind == lib.SettingType.ColorPicker then
			local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)
			label:SetText(name)
			label:SetTextColor(1, 1, 1)
			AddWidget(label)
			yOff = yOff - 14

			local swatch = CreateFrame("Button", nil, dialog)
			swatch:SetSize(20, 20)
			swatch:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, yOff)

			local swatchBG = swatch:CreateTexture(nil, "BACKGROUND")
			swatchBG:SetAllPoints()
			swatchBG:SetColorTexture(0, 0, 0, 1)

			local swatchColor = swatch:CreateTexture(nil, "BORDER")
			swatchColor:SetAllPoints()
			swatchColor:SetPoint("TOPLEFT", 2, -2)
			swatchColor:SetPoint("BOTTOMRIGHT", -2, 2)

			local ok, colorObj = pcall(setting.get, layoutName)
			if ok and colorObj then
				local r, g, b = colorObj:GetRGB()
				swatchColor:SetColorTexture(r, g, b, 1)
			else
				swatchColor:SetColorTexture(1, 1, 1, 1)
			end

			swatch:SetScript("OnClick", function()
				local currentColor = setting.get(layoutName)
				local r, g, b = currentColor:GetRGB()

				ColorPickerFrame.previousValues = {r = r, g = g, b = b}
				ColorPickerFrame:SetupColorPickerAndShow({
					r = r, g = g, b = b,
					hasOpacity = false,
					swatchFunc = function()
						local nr, ng, nb = ColorPickerFrame:GetColorRGB()
						swatchColor:SetColorTexture(nr, ng, nb, 1)
						pcall(setting.set, layoutName, CreateColor(nr, ng, nb, 1))
					end,
					cancelFunc = function(prev)
						if prev then
							swatchColor:SetColorTexture(prev.r, prev.g, prev.b, 1)
							pcall(setting.set, layoutName, CreateColor(prev.r, prev.g, prev.b, 1))
						end
					end,
				})
			end)

			AddWidget(swatch)
			yOff = yOff - 26
		end
	end

	-- Buttons row
	local buttons = data.buttons
	if buttons and #buttons > 0 then
		local xOff = 10
		for _, btn in ipairs(buttons) do
			local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
			b:SetHeight(22)
			local tw = b:GetFontString():GetStringWidth() + 20
			b:SetWidth(math.max(80, tw))
			b:SetPoint("TOPLEFT", dialog, "TOPLEFT", xOff, yOff)
			b:SetText(btn.name)
			b:SetScript("OnClick", function() pcall(btn.onClick, layoutName) end)
			AddWidget(b)
			xOff = xOff + math.max(80, tw) + 4
		end
		yOff = yOff - 28
	end

	-- Reset button
	local resetBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	resetBtn:SetSize(80, 22)
	resetBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -8, 8)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		if not settings then return end
		for _, setting in ipairs(settings) do
			if setting.default ~= nil and setting.set then
				pcall(setting.set, lib.currentLayout, setting.default, true)
			end
		end
		RebuildDialog(owner) -- refresh values
	end)
	AddWidget(resetBtn)

	local totalH = math.abs(yOff) + 40
	dialog:SetHeight(totalH)
	dialog:SetWidth(W + 20)
	dialog:Show()
end

---------------------------------------------------------------------------
-- Frame selection
---------------------------------------------------------------------------

local selectedFrame = nil

function lib:SelectFrame(owner)
	-- Deselect previous
	if selectedFrame and selectedFrame ~= owner then
		local prev = lib.frames[selectedFrame]
		if prev and selectedFrame.Selection then
			selectedFrame.Selection.isSelected = false
			selectedFrame.Selection.Center:SetAlpha(0)
			selectedFrame.Selection.Label:Hide()
		end
	end
	selectedFrame = owner
	local data = lib.frames[owner]
	if not data then return end

	owner.Selection.isSelected = true
	owner.Selection.Center:SetAlpha(1)
	owner.Selection.Label:Show()

	-- Position dialog below (or above) the frame
	dialog:ClearAllPoints()
	dialog.owner = owner
	local _, _, _, _, y = owner:GetPoint(1)
	if (y or 0) > 0 then
		dialog:SetPoint("TOP", owner, "BOTTOM", 0, -4)
	else
		dialog:SetPoint("BOTTOM", owner, "TOP", 0, 4)
	end

	if data.settings and #data.settings > 0 then
		dialog.currentLayout = lib.currentLayout
		RebuildDialog(owner)
	else
		dialog:Hide()
	end
end

---------------------------------------------------------------------------
-- Enter / Exit Edit Mode
---------------------------------------------------------------------------

local function EnterEditMode()
	lib.isInEditMode = true
	for frame, data in pairs(lib.frames) do
		if frame.Selection then
			frame:SetMovable(true)
			frame:SetClampedToScreen(true)
			frame:EnableMouse(true)
			frame.Selection:Show()
			frame.Selection.Label:SetText(frame.editModeName or "Frame")
		end
	end
	FireCallback("enter")
end

local function ExitEditMode()
	lib.isInEditMode = false
	dialog:Hide()
	selectedFrame = nil
	for frame in pairs(lib.frames) do
		if frame.Selection then
			frame.Selection:Hide()
			frame.Selection.isSelected = false
			frame.Selection.Center:SetAlpha(0)
			frame.Selection.Label:Hide()
			frame:EnableMouse(false)
		end
	end
	FireCallback("exit")
end

---------------------------------------------------------------------------
-- Layout tracking  (EDIT_MODE_LAYOUTS_UPDATED carries the active layout)
---------------------------------------------------------------------------

local function GetCurrentLayoutName()
	if EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutName then
		return EditModeManagerFrame:GetActiveLayoutName()
	end
	return "Default"
end

local function ApplyLayout(layoutName)
	lib.currentLayout = layoutName
	-- Reposition all frames from their saved data
	for frame, data in pairs(lib.frames) do
		-- The addon's 'layout' callback is responsible for actually moving the frame;
		-- we just fire the callback with the layout name.
	end
	FireCallback("layout", layoutName)
end

---------------------------------------------------------------------------
-- Hook EditModeManagerFrame after all frames exist
---------------------------------------------------------------------------

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function(self, event)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")

	if EditModeManagerFrame then
		EditModeManagerFrame:HookScript("OnShow", function()
			ApplyLayout(GetCurrentLayoutName())
			EnterEditMode()
		end)
		EditModeManagerFrame:HookScript("OnHide", function()
			ExitEditMode()
		end)
		if EditModeManagerFrame:IsShown() then
			EnterEditMode()
		end
	end

	-- Apply current layout on login
	ApplyLayout(GetCurrentLayoutName())
end)

-- Also fire layout callback on layout change events
local layoutEventFrame = CreateFrame("Frame")
layoutEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
layoutEventFrame:SetScript("OnEvent", function(self, event)
	ApplyLayout(GetCurrentLayoutName())
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

---Register a frame to be movable in Edit Mode.
---@param frame table Frame to register
---@param callback function Called when position changes: callback(frame, layoutName, point, x, y)
---@param default table Default position: {point, x, y}
function lib:AddFrame(frame, callback, default)
	assert(frame,    "LibEditMode:AddFrame requires a frame")
	assert(callback, "LibEditMode:AddFrame requires a callback")

	lib.frames[frame] = lib.frames[frame] or {}
	lib.frames[frame].callback = callback
	lib.frames[frame].default  = default
	lib.frames[frame].settings = lib.frames[frame].settings or {}
	lib.frames[frame].buttons  = lib.frames[frame].buttons  or {}

	BuildSelectionFrame(frame)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false) -- only enabled during Edit Mode
end

---Register extra settings shown in the Edit Mode dialog for this frame.
---@param frame table Frame already registered with AddFrame
---@param settings table Array of setting definition tables
function lib:AddFrameSettings(frame, settings)
	assert(lib.frames[frame], "LibEditMode:AddFrameSettings: frame must be registered first")
	lib.frames[frame].settings = settings
end

---Register extra buttons shown in the Edit Mode dialog for this frame.
---@param frame table Frame already registered with AddFrame
---@param buttons table Array of {name, onClick} tables
function lib:AddFrameSettingsButtons(frame, buttons)
	assert(lib.frames[frame], "LibEditMode:AddFrameSettingsButtons: frame must be registered first")
	lib.frames[frame].buttons = buttons
end

---Returns true when Edit Mode is currently open.
function lib:IsInEditMode()
	return lib.isInEditMode
end

---Force-refresh the settings dialog for a frame.
function lib:RefreshFrameSettings(frame)
	if selectedFrame == frame and dialog:IsShown() then
		RebuildDialog(frame)
	end
end

---Enable a named setting in the dialog.
function lib:EnableFrameSetting(frame, settingName)
	local data = lib.frames[frame]
	if not data then return end
	for _, s in ipairs(data.settings or {}) do
		if s.name == settingName then s._disabled = false end
	end
	if selectedFrame == frame then RebuildDialog(frame) end
end

---Disable a named setting in the dialog (greyed out).
function lib:DisableFrameSetting(frame, settingName)
	local data = lib.frames[frame]
	if not data then return end
	for _, s in ipairs(data.settings or {}) do
		if s.name == settingName then s._disabled = true end
	end
	if selectedFrame == frame then RebuildDialog(frame) end
end