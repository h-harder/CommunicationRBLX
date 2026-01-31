--[[
CommunicationV1 - First-Time Install (Roblox Studio Command Bar)

Creates:
ReplicatedStorage/CustomChat
  - ModeratorUserId (IntValue) default 0 (blank)
  - SendMessage (RemoteEvent)
  - BroadcastMessage (RemoteEvent)
  - ClearChat (RemoteEvent)
  - DeleteMessages (RemoteEvent)
  - LetterRenderer (ModuleScript)

ServerScriptService/CustomChatServer
StarterPlayer/StarterPlayerScripts/CustomChatClient

Moderator config:
Set moderator ID here:
ReplicatedStorage.CustomChat.ModeratorUserId.Value

If ModeratorUserId is 0/invalid, chat is blocked by an overlay until "Check" confirms a valid ID.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if obj and obj.ClassName == className then
		return obj
	end
	if obj then obj:Destroy() end
	obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

-- Core folder + config
local customFolder = getOrCreate(ReplicatedStorage, "Folder", "CustomChat")

local modIdVal = getOrCreate(customFolder, "IntValue", "ModeratorUserId")
if typeof(modIdVal.Value) ~= "number" then
	modIdVal.Value = 0
end
-- If you want it ALWAYS blank on install, uncomment:
-- modIdVal.Value = 0

getOrCreate(customFolder, "RemoteEvent", "SendMessage")
getOrCreate(customFolder, "RemoteEvent", "BroadcastMessage")
getOrCreate(customFolder, "RemoteEvent", "ClearChat")
getOrCreate(customFolder, "RemoteEvent", "DeleteMessages")

-- Letter renderer
local letterModule = getOrCreate(customFolder, "ModuleScript", "LetterRenderer")
letterModule.Source = [[
local TweenService = game:GetService("TweenService")

local LetterRenderer = {}

local DEFAULTS = {
	CharDelay = 0.014,
	PunctuationDelay = 0.08,
	MaxLength = 350,
	FadeIn = true,
}

local function merge(opts)
	local out = {}
	for k,v in pairs(DEFAULTS) do out[k] = v end
	if typeof(opts) == "table" then
		for k,v in pairs(opts) do out[k] = v end
	end
	return out
end

local function isPunct(ch)
	return ch == "." or ch == "," or ch == "!" or ch == "?" or ch == ":" or ch == ";" or ch == "\n"
end

function LetterRenderer.Render(gui, text, opts)
	if not gui or not gui:IsA("GuiObject") then return end
	local ok = pcall(function() return gui.Text end)
	if not ok then return end

	local o = merge(opts)
	text = tostring(text or "")
	if #text > o.MaxLength then
		text = text:sub(1, o.MaxLength) .. "…"
	end

	gui.Text = ""
	if o.FadeIn then
		gui.TextTransparency = 1
		TweenService:Create(gui, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0
		}):Play()
	end

	for i = 1, #text do
		gui.Text = text:sub(1, i)
		local ch = text:sub(i, i)
		task.wait(isPunct(ch) and o.PunctuationDelay or o.CharDelay)
	end
end

return LetterRenderer
]]

-- Server script
local serverScript = getOrCreate(ServerScriptService, "Script", "CustomChatServer")
serverScript.Source = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("CustomChat")
local ModeratorUserId = folder:WaitForChild("ModeratorUserId")
local SendMessage = folder:WaitForChild("SendMessage")
local BroadcastMessage = folder:WaitForChild("BroadcastMessage")
local ClearChat = folder:WaitForChild("ClearChat")
local DeleteMessages = folder:WaitForChild("DeleteMessages")

local MAX_LEN = 200
local RATE_LIMIT_SECONDS = 0.35

-- Commands
local CMD_CLEAR_ALL   = "/clear all"
local CMD_CLEAR_ME    = "/clear me"
local CMD_PAUSECHAT   = "/pausechat"
local CMD_MUTE        = "/mute"
local CMD_MSGDELETE   = "/msgdelete"
local CMD_REMOVECHAT  = "/removechat"
local CMD_GIVECHAT    = "/givechat"

-- State
local lastSentAt = {}
local msgCounter = 0
local pausedUntil = 0
local muted = {}          -- [userId] = true
local removedUntil = {}   -- [userId] = os.time() or math.huge
local history = {}
local HISTORY_LIMIT = 250

-- Hook for YOUR censor system later (pass-through)
local function ProcessOutgoingMessage(player, rawText)
	return rawText
end

local function nowSec() return os.time() end

local function nextMsgId()
	msgCounter += 1
	return msgCounter
end

local function normalize(rawText)
	rawText = tostring(rawText or "")
	rawText = rawText:gsub("\r", " "):gsub("\n", " ")
	rawText = rawText:sub(1, MAX_LEN)
	rawText = rawText:gsub("^%s+", ""):gsub("%s+$", "")
	return rawText
end

local function splitTokens(s)
	local t = {}
	for token in s:gmatch("%S+") do table.insert(t, token) end
	return t
end

local function addToHistory(entry)
	table.insert(history, entry)
	if #history > HISTORY_LIMIT then
		table.remove(history, 1)
	end
end

local function modId()
	return tonumber(ModeratorUserId.Value) or 0
end

local function isConfigured()
	return modId() > 0
end

local function isMod(player)
	local id = modId()
	return id > 0 and player and player.UserId == id
end

local function systemToClient(player, text)
	local id = nextMsgId()
	BroadcastMessage:FireClient(player, "System", text, nowSec(), id)
end

local function systemToAll(text)
	local id = nextMsgId()
	BroadcastMessage:FireAllClients("System", text, nowSec(), id)
end

local function findPlayerByArg(arg)
	if not arg or arg == "" then return nil end

	local asNum = tonumber(arg)
	if asNum then
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == asNum then return p end
		end
	end

	local lower = string.lower(arg)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower then return p end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name):sub(1, #lower) == lower then return p end
	end

	return nil
end

local function canChat(player)
	local t = nowSec()

	if not isConfigured() then
		return false, "Chat is disabled until a moderator UserId is configured."
	end

	if pausedUntil > t and not isMod(player) then
		return false, "Chat is paused."
	end

	local ru = removedUntil[player.UserId]
	if ru and ru > t and not isMod(player) then
		return false, "You currently do not have chat."
	end

	if muted[player.UserId] and not isMod(player) then
		return false, "You are muted."
	end

	return true, ""
end

local function handleCommands(player, msg)
	-- Commands should NEVER show as regular messages.
	-- If configured: only mod can run them, but non-mod attempts are suppressed.
	-- If not configured: treat everything as a normal message (but canChat will block anyway).
	if not isConfigured() then
		return false
	end

	local lower = string.lower(msg)

	-- exact commands
	if lower == CMD_CLEAR_ALL then
		if not isMod(player) then return true end
		ClearChat:FireAllClients()
		systemToAll("Chat cleared.")
		return true
	end

	if lower == CMD_CLEAR_ME then
		if not isMod(player) then return true end
		ClearChat:FireClient(player)
		systemToClient(player, "Chat cleared (local).")
		return true
	end

	local tokens = splitTokens(msg)
	local cmd = string.lower(tokens[1] or "")

	if cmd == CMD_PAUSECHAT then
		if not isMod(player) then return true end
		local mins = tonumber(tokens[2] or "")
		if not mins then
			systemToClient(player, "Usage: /pausechat [minutes] (use 0 to unpause)")
			return true
		end
		if mins <= 0 then
			pausedUntil = 0
			systemToAll("Chat unpaused.")
		else
			pausedUntil = nowSec() + math.floor(mins * 60)
			systemToAll("Chat paused.")
		end
		return true
	end

	if cmd == CMD_MUTE then
		if not isMod(player) then return true end
		local target = findPlayerByArg(tokens[2])
		if not target then
			systemToClient(player, "Usage: /mute [player name or ID]")
			return true
		end
		muted[target.UserId] = true
		systemToClient(player, "Muted: " .. target.Name)
		systemToClient(target, "You have been muted.")
		return true
	end

	if cmd == CMD_REMOVECHAT then
		if not isMod(player) then return true end
		local target = findPlayerByArg(tokens[2])
		if not target then
			systemToClient(player, "Usage: /removechat [player] [minutes optional]")
			return true
		end

		local mins = tonumber(tokens[3] or "")
		if mins and mins > 0 then
			removedUntil[target.UserId] = nowSec() + math.floor(mins * 60)
			systemToClient(player, "Removed chat for " .. target.Name .. " (" .. mins .. " min)")
			systemToClient(target, "Your chat has been removed for " .. mins .. " minutes.")
		else
			removedUntil[target.UserId] = math.huge
			systemToClient(player, "Removed chat for " .. target.Name .. " (until restored)")
			systemToClient(target, "Your chat has been removed until restored.")
		end
		return true
	end

	if cmd == CMD_GIVECHAT then
		if not isMod(player) then return true end
		local target = findPlayerByArg(tokens[2])
		if not target then
			systemToClient(player, "Usage: /givechat [player]")
			return true
		end
		muted[target.UserId] = nil
		removedUntil[target.UserId] = nil
		systemToClient(player, "Restored chat: " .. target.Name)
		systemToClient(target, "Your chat has been restored.")
		return true
	end

	if cmd == CMD_MSGDELETE then
		if not isMod(player) then return true end
		local target = findPlayerByArg(tokens[2])
		if not target then
			systemToClient(player, "Usage: /msgdelete [player] [text in message]")
			return true
		end

		-- Get the remainder after "/msgdelete <player> "
		local prefix = tokens[1] .. " " .. tokens[2] .. " "
		local needle = msg:sub(#prefix + 1)
		needle = normalize(needle)

		if needle == "" then
			systemToClient(player, "Usage: /msgdelete [player] [text in message]")
			return true
		end

		local needleLower = string.lower(needle)
		local idsToDelete = {}

		for _, entry in ipairs(history) do
			if entry.userId == target.UserId then
				if string.find(string.lower(entry.text), needleLower, 1, true) then
					table.insert(idsToDelete, entry.id)
				end
			end
		end

		if #idsToDelete == 0 then
			systemToClient(player, "No matching recent messages found.")
			return true
		end

		DeleteMessages:FireAllClients(idsToDelete)
		systemToClient(player, "Deleted " .. tostring(#idsToDelete) .. " message(s).")
		return true
	end

	return false
end

SendMessage.OnServerEvent:Connect(function(player, rawText)
	if typeof(rawText) ~= "string" then return end

	-- rate limit includes commands
	local now = os.clock()
	local last = lastSentAt[player.UserId]
	if last and (now - last) < RATE_LIMIT_SECONDS then return end
	lastSentAt[player.UserId] = now

	local msg = normalize(rawText)
	if msg == "" then return end

	-- suppress commands from appearing as chat
	if handleCommands(player, msg) then
		return
	end

	local ok, reason = canChat(player)
	if not ok then
		systemToClient(player, reason)
		return
	end

	msg = ProcessOutgoingMessage(player, msg)
	msg = normalize(msg)
	if msg == "" then return end

	local id = nextMsgId()
	addToHistory({
		id = id,
		userId = player.UserId,
		name = player.Name,
		text = msg,
		t = nowSec(),
	})

	BroadcastMessage:FireAllClients(player.Name, msg, nowSec(), id)
end)
]]

-- Ensure StarterPlayerScripts exists
local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if not starterPlayerScripts then
	starterPlayerScripts = Instance.new("StarterPlayerScripts")
	starterPlayerScripts.Parent = StarterPlayer
end

-- Client script
local clientScript = getOrCreate(starterPlayerScripts, "LocalScript", "CustomChatClient")
clientScript.Source = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("CustomChat")
local ModeratorUserId = folder:WaitForChild("ModeratorUserId")
local SendMessage = folder:WaitForChild("SendMessage")
local BroadcastMessage = folder:WaitForChild("BroadcastMessage")
local ClearChat = folder:WaitForChild("ClearChat")
local DeleteMessages = folder:WaitForChild("DeleteMessages")
local LetterRenderer = require(folder:WaitForChild("LetterRenderer"))

local CONFIG_PATH_TEXT = "ReplicatedStorage.CustomChat.ModeratorUserId.Value"

task.defer(function()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
end)

-- Remove previous GUI if it exists (useful for test sessions)
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("CustomChatGui")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomChatGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = pg

-- Small floating "Chat" button (bottom-right)
local openBtn = Instance.new("TextButton")
openBtn.Name = "OpenChatButton"
openBtn.AnchorPoint = Vector2.new(1, 1)
openBtn.Position = UDim2.new(1, -18, 1, -18)
openBtn.Size = UDim2.new(0, 56, 0, 32)
openBtn.Text = "Chat"
openBtn.Font = Enum.Font.GothamSemibold
openBtn.TextSize = 13
openBtn.TextColor3 = Color3.fromRGB(10, 10, 14)
openBtn.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
openBtn.BorderSizePixel = 0
openBtn.Parent = screenGui
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 10)

-- Chat panel
local root = Instance.new("Frame")
root.Name = "ChatPanel"
root.AnchorPoint = Vector2.new(1, 1)
root.Position = UDim2.new(1, -18, 1, -64)
root.Size = UDim2.new(0, 380, 0, 260)
root.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
root.BackgroundTransparency = 0.18
root.BorderSizePixel = 0
root.Visible = false
root.Parent = screenGui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.55
stroke.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 10)
title.Size = UDim2.new(1, -56, 0, 20)
title.Font = Enum.Font.GothamSemibold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "CommunicationV1"
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Parent = root

