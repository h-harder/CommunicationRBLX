# CommunicationV1 (Roblox Custom Chat)

A lightweight custom chat UI + moderation commands + bubble chat, designed to run alongside Roblox TextService filtering.

## What this includes
- Custom on-screen chat UI (toggle button bottom-right, X close)
- Moderator-only commands:
  - `/clear all`
  - `/pausechat [minutes]`
  - `/mute [player name or ID]`
  - `/msgdelete [player] [text in message]`
  - `/removechat [player] [minutes optional]`
  - `/givechat [player]`
  - `/robloxfilter [on/off]`
  - `/bubblechat [on/off]`
- Bubble text above the speaker (auto-sizes to text)
- Optional custom filter hook module
- Optional banned-terms text list (one term/phrase per line) with whole-word / whole-phrase matching

## Install (first time)
1. In Roblox Studio, open **View → Command Bar**
2. Paste the **FIRST-TIME INSTALL** script and run with **Shift+Enter**
3. In Explorer:
   - `ReplicatedStorage → CustomChat → ModeratorUserId`
   - Set `Value` to your Roblox userId (number)
4. In-game, open the chat UI and click **Check** on the overlay to enable chat.

## Configure banned terms (optional)
- `ReplicatedStorage → CustomChat → BannedTermsText`
- Paste ONE term or phrase per line
- Lines starting with `#` are treated as comments

## Custom filter hook (optional)
Edit:
- `ServerScriptService → CommunicationV1_CustomFilter`

Return either:
- `function(text, speakerUserId) -> string`, or
- `{ Apply = function(text, speakerUserId) -> string }`

This runs **before** the banned-terms masking and Roblox TextService filtering.

## Roblox official filtering
The server uses `TextService:FilterStringAsync` + `GetChatForUserAsync(userId)` per-recipient when enabled.

Toggle (moderator only):
- `/robloxfilter on`
- `/robloxfilter off`

## Bubble chat
Toggle (moderator only):
- `/bubblechat on`
- `/bubblechat off`

## Notes
- Text filtering behavior is governed by Roblox policy and can vary by account and context.
- Keep this system server-authoritative (filtering should happen server-side).
