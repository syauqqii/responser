local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local old = player.PlayerGui:FindFirstChild("FlyGUI")
if old then old:Destroy() end

local state = { flying = false, speed = 5, up = false, down = false, mode = "air" }
local MIN_SPEED, MAX_SPEED, SPEED_MULT = 1, 20, 10
local bv, bg, conn, platform
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

local function stopFly()
	state.flying = false
	if conn then conn:Disconnect() conn = nil end
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
	platform.Size = Vector3.new(10, 1, 10)
	platform.Anchored = true
	platform.CanCollide = true
	platform.Transparency = 1
	platform.Name = "AirWalkPlatform"
	platform.Parent = workspace

	conn = RunService.RenderStepped:Connect(function(dt)
		local h, r = getParts()
		if not (h and r and h.Health > 0) then return stopFly() end
		level += ((state.up and 1 or 0) - (state.down and 1 or 0)) * state.speed * 5 * dt
		platform.CFrame = CFrame.new(r.Position.X, level - 0.5, r.Position.Z)
	end)
end

local function startFly()
	local hum, root = getParts()
	if not (hum and root) then return end
	stopFly()
	state.flying = true
	flyDisabled = true

	local char = player.Character
	local animate = char:FindFirstChild("Animate")
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

	conn = RunService.RenderStepped:Connect(function(dt)
		local h, r = getParts()
		if not (h and r and h.Health > 0) then return stopFly() end

		local dir = h.MoveDirection
		if dir.Magnitude == 0 and not UIS:GetFocusedTextBox() then
			local cf = camera.CFrame
			local f = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
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
			player.Character:TranslateBy(move * state.speed * 12 * dt)
		end

		local look = camera.CFrame.LookVector
		bg.CFrame = CFrame.lookAt(r.Position, r.Position + Vector3.new(look.X, 0, look.Z))
	end)
end

local defaultWS = (getParts() and getParts().WalkSpeed) or 16
local WS_MIN, WS_MAX, WS_STEP = 2, 150, 2
local wsConn = RunService.Heartbeat:Connect(function()
	local h = getParts()
	if h and state.ws and h.WalkSpeed ~= state.ws then h.WalkSpeed = state.ws end
end)

local function changeWS(delta)
	local cur = state.ws or defaultWS
	state.ws = math.clamp(cur + delta, WS_MIN, WS_MAX)
end

local function resetWS()
	state.ws = nil
	local h = getParts()
	if h then h.WalkSpeed = defaultWS end
end

state.emote = false
local emoteTrack, animateOverridden = nil, false

local function stopEmote()
	if emoteTrack then pcall(function() emoteTrack:Stop() end) emoteTrack = nil end
end

local function findEmoteId(hum, name)
	local char = player.Character
	local animate = char and char:FindFirstChild("Animate")
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
	if startPos then track.TimePosition = startPos end
	emoteTrack = track
	return true, track
end

local function playEmote(name)
	local hum = getParts()
	if not hum then return false end
	local id = findEmoteId(hum, tostring(name))
	if not id then return false end
	return playEmoteById(hum, id)
end

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
	local char = player.Character
	local animate = char and char:FindFirstChild("Animate")
	local pe = animate and animate:FindFirstChild("PlayEmote")
	if pe and pe:IsA("BindableFunction") then
		pe.OnInvoke = function(name) return playEmote(name) end
		animateOverridden = true
	end
end

local function restoreAnimate()
	stopEmote()
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

local emoteConn = RunService.Heartbeat:Connect(function()
	if not emoteTrack then return end
	local h = getParts()

	local moving = h and (h.MoveDirection.Magnitude > 0 or state.up or state.down)
	if (moving and not state.emote) or not emoteTrack.IsPlaying then stopEmote() end
end)

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

player.CharacterAdded:Connect(function()
	flyDisabled = false
	stopFly()
	state.up, state.down = false, false
end)

local gui = Instance.new("ScreenGui")
gui.Name = "FlyGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local ACCENT = Color3.fromRGB(120, 200, 255)

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function button(parent, text, size, pos)
	local b = Instance.new("TextButton")
	b.Size, b.Position = size, pos
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BackgroundTransparency = 0.88
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	corner(b, 6)
	return b
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(170, 186)
panel.Position = UDim2.fromScale(0.05, 0.4)
panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
panel.BackgroundTransparency = 0.45
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(1, 1, 1)
stroke.Transparency = 0.85
stroke.Parent = panel

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -56, 0, 24)
header.Position = UDim2.fromOffset(10, 2)
header.BackgroundTransparency = 1
header.Text = "FLY"
header.Font = Enum.Font.GothamBold
header.TextSize = 12
header.TextXAlignment = Enum.TextXAlignment.Left
header.TextColor3 = Color3.new(1, 1, 1)
header.Parent = panel

