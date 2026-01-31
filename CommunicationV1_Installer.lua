-- CommunicationV1 FIRST-TIME INSTALL (single-button UI, no tiny blue fallback)
-- This deletes any existing CommunicationV1 install pieces and recreates them fresh.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if obj and obj.ClassName == className then return obj end
	if obj then obj:Destroy() end
	obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

-- ---------
-- CLEANUP
-- ---------
do
	local oldFolder = ReplicatedStorage:FindFirstChild("CustomChat")
	if oldFolder then oldFolder:Destroy() end

	local oldServer = ServerScriptService:FindFirstChild("CustomChatServer")
	if oldServer then oldServer:Destroy() end

	local oldHook = ServerScriptService:FindFirstChild("CommunicationV1_CustomFilter")
	if oldHook then oldHook:Destroy() end

	local oldGui = StarterGui:FindFirstChild("CommunicationV1Gui")
	if oldGui then oldGui:Destroy() end
end

-- -----------------------------
-- ReplicatedStorage/CustomChat
-- -----------------------------
local folder = Instance.new("Folder")
folder.Name = "CustomChat"
folder.Parent = ReplicatedStorage

local ModeratorUserId = Instance.new("IntValue")
ModeratorUserId.Name = "ModeratorUserId"
ModeratorUserId.Value = 0 -- blank default
ModeratorUserId.Parent = folder

local RobloxFilterEnabled = Instance.new("BoolValue")
RobloxFilterEnabled.Name = "RobloxFilterEnabled"
RobloxFilterEnabled.Value = true
RobloxFilterEnabled.Parent = folder

local BubbleChatEnabled = Instance.new("BoolValue")
BubbleChatEnabled.Name = "BubbleChatEnabled"
BubbleChatEnabled.Value = true
BubbleChatEnabled.Parent = folder

local BannedTermsText = Instance.new("StringValue")
BannedTermsText.Name = "BannedTermsText"
BannedTermsText.Value = [[
# CommunicationV1 banned terms
# One term or phrase per line
# Comments start with #
# Paste your list here
]]
BannedTermsText.Parent = folder

local SendMessage = Instance.new("RemoteEvent")
SendMessage.Name = "SendMessage"
SendMessage.Parent = folder

local BroadcastMessage = Instance.new("RemoteEvent")
BroadcastMessage.Name = "BroadcastMessage"
BroadcastMessage.Parent = folder

local ClearChat = Instance.new("RemoteEvent")
ClearChat.Name = "ClearChat"
ClearChat.Parent = folder

local DeleteMessages = Instance.new("RemoteEvent")
DeleteMessages.Name = "DeleteMessages"
DeleteMessages.Parent = folder

-- -----------------------------------------
-- ServerScriptService/CommunicationV1 hook
-- -----------------------------------------
local hook = Instance.new("ModuleScript")
hook.Name = "CommunicationV1_CustomFilter"
hook.Parent = ServerScriptService
hook.Source = [[
-- OPTIONAL custom filter hook.
-- Return either:
--   function(text, speakerUserId) -> string
-- or:
--   { Apply = function(text, speakerUserId) -> string }
return function(text, speakerUserId)
	return text
end
]]

-- -----------------------------------------
-- ServerScriptService/CustomChatServer
-- -----------------------------------------
local server = Instance.new("Script")
server.Name = "CustomChatServer"
server.Parent = ServerScriptService
server.Source = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local folder = ReplicatedStorage:WaitForChild("CustomChat")

local ModeratorUserId = folder:WaitForChild("ModeratorUserId")
local RobloxFilterEnabled = folder:WaitForChild("RobloxFilterEnabled")
local BubbleChatEnabled = folder:WaitForChild("BubbleChatEnabled")
local BannedTermsText = folder:WaitForChild("BannedTermsText")

local SendMessage = folder:WaitForChild("SendMessage")
local BroadcastMessage = folder:WaitForChild("BroadcastMessage")
local ClearChat = folder:WaitForChild("ClearChat")
local DeleteMessages = folder:WaitForChild("DeleteMessages")

