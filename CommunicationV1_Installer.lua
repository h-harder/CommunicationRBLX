-- Patch: rename title + reduce spacing between chat messages
local StarterPlayer = game:GetService("StarterPlayer")

local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if not sps then error("StarterPlayerScripts not found under StarterPlayer.") end

local client = sps:FindFirstChild("CustomChatClient")
if not client or not client:IsA("LocalScript") then
	error("CustomChatClient LocalScript not found in StarterPlayerScripts.")
end

local src = client.Source
local changed = 0

-- 1) Rename title
do
	local before = src
	src = src:gsub('title%.Text%s*=%s*"Custom Chat"', 'title.Text = "CommunicationV1"')
	if src ~= before then changed += 1 end
end

-- 2) Reduce spacing between messages
-- Your code currently has: list.Padding = UDim.new(0, 8)
do
	local before = src
	src = src:gsub("list%.Padding%s*=%s*UDim%.new%(%s*0%s*,%s*8%s*%)", "list.Padding = UDim.new(0, 3)")
	if src ~= before then changed += 1 end
end

client.Source = src

print(("✅ Patch applied. Changes made: %d"):format(changed))
print("Title is now 'CommunicationV1' and message spacing reduced.")