local btnMin   = button(panel, "–", UDim2.fromOffset(22, 20), UDim2.new(1, -50, 0, 4))
local btnClose = button(panel, "×", UDim2.fromOffset(22, 20), UDim2.new(1, -26, 0, 4))

local btnFly  = button(panel, "FLY: OFF", UDim2.fromOffset(70, 26), UDim2.fromOffset(8, 30))
local btnUp   = button(panel, "▲", UDim2.fromOffset(40, 26), UDim2.fromOffset(82, 30))
local btnDown = button(panel, "▼", UDim2.fromOffset(40, 26), UDim2.fromOffset(124, 30))

local btnSub = button(panel, "-", UDim2.fromOffset(40, 26), UDim2.fromOffset(8, 62))
local lblSpd = Instance.new("TextLabel")
lblSpd.Size = UDim2.fromOffset(70, 26)
lblSpd.Position = UDim2.fromOffset(50, 62)
lblSpd.BackgroundTransparency = 1
lblSpd.Text = "SPD " .. state.speed
lblSpd.Font = Enum.Font.Gotham
lblSpd.TextSize = 12
lblSpd.TextColor3 = Color3.new(1, 1, 1)
lblSpd.Parent = panel
local btnAdd = button(panel, "+", UDim2.fromOffset(40, 26), UDim2.fromOffset(122, 62))
btnAdd.Size = UDim2.fromOffset(40, 26)

local btnMode = button(panel, "MODE: AIRWALK", UDim2.fromOffset(154, 26), UDim2.fromOffset(8, 94))

local btnWsSub = button(panel, "-", UDim2.fromOffset(36, 26), UDim2.fromOffset(8, 124))
local lblWs = Instance.new("TextLabel")
lblWs.Size = UDim2.fromOffset(54, 26)
lblWs.Position = UDim2.fromOffset(46, 124)
lblWs.BackgroundTransparency = 1
lblWs.Font = Enum.Font.Gotham
lblWs.TextSize = 12
lblWs.TextColor3 = Color3.new(1, 1, 1)
lblWs.Parent = panel
local btnWsAdd = button(panel, "+", UDim2.fromOffset(36, 26), UDim2.fromOffset(102, 124))
local btnWsRst = button(panel, "R", UDim2.fromOffset(22, 26), UDim2.fromOffset(140, 124))

local btnEmote = button(panel, "☐ Allow emote", UDim2.fromOffset(154, 26), UDim2.fromOffset(8, 154))

header.Text = ""
local tabMove    = button(panel, "MOVE", UDim2.fromOffset(52, 20), UDim2.fromOffset(8, 4))
local tabPlayers = button(panel, "PLAYERS", UDim2.fromOffset(62, 20), UDim2.fromOffset(64, 4))
tabMove.TextSize, tabPlayers.TextSize = 11, 11

local pageMove = Instance.new("Frame")
pageMove.Size = UDim2.fromScale(1, 1)
pageMove.BackgroundTransparency = 1
pageMove.Parent = panel
for _, c in ipairs({ btnFly, btnUp, btnDown, btnSub, lblSpd, btnAdd, btnMode,
	btnWsSub, lblWs, btnWsAdd, btnWsRst, btnEmote }) do
	c.Parent = pageMove
end

local pagePlayers = Instance.new("Frame")
pagePlayers.Size = UDim2.fromScale(1, 1)
pagePlayers.BackgroundTransparency = 1
pagePlayers.Visible = false
pagePlayers.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.fromOffset(154, 88)
list.Position = UDim2.fromOffset(8, 30)
list.BackgroundColor3 = Color3.new(1, 1, 1)
list.BackgroundTransparency = 0.92
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = pagePlayers
corner(list, 6)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.Parent = list

local btnTp  = button(pagePlayers, "TELEPORT", UDim2.fromOffset(100, 26), UDim2.fromOffset(8, 122))
local btnRef = button(pagePlayers, "⟳", UDim2.fromOffset(50, 26), UDim2.fromOffset(112, 122))
local lblSel = Instance.new("TextLabel")
lblSel.Size = UDim2.fromOffset(154, 26)
lblSel.Position = UDim2.fromOffset(8, 154)
lblSel.BackgroundTransparency = 1
lblSel.Text = "Pilih player dulu"
lblSel.Font = Enum.Font.Gotham
lblSel.TextSize = 11
lblSel.TextColor3 = Color3.new(1, 1, 1)
lblSel.TextTruncate = Enum.TextTruncate.AtEnd
lblSel.Parent = pagePlayers

local selected
local function renderPlayers()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local row = button(list, p.DisplayName .. " (@" .. p.Name .. ")", UDim2.new(1, -6, 0, 22), UDim2.new())
			row.TextSize = 11
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.BackgroundColor3 = selected == p and ACCENT or Color3.new(1, 1, 1)
			row.BackgroundTransparency = selected == p and 0.55 or 0.9
			row.MouseButton1Click:Connect(function()
				selected = p
				lblSel.Text = "Dipilih: " .. p.Name
				renderPlayers()
			end)
		end
	end