-- Close button (plain letter X)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseChatButton"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -10, 0, 10)
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamSemibold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.BackgroundTransparency = 0.9
closeBtn.BorderSizePixel = 0
closeBtn.Parent = root
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

local messages = Instance.new("ScrollingFrame")
messages.Position = UDim2.new(0, 12, 0, 38)
messages.Size = UDim2.new(1, -24, 1, -92)
messages.BackgroundTransparency = 1
messages.BorderSizePixel = 0
messages.ScrollBarThickness = 6
messages.AutomaticCanvasSize = Enum.AutomaticSize.Y
messages.CanvasSize = UDim2.new(0,0,0,0)
messages.Parent = root

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 3) -- tighter spacing between messages
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = messages

local inputBar = Instance.new("Frame")
inputBar.AnchorPoint = Vector2.new(0, 1)
inputBar.Position = UDim2.new(0, 12, 1, -12)
inputBar.Size = UDim2.new(1, -24, 0, 44)
inputBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
inputBar.BackgroundTransparency = 0.92
inputBar.BorderSizePixel = 0
inputBar.Parent = root
Instance.new("UICorner", inputBar).CornerRadius = UDim.new(0, 12)

local textBox = Instance.new("TextBox")
textBox.BackgroundTransparency = 1
textBox.Position = UDim2.new(0, 12, 0, 0)
textBox.Size = UDim2.new(1, -92, 1, 0)
textBox.ClearTextOnFocus = false
textBox.PlaceholderText = "Type a message…"
textBox.Font = Enum.Font.Gotham
textBox.TextSize = 14
textBox.TextXAlignment = Enum.TextXAlignment.Left
textBox.TextColor3 = Color3.fromRGB(245, 245, 250)
textBox.PlaceholderColor3 = Color3.fromRGB(180, 180, 190)
textBox.Text = ""
textBox.Parent = inputBar

