-- Movement Hub (UNIVERSAL: client-side, works in any game)
-- Features: Fly/AirWalk, Walk Speed, Jump Power, Infinite Jump, persistent Emote while moving, Teleport to player
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
	ws = nil, jump = nil, infJump = false, emote = false,
}
local defaults = { ws = 16, jump = 50 }
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local bv, bg, flyConn, platform
local flyDisabled = false

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
		if dir.Magnitude == 0 and not UIS:GetFocusedTextBox() then
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
	if state.ws and h.WalkSpeed ~= state.ws then h.WalkSpeed = state.ws end
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
	if h then h.WalkSpeed = defaults.ws end
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
-- Same idea as the Up/Down case: the emote must not depend on the
-- default Animate script. While an emote is held we (1) disable Animate,
-- (2) kill its low-priority walk/idle tracks, (3) replay the emote
-- instantly if anything stops it.
----------------------------------------------------------------
local emoteTrack, emoteId, emotePos = nil, nil, 0
local animateOverridden, animateSuppressed = false, false

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

local function installEmote()
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	local pe = animate and animate:FindFirstChild("PlayEmote")
	if pe and pe:IsA("BindableFunction") then
		pe.OnInvoke = function(name) return playEmote(name) end
		animateOverridden = true
	end
end

local function restoreAnimate()
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
	if state.emote and state.flying and emoteId then
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
		if emoteTrack or emoteId then clearEmote() end
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
		if state.flying and state.emote then installEmote() adoptEmote() end
	end
end

bind(player.CharacterAdded, function()
	flyDisabled = false
	animateOverridden = false
	animateSuppressed = false
	emoteTrack, emoteId, emotePos = nil, nil, 0
	stopFly()
	state.up, state.down = false, false
end)

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local ACCENT = Color3.fromRGB(110, 190, 255)
local WHITE  = Color3.new(1, 1, 1)
local PANEL_W, PANEL_H = 230, 300

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

local refreshers = {}
local function reg(fn) table.insert(refreshers, fn) fn() end
local function refresh() for _, fn in ipairs(refreshers) do fn() end end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position = UDim2.fromScale(0.04, 0.35)
panel.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
panel.BackgroundTransparency = 0.82
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
label(header, "Movement Hub", UDim2.fromOffset(110, 30), UDim2.fromOffset(10, 0), 13, Enum.Font.GothamBold)
local badge = label(header, "UNIVERSAL", UDim2.fromOffset(64, 16), UDim2.fromOffset(104, 7), 9, Enum.Font.GothamBold)
badge.TextXAlignment = Enum.TextXAlignment.Center
badge.TextColor3 = Color3.fromRGB(15, 15, 20)
badge.BackgroundTransparency = 0
badge.BackgroundColor3 = ACCENT
corner(badge, 8)
local btnMin   = button(header, "–", UDim2.fromOffset(22, 20), UDim2.new(1, -50, 0, 5))
local btnClose = button(header, "×", UDim2.fromOffset(22, 20), UDim2.new(1, -26, 0, 5))

-- tabs
local tabNames = { "MOVE", "FLY", "PLAYERS" }
local tabs, pages = {}, {}
for i, name in ipairs(tabNames) do
	tabs[name] = button(panel, name, UDim2.fromOffset(66, 22), UDim2.fromOffset(8 + (i - 1) * 71, 32))
	tabs[name].TextSize = 11
end

local function newPage(layout)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -16, 0, 196)
	f.Position = UDim2.fromOffset(8, 60)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = panel
	if layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
	end
	return f
end
pages.MOVE, pages.FLY, pages.PLAYERS = newPage(true), newPage(true), newPage(false)

local order = 0
local function row(parent)
	order += 1
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, 0, 0, 28)
	r.BackgroundTransparency = 1
	r.LayoutOrder = order
	r.Parent = parent
	return r
end

-- [label]  [-]  value  [+]  [R]
local function stepper(parent, text, get, step, min, max, set, reset)
	local r = row(parent)
	label(r, text, UDim2.fromOffset(70, 28), UDim2.fromOffset(2, 0), 12)
	local minus = button(r, "-", UDim2.fromOffset(28, 28), UDim2.fromOffset(72, 0))
	local val = label(r, "", UDim2.fromOffset(40, 28), UDim2.fromOffset(102, 0), 12, Enum.Font.GothamBold)
	val.TextXAlignment = Enum.TextXAlignment.Center
	local plus = button(r, "+", UDim2.fromOffset(28, 28), UDim2.fromOffset(144, 0))
	local rst = button(r, "R", UDim2.fromOffset(28, 28), UDim2.fromOffset(176, 0))
	reg(function() val.Text = tostring(math.floor(get() + 0.5)) end)
	minus.MouseButton1Click:Connect(function() set(math.clamp(get() - step, min, max)) refresh() end)
	plus.MouseButton1Click:Connect(function() set(math.clamp(get() + step, min, max)) refresh() end)
	rst.MouseButton1Click:Connect(function() reset() refresh() end)
end

local function toggleRow(parent, text, get, onClick)
	local r = row(parent)
	local b = button(r, "", UDim2.fromScale(1, 1), UDim2.new())
	b.TextXAlignment = Enum.TextXAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = b
	reg(function()
		local on = get()
		b.Text = (on and "●  " or "○  ") .. text
		b.BackgroundColor3 = on and ACCENT or WHITE
		b.BackgroundTransparency = on and 0.55 or 0.9
	end)
	b.MouseButton1Click:Connect(function() onClick() refresh() end)
	return b
end