end

local function teleportTo(target)
	local _, root = getParts()
	local tc = target and target.Character
	local troot = tc and tc:FindFirstChild("HumanoidRootPart")
	if not (root and troot) then lblSel.Text = "Player tidak ditemukan" return end
	local wasAir = state.flying and state.mode == "air"
	root.CFrame = troot.CFrame * CFrame.new(0, 0, 3)
	root.AssemblyLinearVelocity = Vector3.zero
	if wasAir then
		startAirWalk()
		if state.emote then installEmote() end
	end
	lblSel.Text = "Teleport ke " .. target.Name
end

btnTp.MouseButton1Click:Connect(function()
	if selected then teleportTo(selected) else lblSel.Text = "Pilih player dulu" end
end)
btnRef.MouseButton1Click:Connect(renderPlayers)

local plrConns = {
	Players.PlayerAdded:Connect(function() renderPlayers() end),
	Players.PlayerRemoving:Connect(function(p)
		if selected == p then selected = nil lblSel.Text = "Pilih player dulu" end
		task.defer(renderPlayers)
	end),
}

local function showTab(name)
	pageMove.Visible = name == "move"
	pagePlayers.Visible = name == "players"
	tabMove.BackgroundTransparency = name == "move" and 0.6 or 0.9
	tabPlayers.BackgroundTransparency = name == "players" and 0.6 or 0.9
end
tabMove.MouseButton1Click:Connect(function() showTab("move") end)
tabPlayers.MouseButton1Click:Connect(function() renderPlayers() showTab("players") end)
showTab("move")

local mini = Instance.new("TextButton")
mini.Name = "Mini"
mini.Size = UDim2.fromOffset(34, 34)
mini.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mini.BackgroundTransparency = 0.45
mini.BorderSizePixel = 0
mini.Text = "✈"
mini.TextSize = 16
mini.Font = Enum.Font.GothamBold
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Visible = false
mini.Parent = gui
corner(mini, 17)
local miniStroke = stroke:Clone()
miniStroke.Parent = mini

local function refresh()
	btnFly.Text = state.flying and "FLY: ON" or "FLY: OFF"
	btnFly.BackgroundColor3 = state.flying and ACCENT or Color3.new(1, 1, 1)
	btnFly.BackgroundTransparency = state.flying and 0.55 or 0.88
	lblSpd.Text = "SPD " .. state.speed
	lblWs.Text = "WALK " .. (state.ws or defaultWS)
	btnEmote.Text = (state.emote and "☑" or "☐") .. " Allow emote"
	btnEmote.BackgroundColor3 = state.emote and ACCENT or Color3.new(1, 1, 1)
	btnEmote.BackgroundTransparency = state.emote and 0.55 or 0.88
	btnMode.Text = state.mode == "air" and "MODE: AIRWALK" or "MODE: FLY"
	btnFly.Text = state.flying and (state.mode == "air" and "AIR: ON" or "FLY: ON") or "OFF"
	mini.TextColor3 = state.flying and ACCENT or Color3.new(1, 1, 1)
end

btnFly.MouseButton1Click:Connect(function() toggleFly() refresh() end)
btnWsAdd.MouseButton1Click:Connect(function() changeWS(WS_STEP) refresh() end)
btnWsSub.MouseButton1Click:Connect(function() changeWS(-WS_STEP) refresh() end)
btnWsRst.MouseButton1Click:Connect(function() resetWS() refresh() end)
btnEmote.MouseButton1Click:Connect(function()
	state.emote = not state.emote
	if state.emote then
		if state.flying then installEmote() adoptEmote() end
	else
		restoreAnimate()
	end
	refresh()
end)
btnMode.MouseButton1Click:Connect(function()
	shutdown()
	state.mode = state.mode == "air" and "fly" or "air"
	refresh()
end)
btnAdd.MouseButton1Click:Connect(function() state.speed = math.min(MAX_SPEED, state.speed + 1) refresh() end)
btnSub.MouseButton1Click:Connect(function() state.speed = math.max(MIN_SPEED, state.speed - 1) refresh() end)

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
hold(btnUp, "up")
hold(btnDown, "down")

UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.E then state.up = true
	elseif i.KeyCode == Enum.KeyCode.Q then state.down = true
	elseif i.KeyCode == Enum.KeyCode.F then toggleFly() refresh() end
end)
UIS.InputEnded:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.E then state.up = false
	elseif i.KeyCode == Enum.KeyCode.Q then state.down = false end
end)

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

btnClose.MouseButton1Click:Connect(function()
	shutdown()
	resetWS()
	wsConn:Disconnect()
	emoteConn:Disconnect()
	for _, c in ipairs(plrConns) do c:Disconnect() end
	gui:Destroy()
end)

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
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

makeDraggable(header, panel)
makeDraggable(panel, panel)
makeDraggable(mini, mini)

refresh()
