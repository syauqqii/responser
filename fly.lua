-- Movement Hub Lite (UNIVERSAL: client-side, works in any game)
-- Fly/AirWalk, Walk/Jump/Fly speed (type or +/-), Infinite Jump, Override joystick + D-Pad (auto emote), Teleport dropdown
-- Hotkeys: F = toggle flight | E = up | Q = down

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local old = player.PlayerGui:FindFirstChild("FlyGUI")
if old then old:Destroy() end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local state = {
	flying = false, mode = "air", flySpeed = 5, up = false, down = false,
	ws = nil, jump = nil, infJump = false,
	override = false, showPad = false,
}
local pad = { f = false, b = false, l = false, r = false }
local defaults = { ws = 16, jump = 50 }
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local bv, bg, flyConn, platform
local flyDisabled = false
local wsZeroed = false
local animateSuppressed = false

local FLY_STATES = {
	"Climbing", "FallingDown", "Flying", "Freefall", "GettingUp", "Jumping", "Landed", "Physics",
	"PlatformStanding", "Ragdoll", "Running", "RunningNoPhysics", "Seated", "StrafingNoPhysics", "Swimming",
}
local function setStates(hum, enabled)
	for _, name in ipairs(FLY_STATES) do
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType[name], enabled) end)
	end
end

local function getParts()
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return hum, root
end

-- Camera-relative direction from the D-Pad buttons
local function padVector()
	local x = (pad.r and 1 or 0) - (pad.l and 1 or 0)
	local z = (pad.f and 1 or 0) - (pad.b and 1 or 0)
	if x == 0 and z == 0 then return Vector3.zero end
	local cf = camera.CFrame
	local f  = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local rt = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	if f.Magnitude == 0 or rt.Magnitude == 0 then return Vector3.zero end
	local v = f.Unit * z + rt.Unit * x
	return v.Magnitude > 0 and v.Unit or Vector3.zero
end

local function flyMode()
	return state.flying and state.mode == "fly"
end

-- Joystick override works on the ground and in AirWalk (Fly mode already moves manually)
local function overrideActive()
	return state.override and not flyMode()
end

-- Emote hold is on while flying, or while Override / D-Pad is on
local function emoteActive()
	return state.flying or state.override or state.showPad
end

-- Manual horizontal movement (D-Pad, or joystick/WASD when Override is on).
-- The Humanoid itself never walks, so animations/emotes are never interrupted.
local function manualMove(dt)
	if flyMode() then return end
	local h, r = getParts()
	if not (h and r and h.Health > 0) then return end
	local dir = Vector3.zero
	local pv = padVector()
	if pv.Magnitude > 0 then
		dir = pv
	elseif state.override then
		dir = h.MoveDirection
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude > 0 then
		dir = dir.Unit
		local pos = r.Position + dir * (state.ws or defaults.ws) * dt
		r.CFrame = CFrame.lookAt(pos, pos + dir)
	end
end

-- Ground movement (not flying). While AirWalking, the AirWalk loop calls manualMove itself.
bind(RunService.RenderStepped, function(dt)
	if not state.flying then manualMove(dt) end
end)

----------------------------------------------------------------
-- FLY / AIRWALK
----------------------------------------------------------------
local function stopFly()
	state.flying = false
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if bv then bv:Destroy() bv = nil end
	if bg then bg:Destroy() bg = nil end
	if platform then platform:Destroy() platform = nil end
	local hum = getParts()
	if hum then hum.PlatformStand = false end
	if flyDisabled then
		flyDisabled = false
		if hum then
			setStates(hum, true)
			hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
		end
		local animate = player.Character and player.Character:FindFirstChild("Animate")
		if animate then animate.Disabled = false end
		animateSuppressed = false
	end
end