local CustomFilterModule = require(ServerScriptService:WaitForChild("CommunicationV1_CustomFilter"))

local MAX_LEN = 200
local RATE_LIMIT_SECONDS = 0.35

-- Commands
local CMD_CLEAR_ALL      = "/clear all"
local CMD_CLEAR_ME       = "/clear me"
local CMD_PAUSECHAT      = "/pausechat"
local CMD_MUTE           = "/mute"
local CMD_MSGDELETE      = "/msgdelete"
local CMD_REMOVECHAT     = "/removechat"
local CMD_GIVECHAT       = "/givechat"
local CMD_ROBLOX_FILTER  = "/robloxfilter"
local CMD_BUBBLE_CHAT    = "/bubblechat"

-- State
local lastSentAt = {}
local msgCounter = 0
local pausedUntil = 0
local muted = {}
local removedUntil = {}
local history = {}
local HISTORY_LIMIT = 250

local function nowSec() return os.time() end
local function nextMsgId() msgCounter += 1; return msgCounter end

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
	if #history > HISTORY_LIMIT then table.remove(history, 1) end
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
	for _, p in ipairs(Players:GetPlayers()) do
		BroadcastMessage:FireClient(p, "System", text, nowSec(), id)
	end
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

-- ======================
-- Whole-word/phrase banned list mask
-- ======================
local function parseBannedTerms()
	local txt = tostring(BannedTermsText.Value or "")
	local terms = {}
	for line in txt:gmatch("[^\n]+") do
		line = line:gsub("\r", "")
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:match("^#") and not line:match("^%-%-") then
			table.insert(terms, string.lower(line))
		end
	end
	return terms
end

local function escapeLuaPattern(s)
	return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function buildWholeTermPattern(termLower)
	local words = {}
	for w in termLower:gmatch("%S+") do
		table.insert(words, escapeLuaPattern(w))
	end
	if #words == 0 then return nil end
	local core = table.concat(words, "[%s%p]+")
	return "%f[%w]" .. core .. "%f[%W]"
end