local sendBtn = Instance.new("TextButton")
sendBtn.AnchorPoint = Vector2.new(1, 0.5)
sendBtn.Position = UDim2.new(1, -10, 0.5, 0)
sendBtn.Size = UDim2.new(0, 64, 0, 28)
sendBtn.Text = "Send"
sendBtn.Font = Enum.Font.GothamSemibold
sendBtn.TextSize = 13
sendBtn.TextColor3 = Color3.fromRGB(10, 10, 14)
sendBtn.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
sendBtn.BorderSizePixel = 0
sendBtn.Parent = inputBar
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 10)

-- Overlay that blocks chat until ModeratorUserId is set + verified by Check
local overlay = Instance.new("Frame")
overlay.Name = "ConfigOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = root

local overlayCard = Instance.new("Frame")
overlayCard.AnchorPoint = Vector2.new(0.5, 0.5)
overlayCard.Position = UDim2.new(0.5, 0, 0.5, 0)
overlayCard.Size = UDim2.new(0, 320, 0, 160)
overlayCard.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
overlayCard.BackgroundTransparency = 0.05
overlayCard.BorderSizePixel = 0
overlayCard.ZIndex = 51
overlayCard.Parent = overlay
Instance.new("UICorner", overlayCard).CornerRadius = UDim.new(0, 14)

