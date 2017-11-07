
if SERVER then
	include("discord_relay/sv_config.lua") -- Order of operation bullshit.
	include("discord_relay/sh_discordcolors.lua") -- Colors next
	include("discord_relay/sv_relay.lua") -- And finally the bulk of the script.
	AddCSLuaFile("discord_relay/sh_discordcolors.lua")
	AddCSLuaFile("discord_relay/cl_relay.lua")
end

if CLIENT then
	include("discord_relay/sh_discordcolors.lua")
	include("discord_relay/cl_relay.lua")
end

// Originally made by Shigbeard, https://www.gmodstore.com/scripts/view/3277/discord-garrys-mod-chat-relay-script
MsgC(COLOR_DISCORD, "[Discord]", COLOR_USERNAME, " Hooray! ", COLOR_MESSAGE, "Relay has been loaded!\n")