local function applyBannedMask(text)
	local terms = parseBannedTerms()
	if #terms == 0 then return text end

	local original = text
	local lowerText = string.lower(text)
	local mark = table.create(#original, false)

	local function markRange(s, e)
		for i = s, e do mark[i] = true end
	end

	for _, term in ipairs(terms) do
		local patt = buildWholeTermPattern(term)
		if patt then
			local startPos = 1
			while true do
				local s, e = string.find(lowerText, patt, startPos)
				if not s then break end
				markRange(s, e)
				startPos = e + 1
			end
		end
	end

	local out = table.create(#original)
	for i = 1, #original do
		out[i] = mark[i] and "#" or original:sub(i, i)
	end
	return table.concat(out)
end

-- ======================
-- Bubble chat (auto-sized)
-- ======================
local BUBBLE_FONT = Enum.Font.Gotham
local BUBBLE_TEXT_SIZE = 14
local BUBBLE_MAX_WIDTH = 260
local PAD_X = 18
local PAD_Y = 16

local function getAdornee(char)
	if not char then return nil end
	return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function computeBubble(text)
	local bubbleText = tostring(text or ""):sub(1, 140)
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(bubbleText, BUBBLE_TEXT_SIZE, BUBBLE_FONT, Vector2.new(BUBBLE_MAX_WIDTH, 1000))
	end)
	if not ok then
		return 220, 44, bubbleText
	end
	local w = math.clamp(bounds.X + PAD_X, 120, BUBBLE_MAX_WIDTH + PAD_X)
	local h = math.clamp(bounds.Y + PAD_Y, 34, 140)
	return w, h, bubbleText
end

local function showBubble(player, text)
	if not BubbleChatEnabled.Value then return end
	local char = player.Character
	local adornee = getAdornee(char)
	if not adornee then return end

	local old = adornee:FindFirstChild("CommunicationV1Bubble")
	if old then old:Destroy() end

	local w, h, bubbleText = computeBubble(text)

	local gui = Instance.new("BillboardGui")
	gui.Name = "CommunicationV1Bubble"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(w, h)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100
	gui.Parent = adornee

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.6
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(9, 7)
	label.Size = UDim2.new(1, -18, 1, -14)
	label.Font = BUBBLE_FONT
	label.TextSize = BUBBLE_TEXT_SIZE
	label.TextColor3 = Color3.fromRGB(245, 245, 250)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = bubbleText
	label.Parent = frame

	task.delay(3.0, function()
		if gui.Parent == nil then return end
		local tInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		pcall(function()
			TweenService:Create(frame, tInfo, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, tInfo, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, tInfo, { Transparency = 1 }):Play()
		end)
		Debris:AddItem(gui, 0.5)
	end)
end

-- ======================
-- Roblox official filtering (per-recipient)
-- ======================
local function sendFilteredToAll(sender, authorName, rawMsg, ts, msgId)
	if not RobloxFilterEnabled.Value then
		for _, p in ipairs(Players:GetPlayers()) do
			BroadcastMessage:FireClient(p, authorName, rawMsg, ts, msgId)
		end
		return
	end

	local ok, filterResult = pcall(function()
		return TextService:FilterStringAsync(rawMsg, sender.UserId)
	end)

	if not ok or not filterResult then
		local masked = string.rep("#", math.min(#rawMsg, MAX_LEN))
		for _, p in ipairs(Players:GetPlayers()) do
			BroadcastMessage:FireClient(p, authorName, masked, ts, msgId)
		end
		return
	end

	for _, recipient in ipairs(Players:GetPlayers()) do
		local ok2, perUser = pcall(function()
			return filterResult:GetChatForUserAsync(recipient.UserId)
		end)
		if ok2 and typeof(perUser) == "string" then
			BroadcastMessage:FireClient(recipient, authorName, perUser, ts, msgId)
		else
			BroadcastMessage:FireClient(recipient, authorName, string.rep("#", math.min(#rawMsg, MAX_LEN)), ts, msgId)
		end
	end
end

-- ======================
-- Commands
-- ======================
local function handleCommands(player, msg)
	if not isConfigured() then return false end

	local lower = string.lower(msg)

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

	if cmd == CMD_ROBLOX_FILTER then
		if not isMod(player) then return true end
		local arg = string.lower(tokens[2] or "")
		if arg == "on" then
			RobloxFilterEnabled.Value = true
			systemToAll("Roblox filtering: ON")
		elseif arg == "off" then
			RobloxFilterEnabled.Value = false
			systemToAll("Roblox filtering: OFF")
		else
			systemToClient(player, "Usage: /robloxfilter [on/off]")
		end
		return true
	end

	if cmd == CMD_BUBBLE_CHAT then
		if not isMod(player) then return true end
		local arg = string.lower(tokens[2] or "")
		if arg == "on" then
			BubbleChatEnabled.Value = true
			systemToAll("Bubble chat: ON")
		elseif arg == "off" then
			BubbleChatEnabled.Value = false
			systemToAll("Bubble chat: OFF")
		else
			systemToClient(player, "Usage: /bubblechat [on/off]")
		end
		return true
	end

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

-- ======================
-- Main message handler
-- ======================
SendMessage.OnServerEvent:Connect(function(player, rawText)
	if typeof(rawText) ~= "string" then return end

	local now = os.clock()
	local last = lastSentAt[player.UserId]
	if last and (now - last) < RATE_LIMIT_SECONDS then return end
	lastSentAt[player.UserId] = now

	local msg = normalize(rawText)
	if msg == "" then return end

	-- commands never show
	if handleCommands(player, msg) then return end

	local ok, reason = canChat(player)
	if not ok then
		systemToClient(player, reason)
		return
	end

	-- A) custom hook first
	local filtered = msg
	local okHook, result = pcall(function()
		if typeof(CustomFilterModule) == "function" then
			return CustomFilterModule(filtered, player.UserId)
		elseif typeof(CustomFilterModule) == "table" and typeof(CustomFilterModule.Apply) == "function" then
			return CustomFilterModule.Apply(filtered, player.UserId)
		end
		return filtered
	end)
	if okHook and typeof(result) == "string" then
		filtered = result
	end
	filtered = normalize(filtered)
	if filtered == "" then return end

	-- B) banned list mask
	filtered = applyBannedMask(filtered)
	filtered = normalize(filtered)
	if filtered == "" then return end

	local id = nextMsgId()
	local ts = nowSec()
	addToHistory({ id = id, userId = player.UserId, name = player.Name, text = filtered, t = ts })

	showBubble(player, filtered)
	sendFilteredToAll(player, player.Name, filtered, ts, id)
end)

print("✅ CommunicationV1 server installed.")
]]

-- -----------------------------
-- StarterGui/CommunicationV1Gui
-- -----------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CommunicationV1Gui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = StarterGui

local client = Instance.new("LocalScript")
client.Name = "CommunicationV1Client"
client.Parent = gui
client.Source = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("CustomChat")
local SendMessage = folder:WaitForChild("SendMessage")
local BroadcastMessage = folder:WaitForChild("BroadcastMessage")
local ClearChat = folder:WaitForChild("ClearChat")
local DeleteMessages = folder:WaitForChild("DeleteMessages")
local ModeratorUserId = folder:WaitForChild("ModeratorUserId")

local screenGui = script.Parent

local function new(className, props, parent)
	local o = Instance.new(className)
	for k,v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

-- ONE opener button (nice-looking, not tiny blue)
local openBtn = new("TextButton", {
	Name = "OpenChatButton",
	AnchorPoint = Vector2.new(1,1),
	Position = UDim2.new(1, -18, 1, -22),
	Size = UDim2.new(0, 150, 0, 36),
	Text = "CommunicationV1",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(245,245,250),
	BackgroundColor3 = Color3.fromRGB(28,28,34),
	AutoButtonColor = true,
}, screenGui)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, openBtn)
new("UIStroke", {Thickness = 1, Transparency = 0.65}, openBtn)

-- Panel
local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(1,1),
	Position = UDim2.new(1, -18, 1, -68),
	Size = UDim2.new(0, 350, 0, 320),
	BackgroundColor3 = Color3.fromRGB(18,18,22),
	BackgroundTransparency = 0.10,
	Visible = false,
}, screenGui)
new("UICorner", {CornerRadius = UDim.new(0, 14)}, panel)
new("UIStroke", {Thickness = 1, Transparency = 0.65}, panel)