local overlayStroke = Instance.new("UIStroke")
overlayStroke.Transparency = 0.45
overlayStroke.Thickness = 1
overlayStroke.Parent = overlayCard

local overlayText = Instance.new("TextLabel")
overlayText.BackgroundTransparency = 1
overlayText.Position = UDim2.new(0, 14, 0, 14)
overlayText.Size = UDim2.new(1, -28, 1, -60)
overlayText.Font = Enum.Font.Gotham
overlayText.TextSize = 14
overlayText.TextColor3 = Color3.fromRGB(240, 240, 245)
overlayText.TextWrapped = true
overlayText.TextXAlignment = Enum.TextXAlignment.Left
overlayText.TextYAlignment = Enum.TextYAlignment.Top
overlayText.ZIndex = 52
overlayText.Parent = overlayCard

local checkBtn = Instance.new("TextButton")
checkBtn.AnchorPoint = Vector2.new(1, 1)
checkBtn.Position = UDim2.new(1, -14, 1, -14)
checkBtn.Size = UDim2.new(0, 74, 0, 30)
checkBtn.Text = "Check"
checkBtn.Font = Enum.Font.GothamSemibold
checkBtn.TextSize = 13
checkBtn.TextColor3 = Color3.fromRGB(10, 10, 14)
checkBtn.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
checkBtn.BorderSizePixel = 0
checkBtn.ZIndex = 52
checkBtn.Parent = overlayCard
Instance.new("UICorner", checkBtn).CornerRadius = UDim.new(0, 10)