local function note(parent, text, height)
	order += 1
	local l = label(parent, text, UDim2.new(1, 0, 0, height or 30), UDim2.new(), 10)
	l.TextWrapped = true
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextTransparency = 0.35
	l.LayoutOrder = order
	return l
end

-- MOVE page
stepper(pages.MOVE, "Walk", function() return state.ws or defaults.ws end,
	4, 4, 200, function(v) state.ws = v end, resetWalk)
stepper(pages.MOVE, "Jump", function() return state.jump or defaults.jump end,
	10, 10, 300, function(v) state.jump = v end, resetJump)
toggleRow(pages.MOVE, "Infinite Jump", function() return state.infJump end,
	function() state.infJump = not state.infJump end)
note(pages.MOVE, "Infinite Jump: tap Jump repeatedly in mid-air to keep jumping. R = restore the game's original value.", 42)

-- FLY page
toggleRow(pages.FLY, "Flight", function() return state.flying end, toggleFly)
do
	local r = row(pages.FLY)
	local b = button(r, "", UDim2.fromScale(1, 1), UDim2.new())
	reg(function()
		b.Text = state.mode == "air" and "Mode: AirWalk (walk on air)" or "Mode: Fly (free flight)"
	end)
	b.MouseButton1Click:Connect(function()
		shutdown()
		state.mode = state.mode == "air" and "fly" or "air"
		refresh()
	end)
end
stepper(pages.FLY, "Fly speed", function() return state.flySpeed end,
	1, 1, 20, function(v) state.flySpeed = v end, function() state.flySpeed = 5 end)
toggleRow(pages.FLY, "Keep emote while moving", function() return state.emote end, function()
	state.emote = not state.emote
	if state.emote then
		if state.flying then installEmote() adoptEmote() end
	else
		restoreAnimate()
	end
end)
do
	local r = row(pages.FLY)
	local up   = button(r, "▲ Up (E)", UDim2.new(0.5, -3, 1, 0), UDim2.new())
	local down = button(r, "▼ Down (Q)", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0))
	local function hold(btn, key)
		btn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				state[key] = true
			end
		end)
		btn.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				state[key] = false
			end
		end)
	end
	hold(up, "up")
	hold(down, "down")
end
note(pages.FLY, "F = toggle flight. Start an emote while Flight + Keep emote are on. Turn Keep emote off to cancel it.", 26)

-- PLAYERS page (teleports only YOUR character to the target)
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, 0, 0, 110)
list.BackgroundColor3 = WHITE
list.BackgroundTransparency = 0.94
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = pages.PLAYERS
corner(list, 6)
local ll = Instance.new("UIListLayout")
ll.Padding = UDim.new(0, 2)
ll.Parent = list

local btnTp  = button(pages.PLAYERS, "TELEPORT", UDim2.new(1, -56, 0, 28), UDim2.fromOffset(0, 118))
local btnRef = button(pages.PLAYERS, "⟳", UDim2.fromOffset(50, 28), UDim2.new(1, -50, 0, 118))
local lblSel = label(pages.PLAYERS, "Select a player first", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 152), 11)
lblSel.TextTruncate = Enum.TextTruncate.AtEnd

local selected
local function renderPlayers()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local b = button(list, p.DisplayName .. " (@" .. p.Name .. ")", UDim2.new(1, -6, 0, 22), UDim2.new())
			b.TextSize = 11
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextTruncate = Enum.TextTruncate.AtEnd
			b.BackgroundColor3 = selected == p and ACCENT or WHITE
			b.BackgroundTransparency = selected == p and 0.55 or 0.9
			b.MouseButton1Click:Connect(function()
				selected = p
				lblSel.Text = "Selected: " .. p.Name
				renderPlayers()
			end)
		end
	end
end

local function teleportTo(target)
	local _, root = getParts()
	local tc = target and target.Character
	local troot = tc and tc:FindFirstChild("HumanoidRootPart")
	if not (root and troot) then lblSel.Text = "Player not found" return end
	local wasAir = state.flying and state.mode == "air"
	root.CFrame = troot.CFrame * CFrame.new(0, 0, 3)
	root.AssemblyLinearVelocity = Vector3.zero
	if wasAir then
		startAirWalk()
		if state.emote then installEmote() end
	end
	lblSel.Text = "Teleported to " .. target.Name
end

btnTp.MouseButton1Click:Connect(function()
	if selected then teleportTo(selected) else lblSel.Text = "Select a player first" end
end)
btnRef.MouseButton1Click:Connect(renderPlayers)
bind(Players.PlayerAdded, function() renderPlayers() end)
bind(Players.PlayerRemoving, function(p)
	if selected == p then selected = nil lblSel.Text = "Select a player first" end
	task.defer(renderPlayers)
end)

-- footer info
local footer = label(panel, "🌐 Universal: works in any game (client-side). Games with anti-cheat or server checks may reset values.",
	UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 1, -38), 9)
footer.TextWrapped = true
footer.TextYAlignment = Enum.TextYAlignment.Top
footer.TextTransparency = 0.4

-- tab switching
local function showTab(name)
	for n, page in pairs(pages) do
		page.Visible = (n == name)
		tabs[n].BackgroundColor3 = n == name and ACCENT or WHITE
		tabs[n].BackgroundTransparency = n == name and 0.55 or 0.9
	end
	if name == "PLAYERS" then renderPlayers() end
end
for name, b in pairs(tabs) do
	b.MouseButton1Click:Connect(function() showTab(name) end)
end
showTab("MOVE")

-- minimize
local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(34, 34)
mini.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
mini.BackgroundTransparency = 0.45
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
	shutdown()
	resetWalk()
	resetJump()
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
end)

-- drag (header + mini)
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
makeDraggable(mini, mini)

refresh()