new("TextLabel", {
	Name = "Title",
	Position = UDim2.new(0, 12, 0, 8),
	Size = UDim2.new(1, -60, 0, 22),
	BackgroundTransparency = 1,
	Text = "CommunicationV1",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(245,245,250),
	TextXAlignment = Enum.TextXAlignment.Left
}, panel)

local closeBtn = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1,0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.new(0, 26, 0, 22),
	BackgroundTransparency = 1,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(245,245,250),
	AutoButtonColor = true,
}, panel)

local listFrame = new("ScrollingFrame", {
	Name = "List",
	Position = UDim2.new(0, 12, 0, 36),
	Size = UDim2.new(1, -24, 1, -92),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0,0,0,0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)

new("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, listFrame)

local input = new("TextBox", {
	Name = "Input",
	Position = UDim2.new(0, 12, 1, -46),
	Size = UDim2.new(1, -24, 0, 34),
	BackgroundColor3 = Color3.fromRGB(28,28,34),
	TextColor3 = Color3.fromRGB(245,245,250),
	Font = Enum.Font.Gotham,
	TextSize = 14,
	ClearTextOnFocus = false,
	PlaceholderText = "Type message...",
	TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
new("UICorner", {CornerRadius = UDim.new(0, 10)}, input)

-- Overlay requiring moderator ID
local overlay = new("Frame", {
	Name = "Overlay",
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 0.35,
	Size = UDim2.new(1,0,1,0),
	Visible = false,
}, panel)

local overlayCard = new("Frame", {
	AnchorPoint = Vector2.new(0.5,0.5),
	Position = UDim2.new(0.5,0,0.5,0),
	Size = UDim2.new(0, 310, 0, 160),
	BackgroundColor3 = Color3.fromRGB(18,18,22),
	BackgroundTransparency = 0.06,
}, overlay)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, overlayCard)
new("UIStroke", {Thickness=1, Transparency=0.65}, overlayCard)

new("TextLabel", {
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(1, -24, 0, 96),
	BackgroundTransparency = 1,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(245,245,250),
	Text = "Please enter moderator player ID at this portion of the code:\nReplicatedStorage.CustomChat.ModeratorUserId.Value\n\nThen click Check.",
}, overlayCard)

local checkBtn = new("TextButton", {
	Name = "Check",
	AnchorPoint = Vector2.new(1,1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.new(0, 90, 0, 30),
	BackgroundColor3 = Color3.fromRGB(11, 92, 171),
	Text = "Check",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255,255,255),
}, overlayCard)
new("UICorner", {CornerRadius = UDim.new(0, 10)}, checkBtn)

local function overlayShouldShow()
	return (tonumber(ModeratorUserId.Value) or 0) <= 0
end

local function refreshOverlay()
	overlay.Visible = overlayShouldShow()
	input.TextEditable = not overlay.Visible
	input.Active = not overlay.Visible
end

checkBtn.MouseButton1Click:Connect(function()
	refreshOverlay()
end)

ModeratorUserId.Changed:Connect(function()
	-- Overlay reappears automatically if ID becomes blank, but does not auto-dismiss.
	if overlayShouldShow() then
		overlay.Visible = true
	end
end)

refreshOverlay()

local function openPanel()
	panel.Visible = true
	openBtn.Visible = false
	refreshOverlay()
	task.wait()
	if not overlay.Visible then
		input:CaptureFocus()
	end
end

local function closePanel()
	panel.Visible = false
	openBtn.Visible = true
end

openBtn.MouseButton1Click:Connect(openPanel)
closeBtn.MouseButton1Click:Connect(closePanel)

-- Message map for deletions
local labelById = {}

local function addLine(author, text, msgId)
	local line = Instance.new("TextLabel")
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, 18)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.Font = Enum.Font.Gotham
	line.TextSize = 13
	line.TextColor3 = Color3.fromRGB(245,245,250)
	line.Text = string.format("%s: %s", tostring(author), tostring(text))
	line.Parent = listFrame
	if msgId then labelById[msgId] = line end
end

BroadcastMessage.OnClientEvent:Connect(function(author, text, ts, msgId)
	addLine(author, text, msgId)
	listFrame.CanvasPosition = Vector2.new(0, 10^7)
end)

ClearChat.OnClientEvent:Connect(function()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	table.clear(labelById)
end)

DeleteMessages.OnClientEvent:Connect(function(ids)
	if typeof(ids) ~= "table" then return end
	for _, id in ipairs(ids) do
		local label = labelById[id]
		if label then
			label:Destroy()
			labelById[id] = nil
		end
	end
end)

local function send()
	if overlay.Visible then return end
	local text = (input.Text or ""):gsub("^%s+",""):gsub("%s+$","")
	if text == "" then return end
	input.Text = ""
	SendMessage:FireServer(text)
end

input.FocusLost:Connect(function(enterPressed)
	if enterPressed then send() end
end)

UIS.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Return and input:IsFocused() then
		send()
	end
end)
]]

print("✅ CommunicationV1 FIRST-TIME install complete.")
print("Next: Set ReplicatedStorage.CustomChat.ModeratorUserId.Value to your userId, open chat, then click Check.")