local function showChat()
	root.Visible = true
	openBtn.Visible = false
	root.Size = UDim2.new(0, 360, 0, 248)
	TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 380, 0, 260)
	}):Play()
end

local function hideChat()
	root.Visible = false
	openBtn.Visible = true
end

openBtn.MouseButton1Click:Connect(showChat)
closeBtn.MouseButton1Click:Connect(hideChat)

local function scrollToBottom()
	task.defer(function()
		task.wait()
		messages.CanvasPosition = Vector2.new(0, math.max(0, messages.AbsoluteCanvasSize.Y - messages.AbsoluteSize.Y))
	end)
end

local function addMessageLine(author, text, isSystem, msgId)
	local line = Instance.new("Frame")
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, 18) -- slightly tighter baseline
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.Parent = messages

	if msgId ~= nil then
		pcall(function()
			line:SetAttribute("MsgId", msgId)
		end)
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -6, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = isSystem and Color3.fromRGB(190, 200, 255) or Color3.fromRGB(240, 240, 245)
	label.Parent = line

	local prefix = isSystem and "" or (author .. ": ")
	local full = prefix .. tostring(text or "")

	task.spawn(function()
		LetterRenderer.Render(label, full, {
			CharDelay = 0.012,
			PunctuationDelay = 0.08,
			MaxLength = 350,
			FadeIn = true,
		})
	end)

	scrollToBottom()
end

local function clearChatUI()
	for _, child in ipairs(messages:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	scrollToBottom()
end

local function currentModId()
	return tonumber(ModeratorUserId.Value) or 0
end

local function isValidUserId(id)
	if not id or id <= 0 then return false end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(id)
	end)
	return ok and typeof(name) == "string" and #name > 0
end

local function setOverlayVisible(visible)
	overlay.Visible = visible
	inputBar.Visible = not visible
end

local function updateOverlayText()
	overlayText.Text =
		"Please enter moderator player ID at this portion of the code:\n\n" ..
		CONFIG_PATH_TEXT ..
		"\n\nThen click Check."
end

-- IMPORTANT: overlay only disappears after clicking Check successfully,
-- but it WILL reappear automatically if the value becomes 0/invalid again.
local function evaluateConfigForAutoShowOnly()
	local id = currentModId()
	if not isValidUserId(id) then
		updateOverlayText()
		setOverlayVisible(true)
	end
end

checkBtn.MouseButton1Click:Connect(function()
	local id = currentModId()
	if isValidUserId(id) then
		setOverlayVisible(false)
	else
		-- Do nothing if still invalid (overlay stays)
		updateOverlayText()
	end
end)

ModeratorUserId.Changed:Connect(function()
	-- If they remove it / set invalid, bring overlay back instantly.
	-- If they set valid, it stays until Check is clicked.
	evaluateConfigForAutoShowOnly()
end)

local function sendCurrent()
	if overlay.Visible then return end

	local msg = (textBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #msg == 0 then return end
	textBox.Text = ""
	SendMessage:FireServer(msg)
end

sendBtn.MouseButton1Click:Connect(sendCurrent)
textBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then sendCurrent() end
end)

BroadcastMessage.OnClientEvent:Connect(function(author, msg, ts, msgId)
	addMessageLine(author, msg, author == "System", msgId)
end)

ClearChat.OnClientEvent:Connect(function()
	clearChatUI()
end)

DeleteMessages.OnClientEvent:Connect(function(idList)
	if typeof(idList) ~= "table" then return end
	local toDelete = {}
	for _, id in ipairs(idList) do
		toDelete[id] = true
	end

	for _, child in ipairs(messages:GetChildren()) do
		if child:IsA("Frame") then
			local id = child:GetAttribute("MsgId")
			if id and toDelete[id] then
				child:Destroy()
			end
		end
	end
	scrollToBottom()
end)

-- Start hidden by default; show overlay if needed
hideChat()
updateOverlayText()
evaluateConfigForAutoShowOnly()
]]

print("✅ CommunicationV1 installed.")
print("Set moderator ID at: ReplicatedStorage.CustomChat.ModeratorUserId.Value")
print("If it's 0/invalid, chat will be blocked by an overlay until Check confirms a valid ID.")