local function startAirWalk()
	local hum, root = getParts()
	if not (hum and root) then return end
	stopFly()
	state.flying = true

	local box, size = player.Character:GetBoundingBox()
	local level = box.Position.Y - size.Y / 2

	platform = Instance.new("Part")
	platform.Name = "AirWalkPlatform"
	platform.Size = Vector3.new(10, 1, 10)
	platform.Anchored = true
	platform.CanCollide = true
	platform.Transparency = 1
	platform.Parent = workspace

	flyConn = RunService.RenderStepped:Connect(function(dt)
		local h, r = getParts()
		if not (h and r and h.Health > 0) then return stopFly() end

		manualMove(dt)

		level += ((state.up and 1 or 0) - (state.down and 1 or 0)) * state.flySpeed * 5 * dt
		platform.CFrame = CFrame.new(r.Position.X, level - 0.5, r.Position.Z)
	end)
end

local function startFly()
	local hum, root = getParts()
	if not (hum and root) then return end
	stopFly()
	state.flying = true
	flyDisabled = true

	local animate = player.Character:FindFirstChild("Animate")
	if animate then animate.Disabled = true end
	for _, track in ipairs(hum:GetPlayingAnimationTracks()) do track:AdjustSpeed(0) end
	setStates(hum, false)
	hum:ChangeState(Enum.HumanoidStateType.Swimming)
	hum.PlatformStand = true

	bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.one * 9e9
	bv.Velocity = Vector3.new(0, 0.1, 0)
	bv.Parent = root

	bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.one * 9e9
	bg.P = 9e4
	bg.CFrame = root.CFrame
	bg.Parent = root

	flyConn = RunService.RenderStepped:Connect(function(dt)
		local h, r = getParts()
		if not (h and r and h.Health > 0) then return stopFly() end

		local dir = h.MoveDirection
		local pv = padVector()
		if pv.Magnitude > 0 then
			dir = pv
		elseif dir.Magnitude == 0 and not UIS:GetFocusedTextBox() then
			local cf = camera.CFrame
			local f  = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			local rt = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
			if f.Magnitude > 0 and rt.Magnitude > 0 then
				f, rt = f.Unit, rt.Unit
				local v = Vector3.zero
				if UIS:IsKeyDown(Enum.KeyCode.W) then v += f end
				if UIS:IsKeyDown(Enum.KeyCode.S) then v -= f end
				if UIS:IsKeyDown(Enum.KeyCode.D) then v += rt end
				if UIS:IsKeyDown(Enum.KeyCode.A) then v -= rt end
				if v.Magnitude > 0 then dir = v.Unit end
			end
		end

		local vertical = (state.up and 1 or 0) - (state.down and 1 or 0)
		local move = dir + Vector3.new(0, vertical, 0)
		if move.Magnitude > 0 then
			player.Character:TranslateBy(move * state.flySpeed * 12 * dt)
		end

		local look = camera.CFrame.LookVector
		bg.CFrame = CFrame.lookAt(r.Position, r.Position + Vector3.new(look.X, 0, look.Z))
	end)
end

