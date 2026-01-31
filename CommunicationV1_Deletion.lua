-- CommunicationV1 UNINSTALL: delete everything and revert to Roblox default chat

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local function safeDestroy(obj)
	if obj and obj.Parent then
		obj:Destroy()
	end
end

-- Remove ReplicatedStorage folder
safeDestroy(ReplicatedStorage:FindFirstChild("CustomChat"))

-- Remove server scripts/modules
safeDestroy(ServerScriptService:FindFirstChild("CustomChatServer"))
safeDestroy(ServerScriptService:FindFirstChild("CommunicationV1_CustomFilter"))

-- Remove StarterGui UI
safeDestroy(StarterGui:FindFirstChild("CommunicationV1Gui"))

-- Remove any already-cloned UI in live PlayerGuis (Play Solo / Test)
for _, plr in ipairs(Players:GetPlayers()) do
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then
		safeDestroy(pg:FindFirstChild("CommunicationV1Gui"))
	end
end

-- Re-enable Roblox default chat (TextChatService / classic fallback)
local TextChatService = game:FindService("TextChatService")
if TextChatService then
	pcall(function()
		TextChatService.Enabled = true
	end)
	pcall(function()
		-- Modern default chat system
		TextChatService.ChatVersion = Enum.ChatVersion.TextChatService
	end)
end

-- Classic chat service fallback (older experiences)
local Chat = game:FindService("Chat")
if Chat then
	pcall(function()
		Chat.BubbleChatEnabled = true
		Chat.LoadDefaultChat = true
	end)
end

print("✅ CommunicationV1 removed. Roblox default chat re-enabled.")
print("If you don't see default chat immediately in Studio test, stop and start Play again.")
