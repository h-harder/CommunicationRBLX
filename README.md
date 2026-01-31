```md
# CommunicationV1 (Custom Chat System for Roblox Studio)

**CommunicationV1** is a lightweight custom chat system you can install into any Roblox experience using the **Studio Command Bar**. It creates a separate chat UI and message pipeline from Roblox’s default chat, and includes **moderator tooling** (mute, pause, delete messages, revoke/restore chat, clear chat).

> ✅ **Portable by design:** the moderator UserId is **blank by default**, and the chat stays **disabled** until a valid moderator ID is configured.

---

## Features

### Core Chat
- Custom chat UI separate from Roblox’s built-in chat
- Bottom-right **Chat** button to open the panel
- When opened:
  - Chat button hides
  - `X` close button appears in the top-right of the chat panel
- Letter-by-letter typing effect (“letter rendering system”) for messages
- System join messages:
  - `player joined.`
  - `player left.`
- Server-side rate limiting to reduce spam
- Supports `/msgdelete` using per-message IDs (so deletions are consistent for everyone)

### Moderator Tools (only the moderator can use these)
- Global clear (everyone)
- Local clear (moderator only)
- Pause chat for the entire server
- Mute a player (messages won’t broadcast)
- Remove chat privileges from a player for a duration or until restored
- Delete recent messages containing specific text from a specific player
- Restore chat access

### Safety / Setup Lock
- Moderator ID is stored as an editable value:
  - `ReplicatedStorage.CustomChat.ModeratorUserId.Value`
- If the moderator ID is **missing/0/invalid**, chat is blocked by an overlay
- Overlay instructs the installer where to enter the moderator ID
- Overlay disappears only after the user clicks **Check** and the ID is valid
- If the ID is removed/reset to 0, the overlay returns and chat becomes unusable again

---

## Installation

### 1) Run the installer in Studio
1. Open **Roblox Studio**
2. Open your experience
3. Go to **View → Command Bar**
4. Paste the **CommunicationV1 First-Time Install** script
5. Run it (Tip: **Shift+Enter**)

After running, these objects are created:

**ReplicatedStorage**
- `CustomChat` (Folder)
  - `ModeratorUserId` (IntValue)
  - `SendMessage` (RemoteEvent)
  - `BroadcastMessage` (RemoteEvent)
  - `ClearChat` (RemoteEvent)
  - `DeleteMessages` (RemoteEvent)
  - `LetterRenderer` (ModuleScript)

**ServerScriptService**
- `CustomChatServer` (Script)

**StarterPlayer → StarterPlayerScripts**
- `CustomChatClient` (LocalScript)

---

## Configure the Moderator ID (Required)

By default, **chat is disabled** until a moderator ID is set.

### Where to set it
In Studio Explorer:
- `ReplicatedStorage → CustomChat → ModeratorUserId`
- Set its `Value` to a real Roblox **UserId** (a number)

Example:
- `ModeratorUserId.Value = 725209742`

### Enabling chat
1. Set the value as above
2. Start Play Test
3. Open chat panel
4. Click **Check** on the overlay
5. If the UserId is valid, the overlay disappears and chat becomes usable

> If the value is invalid or still 0, the **Check** button does nothing and the overlay stays.

---

## How to Use CommunicationV1 In-Game

### Opening / Closing the chat
- Click the **Chat** button (bottom-right) to open
- Click **X** (top-right) to close

### Sending messages
- Type into the input box and press:
  - **Enter**, or
  - Click **Send**

---

## Moderator Commands

> All moderator commands only work for the configured moderator UserId.  
> Commands are **suppressed** (they do not appear as chat messages).

### `/clear all`
**Clears chat for everyone.**  
**Usage:**  
- `/clear all`

**Effect:**
- All clients clear their chat panel
- A system message “Chat cleared.” is broadcast

---

### `/clear me`
**Clears chat only for the moderator.**  
**Usage:**  
- `/clear me`

**Effect:**
- Only the moderator client clears chat panel
- A local system message confirms the action

---

### `/pausechat [minutes]`
**Pauses global chat for non-moderators.**  
**Usage:**
- `/pausechat 10` (pause for 10 minutes)
- `/pausechat 0` (unpause immediately)

**Effect:**
- Non-moderators cannot send messages while paused
- Moderator can still send messages and run commands
- Broadcasts system messages when paused/unpaused

---

### `/mute [player name or ID]`
**Mutes a player so their messages do not broadcast.**  
**Usage:**
- `/mute SomePlayer`
- `/mute 123456789` (UserId)

**Effect:**
- Player can type and “send” but their messages won’t be broadcast
- The muted player receives a system notice (“You have been muted.”)
- Use `/givechat` to restore

---

### `/removechat [player] [minutes optional]`
**Revokes chat privileges from a player.**  
**Usage:**
- `/removechat SomePlayer 15` (removes chat for 15 minutes)
- `/removechat SomePlayer` (removes chat until restored)

**Effect:**
- Player cannot send messages until time expires or chat is restored
- Player receives a system notice about removal
- Use `/givechat` to restore immediately

---

### `/givechat [player]`
**Restores chat privileges (and un-mutes) for a player.**  
**Usage:**
- `/givechat SomePlayer`
- `/givechat 123456789`

**Effect:**
- Clears both mute and removechat status
- Player can chat again immediately

---

### `/msgdelete [player] [text in message]`
**Deletes recent messages from a specific player containing the provided text.**  
**Usage:**
- `/msgdelete SomePlayer hello`
- `/msgdelete SomePlayer that was mean`

**Effect:**
- Searches the recent in-memory message history (server-side)
- Finds messages from the target player that contain the text (case-insensitive)
- Deletes matching messages for **all clients**
- Moderator receives a confirmation with number of messages removed

**Notes:**
- This only affects the **recent history** kept in memory (not permanent logs)
- Matches are substring-based (partial matches count)

---

## Player Targeting Rules

For commands that take a player argument:
- You can use:
  - Exact name (`SomePlayer`)
  - Partial name prefix (`Some`)
  - UserId number (`123456789`)
- If ambiguous or not found, you’ll see a usage message (mod only)

---

## Important Notes / Limitations

- **No filtering is included** (by design). If you need filtering/sensoring, add it in the server hook:
  - `ProcessOutgoingMessage(player, rawText)`
- This system is intended for **Studio/your own experience**. Roblox policies still apply to published games.
- Message deletion operates on **recent in-memory history** only.
- The built-in Roblox chat UI is disabled on the client via:
  - `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)`

---

## Troubleshooting

### “Enter does nothing” in Command Bar
In Studio Command Bar:
- Use **Shift+Enter** to execute the script
- Ensure you are in **View → Command Bar**, not the Output window

### Chat overlay won’t go away
- Confirm you set:
  - `ReplicatedStorage.CustomChat.ModeratorUserId.Value`
- Ensure it’s a **real numeric UserId**
- Click **Check**
- If it still won’t validate, the ID is likely invalid or you are offline (rare). Try a different known valid UserId.

### I want to change the moderator later
- Update `ModeratorUserId.Value`
- Open chat and click **Check** to validate & unlock

---