----------------------------------------------------------------
-- WALK SPEED + JUMP (enforced every frame so the game can't reset them)
----------------------------------------------------------------
local capturedHum
local function readJumpPower(h)
	return h.UseJumpPower and h.JumpPower or math.sqrt(h.JumpHeight * 2 * workspace.Gravity)
end

local function applyStats(h)
	if h ~= capturedHum then -- capture the game's original values before overriding
		capturedHum = h
		defaults.ws = h.WalkSpeed
		defaults.jump = readJumpPower(h)
	end

	if overrideActive() then
		-- Humanoid must not walk by itself: we move the character manually
		if h.WalkSpeed ~= 0 then h.WalkSpeed = 0 end
		wsZeroed = true
	else
		if wsZeroed then
			wsZeroed = false
			h.WalkSpeed = state.ws or defaults.ws
		end
		if state.ws and h.WalkSpeed ~= state.ws then h.WalkSpeed = state.ws end
	end

	if state.jump then
		if h.UseJumpPower then
			if h.JumpPower ~= state.jump then h.JumpPower = state.jump end
		else
			local height = state.jump ^ 2 / (2 * workspace.Gravity)
			if math.abs(h.JumpHeight - height) > 0.01 then h.JumpHeight = height end
		end
	end
end

bind(RunService.Heartbeat, function()
	local h = getParts()
	if h then applyStats(h) end
end)

local function resetWalk()
	state.ws = nil
	local h = getParts()
	if h and not overrideActive() then h.WalkSpeed = defaults.ws end
end

local function resetJump()
	state.jump = nil
	local h = getParts()
	if h then
		if h.UseJumpPower then h.JumpPower = defaults.jump
		else h.JumpHeight = defaults.jump ^ 2 / (2 * workspace.Gravity) end
	end
end

-- Infinite jump
bind(UIS.JumpRequest, function()
	if not state.infJump then return end
	local h = getParts()
	if h and not (state.flying and state.mode == "fly") then
		h:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

----------------------------------------------------------------
-- EMOTE (stays active while moving when "Keep emote" is on)
-- While an emote is held we (1) disable Animate, (2) kill its low-priority
-- walk/idle tracks, (3) replay the emote instantly if anything stops it.
----------------------------------------------------------------
local emoteTrack, emoteId, emotePos = nil, nil, 0
local animateOverridden = false
local wasEmoteActive = false

local function stopEmote()
	if emoteTrack then pcall(function() emoteTrack:Stop() end) emoteTrack = nil end
end

local function clearEmote()
	emoteId, emotePos = nil, 0
	stopEmote()
end

local function suppressAnimate(on)
	if on == animateSuppressed then return end
	animateSuppressed = on
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	if not animate then return end
	if on then
		animate.Disabled = true
	elseif not flyDisabled then
		animate.Disabled = false
	end
end

local function findEmoteId(hum, name)
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	local sv = animate and (animate:FindFirstChild(name) or animate:FindFirstChild(string.lower(name)))
	if sv then
		local anims = sv:GetChildren()
		local a = anims[math.random(1, math.max(#anims, 1))]
		if a and a:IsA("Animation") then return a.AnimationId end
	end
	local desc = hum:FindFirstChildOfClass("HumanoidDescription")
	if desc then
		local ok, emotes = pcall(function() return desc:GetEmotes() end)
		if ok and emotes then
			local ids = emotes[name]
			if not ids then
				for k, v in pairs(emotes) do
					if string.lower(k) == string.lower(name) then ids = v break end
				end
			end
			if ids and ids[1] then return "rbxassetid://" .. tostring(ids[1]) end
		end
	end
end

local function playEmoteById(hum, id, startPos)
	stopEmote()
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local animator = hum:FindFirstChildOfClass("Animator") or hum
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then return false end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	track:Play()
	if startPos and startPos > 0 then pcall(function() track.TimePosition = startPos end) end
	emoteTrack, emoteId = track, id
	return true
end

local function playEmote(name)
	local hum = getParts()
	if not hum then return false end
	local id = findEmoteId(hum, tostring(name))
	if not id then return false end
	emotePos = 0
	return playEmoteById(hum, id)
end

-- If an emote is already playing when the option is enabled, take it over
local function adoptEmote()
	local hum = getParts()
	if not hum then return end
	local known = {}
	local function add(id) local n = string.match(tostring(id), "%d+") if n then known[n] = true end end
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	if animate then
		for _, v in ipairs(animate:GetChildren()) do
			if v:IsA("StringValue") then
				for _, a in ipairs(v:GetChildren()) do if a:IsA("Animation") then add(a.AnimationId) end end
			end
		end
	end
	local desc = hum:FindFirstChildOfClass("HumanoidDescription")
	if desc then
		local ok, emotes = pcall(function() return desc:GetEmotes() end)
		if ok and emotes then
			for _, ids in pairs(emotes) do for _, id in ipairs(ids) do add(id) end end
		end
	end
	for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
		local aid = track.Animation and track.Animation.AnimationId
		local n = aid and string.match(aid, "%d+")
		if n and known[n] and track ~= emoteTrack then
			local pos = track.TimePosition
			track:Stop(0)
			playEmoteById(hum, aid, pos)
			return
		end
	end
end

local function emoteHandler(name) return playEmote(name) end

local function installEmote()
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	local pe = animate and animate:FindFirstChild("PlayEmote")
	if pe and pe:IsA("BindableFunction") then
		pe.OnInvoke = emoteHandler
		animateOverridden = true
	end
end

local function restoreAnimate()
	if emoteActive() then return end -- Override / D-Pad still need the emote hold
	clearEmote()
	suppressAnimate(false)
	if not animateOverridden then return end
	animateOverridden = false
	if flyDisabled then return end
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	if animate then
		task.spawn(function()
			animate.Disabled = true
			task.wait()
			animate.Disabled = false
		end)
	end
end

bind(RunService.Heartbeat, function()
	local h = getParts()
	if not h then return end
	local active = emoteActive()
	if active then
		installEmote() -- keep our emote hook alive (Animate can reset it)
		if not wasEmoteActive then adoptEmote() end
		wasEmoteActive = true
	elseif wasEmoteActive then
		wasEmoteActive = false
		restoreAnimate()
		return
	end
	if active and emoteId then
		suppressAnimate(true)
		-- replay instantly if something stopped the emote
		if not (emoteTrack and emoteTrack.IsPlaying) then
			playEmoteById(h, emoteId, emotePos)
		end
		if emoteTrack then emotePos = emoteTrack.TimePosition end
		-- keep walk/idle animations from fighting the emote
		for _, t in ipairs(h:GetPlayingAnimationTracks()) do
			if t ~= emoteTrack then
				local p = t.Priority
				if p == Enum.AnimationPriority.Core or p == Enum.AnimationPriority.Idle
					or p == Enum.AnimationPriority.Movement then
					t:Stop(0)
				end
			end
		end
	else
		suppressAnimate(false)
	end
end)

----------------------------------------------------------------
-- CONTROL
----------------------------------------------------------------
local function shutdown()
	stopFly()
	restoreAnimate()
end

local function toggleFly()
	if state.flying then
		shutdown()
	else
		if state.mode == "air" then startAirWalk() else startFly() end
		if state.flying then installEmote() adoptEmote() end
	end
end

bind(player.CharacterAdded, function()
	flyDisabled = false
	animateOverridden = false
	animateSuppressed = false
	wsZeroed = false
	emoteTrack, emoteId, emotePos = nil, nil, 0
	stopFly()
	state.up, state.down = false, false
	pad.f, pad.b, pad.l, pad.r = false, false, false, false
end)

----------------------------------------------------------------
-- UI (compact)
----------------------------------------------------------------
local ACCENT = Color3.fromRGB(110, 190, 255)
local WHITE  = Color3.new(1, 1, 1)
local DARK   = Color3.fromRGB(16, 16, 22)
local INK    = Color3.fromRGB(10, 10, 15)
local PANEL_W, PANEL_H = 196, 262
local X0, ROW = 8, 26
local Y = { 34, 66, 98, 130, 162, 194, 228 } -- row positions

local gui = Instance.new("ScreenGui")
gui.Name = "FlyGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
end

local function label(parent, text, size, pos, textSize, font)
	local l = Instance.new("TextLabel")
	l.Size, l.Position = size, pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = font or Enum.Font.Gotham
	l.TextSize = textSize or 12
	l.TextColor3 = WHITE
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent, text, size, pos)
	local b = Instance.new("TextButton")
	b.Size, b.Position = size, pos
	b.BackgroundColor3 = WHITE
	b.BackgroundTransparency = 0.9
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.TextColor3 = WHITE
	b.Parent = parent
	corner(b, 6)
	return b
end

-- press-and-hold helper (mouse + touch)
local function holdBtn(btn, set)
	btn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			set(true)
		end
	end)
	btn.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			set(false)
		end
	end)
end

local refreshers = {}
local function reg(fn) table.insert(refreshers, fn) fn() end
local function refresh() for _, fn in ipairs(refreshers) do fn() end end

-- main panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position = UDim2.fromScale(0.04, 0.3)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = WHITE
stroke.Transparency = 0.85
stroke.Parent = panel

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundTransparency = 1
header.Parent = panel
label(header, "FLY", UDim2.fromOffset(34, 30), UDim2.fromOffset(10, 0), 13, Enum.Font.GothamBold)
local badge = label(header, "UNIVERSAL", UDim2.fromOffset(62, 16), UDim2.fromOffset(46, 7), 9, Enum.Font.GothamBold)
badge.TextXAlignment = Enum.TextXAlignment.Center
badge.TextColor3 = INK
badge.BackgroundTransparency = 0
badge.BackgroundColor3 = ACCENT
corner(badge, 8)
local btnMin   = button(header, "–", UDim2.fromOffset(22, 20), UDim2.new(1, -50, 0, 5))
local btnClose = button(header, "×", UDim2.fromOffset(22, 20), UDim2.new(1, -26, 0, 5))

-- row 1: flight, mode, up, down
local btnFly = button(panel, "FLY", UDim2.fromOffset(70, ROW), UDim2.fromOffset(X0, Y[1]))
local btnMode = button(panel, "", UDim2.fromOffset(46, ROW), UDim2.fromOffset(X0 + 74, Y[1]))
local btnUp   = button(panel, "▲", UDim2.fromOffset(26, ROW), UDim2.fromOffset(X0 + 124, Y[1]))
local btnDown = button(panel, "▼", UDim2.fromOffset(26, ROW), UDim2.fromOffset(X0 + 154, Y[1]))
btnFly.TextSize, btnMode.TextSize = 11, 11
holdBtn(btnUp, function(v) state.up = v end)
holdBtn(btnDown, function(v) state.down = v end)
reg(function()
	btnFly.BackgroundColor3 = state.flying and ACCENT or WHITE
	btnFly.BackgroundTransparency = state.flying and 0.5 or 0.9
	btnFly.TextColor3 = state.flying and INK or WHITE
	btnMode.Text = state.mode == "air" and "AIR" or "FREE"
end)
btnFly.MouseButton1Click:Connect(function() toggleFly() refresh() end)
btnMode.MouseButton1Click:Connect(function()
	shutdown()
	state.mode = state.mode == "air" and "fly" or "air"
	refresh()
end)

-- number rows: [label] [-] [type a value] [+]   (empty box = reset to game default)
local function numRow(y, text, get, step, min, max, set, reset)
	label(panel, text, UDim2.fromOffset(42, ROW), UDim2.fromOffset(X0, y), 12)
	local minus = button(panel, "-", UDim2.fromOffset(30, ROW), UDim2.fromOffset(X0 + 44, y))
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(64, ROW)
	box.Position = UDim2.fromOffset(X0 + 78, y)
	box.BackgroundColor3 = WHITE
	box.BackgroundTransparency = 0.85
	box.BorderSizePixel = 0
	box.Font = Enum.Font.GothamBold
	box.TextSize = 12
	box.TextColor3 = WHITE
	box.PlaceholderText = "default"
	box.PlaceholderColor3 = Color3.fromRGB(170, 170, 180)
	box.ClearTextOnFocus = false
	box.Parent = panel
	corner(box, 6)
	local plus = button(panel, "+", UDim2.fromOffset(30, ROW), UDim2.fromOffset(X0 + 146, y))

	reg(function() box.Text = tostring(math.floor(get() + 0.5)) end)
	minus.MouseButton1Click:Connect(function() set(math.clamp(get() - step, min, max)) refresh() end)
	plus.MouseButton1Click:Connect(function() set(math.clamp(get() + step, min, max)) refresh() end)
	box.FocusLost:Connect(function()
		if box.Text == "" then
			if reset then reset() end
		else
			local n = tonumber(box.Text)
			if n then set(math.clamp(n, min, max)) end
		end
		refresh()
	end)
end

numRow(Y[2], "Fly", function() return state.flySpeed end, 1, 1, 50,
	function(v) state.flySpeed = v end, function() state.flySpeed = 5 end)
numRow(Y[3], "Walk", function() return state.ws or defaults.ws end, 4, 1, 300,
	function(v) state.ws = v end, resetWalk)
numRow(Y[4], "Jump", function() return state.jump or defaults.jump end, 10, 1, 500,
	function(v) state.jump = v end, resetJump)

-- toggles
local function toggle(x, y, w, text, get, onClick)
	local b = button(panel, text, UDim2.fromOffset(w, ROW), UDim2.fromOffset(x, y))
	b.TextSize = 11
	reg(function()
		local on = get()
		b.BackgroundColor3 = on and ACCENT or WHITE
		b.BackgroundTransparency = on and 0.5 or 0.9
		b.TextColor3 = on and INK or WHITE
	end)
	b.MouseButton1Click:Connect(function() onClick() refresh() end)
	return b
end

toggle(X0, Y[5], 86, "INF JUMP", function() return state.infJump end,
	function() state.infJump = not state.infJump end)
toggle(X0 + 90, Y[5], 90, "OVERRIDE", function() return state.override end,
	function() state.override = not state.override end)
toggle(X0, Y[6], 86, "D-PAD", function() return state.showPad end,
	function() state.showPad = not state.showPad end)
local btnStop = button(panel, "STOP EMOTE", UDim2.fromOffset(90, ROW), UDim2.fromOffset(X0 + 90, Y[6]))
btnStop.TextSize = 11
btnStop.MouseButton1Click:Connect(function() clearEmote() end)

-- D-Pad (separate floating, draggable window)
local dpad = Instance.new("Frame")
dpad.Name = "DPad"
dpad.Size = UDim2.fromOffset(196, 172)
dpad.Position = UDim2.new(1, -216, 1, -200)
dpad.BackgroundColor3 = DARK
dpad.BackgroundTransparency = 0.5
dpad.BorderSizePixel = 0
dpad.Visible = false
dpad.Parent = gui
corner(dpad, 12)
local dpStroke = stroke:Clone()
dpStroke.Parent = dpad

local dpadHandle = Instance.new("Frame")
dpadHandle.Size = UDim2.new(1, 0, 0, 20)
dpadHandle.BackgroundTransparency = 1
dpadHandle.Parent = dpad
local dpTitle = label(dpadHandle, "D-PAD", UDim2.fromScale(1, 1), UDim2.new(), 9, Enum.Font.GothamBold)
dpTitle.TextXAlignment = Enum.TextXAlignment.Center
dpTitle.TextTransparency = 0.4

local function padBtn(text, x, y, w, h, set, textSize)
	local b = button(dpad, text, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y))
	b.TextSize = textSize or 16
	holdBtn(b, set)
	return b
end
padBtn("▲", 56, 24, 44, 44, function(v) pad.f = v end)
padBtn("◀", 8, 72, 44, 44, function(v) pad.l = v end)
padBtn("▶", 104, 72, 44, 44, function(v) pad.r = v end)
padBtn("▼", 56, 120, 44, 44, function(v) pad.b = v end)
padBtn("UP", 152, 24, 36, 68, function(v) state.up = v end, 11)
padBtn("DN", 152, 96, 36, 68, function(v) state.down = v end, 11)
reg(function() dpad.Visible = state.showPad end)

-- teleport: pick a player from the dropdown, then press TP
local selected
local btnDrop = button(panel, "", UDim2.fromOffset(122, ROW), UDim2.fromOffset(X0, Y[7]))
btnDrop.TextXAlignment = Enum.TextXAlignment.Left
btnDrop.TextTruncate = Enum.TextTruncate.AtEnd
btnDrop.TextSize = 11
local dropPad = Instance.new("UIPadding")
dropPad.PaddingLeft = UDim.new(0, 8)
dropPad.PaddingRight = UDim.new(0, 6)
dropPad.Parent = btnDrop
local btnTp = button(panel, "TP", UDim2.fromOffset(52, ROW), UDim2.fromOffset(X0 + 128, Y[7]))
btnTp.TextSize = 11
btnTp.BackgroundColor3 = ACCENT
btnTp.BackgroundTransparency = 0.5

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.fromOffset(180, 112)
list.Position = UDim2.fromOffset(X0, Y[7] - 118)
list.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
list.BackgroundTransparency = 0.05
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 10
list.Visible = false
list.Parent = panel
corner(list, 6)
local ll = Instance.new("UIListLayout")
ll.Padding = UDim.new(0, 2)
ll.Parent = list

reg(function()
	btnDrop.Text = (selected and selected.DisplayName or "Select player") .. "  ▾"
end)

local function renderPlayers()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local b = button(list, p.DisplayName .. " (@" .. p.Name .. ")", UDim2.new(1, -6, 0, 24), UDim2.new())
			b.TextSize = 11
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextTruncate = Enum.TextTruncate.AtEnd
			b.BackgroundColor3 = selected == p and ACCENT or WHITE
			b.BackgroundTransparency = selected == p and 0.5 or 0.9
			b.TextColor3 = selected == p and INK or WHITE
			b.MouseButton1Click:Connect(function()
				selected = p
				list.Visible = false
				refresh()
			end)
		end
	end
end

btnDrop.MouseButton1Click:Connect(function()
	list.Visible = not list.Visible
	if list.Visible then renderPlayers() end
end)

local function teleportTo(target)
	local _, root = getParts()
	local tc = target and target.Character
	local troot = tc and tc:FindFirstChild("HumanoidRootPart")
	if not (root and troot) then return false end
	local wasAir = state.flying and state.mode == "air"
	root.CFrame = troot.CFrame * CFrame.new(0, 0, 3)
	root.AssemblyLinearVelocity = Vector3.zero
	if wasAir then
		startAirWalk()
		installEmote()
	end
	return true
end

btnTp.MouseButton1Click:Connect(function()
	list.Visible = false
	local ok = selected and teleportTo(selected)
	btnTp.Text = ok and "✓" or "✗"
	task.delay(1, function() btnTp.Text = "TP" end)
end)

bind(Players.PlayerAdded, function() if list.Visible then renderPlayers() end end)
bind(Players.PlayerRemoving, function(p)
	if selected == p then selected = nil refresh() end
	task.defer(function() if list.Visible then renderPlayers() end end)
end)

-- minimize
local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(34, 34)
mini.BackgroundColor3 = DARK
mini.BackgroundTransparency = 0.35
mini.BorderSizePixel = 0
mini.Text = "✈"
mini.TextSize = 16
mini.Font = Enum.Font.GothamBold
mini.TextColor3 = WHITE
mini.Visible = false
mini.Parent = gui
corner(mini, 17)
local miniStroke = stroke:Clone()
miniStroke.Parent = mini
reg(function() mini.TextColor3 = state.flying and ACCENT or WHITE end)

btnMin.MouseButton1Click:Connect(function()
	list.Visible = false
	mini.Position = panel.Position
	panel.Visible = false
	mini.Visible = true
end)
mini.MouseButton1Click:Connect(function()
	panel.Position = mini.Position
	mini.Visible = false
	panel.Visible = true
end)

-- hotkeys
bind(UIS.InputBegan, function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.E then state.up = true
	elseif i.KeyCode == Enum.KeyCode.Q then state.down = true
	elseif i.KeyCode == Enum.KeyCode.F then toggleFly() refresh() end
end)
bind(UIS.InputEnded, function(i)
	if i.KeyCode == Enum.KeyCode.E then state.up = false
	elseif i.KeyCode == Enum.KeyCode.Q then state.down = false end
end)

-- close
btnClose.MouseButton1Click:Connect(function()
	state.override = false
	state.showPad = false
	shutdown()
	resetWalk()
	resetJump()
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
end)

-- drag (header, D-Pad handle, mini)
local function makeDraggable(handle, target)
	local dragging, startPos, startInput
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startInput, startPos = true, i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	bind(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end
makeDraggable(header, panel)
makeDraggable(dpadHandle, dpad)
makeDraggable(mini, mini)

refresh()
