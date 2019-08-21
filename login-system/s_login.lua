--[[
 _____                         _     _   _____                 _
|  ___|                       | |   | | |  __ \               (_)
| |__ _ __ ___   ___ _ __ __ _| | __| | | |  \/ __ _ _ __ ___  _ _ __   __ _
|  __| '_ ` _ \ / _ \ '__/ _` | |/ _` | | | __ / _` | '_ ` _ \| | '_ \ / _` |
| |__| | | | | |  __/ | | (_| | | (_| | | |_\ \ (_| | | | | | | | | | | (_| |
\____/_| |_| |_|\___|_|  \__,_|_|\__,_|  \____/\__,_|_| |_| |_|_|_| |_|\__, |
																		__/ |
																	   |___/
______ _____ _      ___________ _       _____   __
| ___ \  _  | |    |  ___| ___ \ |     / _ \ \ / /
| |_/ / | | | |    | |__ | |_/ / |    / /_\ \ V /
|    /| | | | |    |  __||  __/| |    |  _  |\ /
| |\ \\ \_/ / |____| |___| |   | |____| | | || |
\_| \_|\___/\_____/\____/\_|   \_____/\_| |_/\_/

Copyright of the Emerald Gaming Development Team, do not distribute - All rights reserved. ]]																																															
v = "4F5BB59224F5B07F019D2ECBBA1B7266" -- For maximum security, we recommend you change this string to something unique to your community and keep secure.

mysql = exports.mysql
blackhawk = exports.blackhawk -- Shorten down exports.blackhawk to just 'blackhawk'

-- Sets the player's temporary name when they login.
function setTempName()
	local randomNumber = math.random(1000, 9999)
	local theTempName = "EG" .. randomNumber
	local players = getElementsByType("players")

	-- Checks all online players to see if by any rare chance the random name already exists.
	for _, thePlayer in ipairs(players) do
		local thePlayerName = getPlayerName(thePlayer)
		if (thePlayerName == theTempName) then
			randomNumber = math.random(1, 99999)
		end
	end
	setPlayerName(source, theTempName)
	triggerEvent("updateNametagColor", source)
end
addEvent("setLoginTempNames", true)
addEventHandler("setLoginTempNames", root, setTempName)

function playerLogin(username, password, saveDetails)
	local thePlayer = source
	if (username == "") then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "Please enter your username!", 255, 0, 0, 1)
		return false
	elseif (password == "") then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "Please enter your password!", 255, 0, 0, 1)
		return false
	end

	-- Check if the account exists.
	local accountID = exports.mysql:QueryString("SELECT `id` FROM `accounts` WHERE `username` = (?);", username)

	if not tonumber(accountID) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "The account '" .. username .. "' doesn't exist!", 255, 0, 0, 1)
		return false
	end

	-- Check if the password is correct.
	local passData = exports.mysql:QuerySingle("SELECT `password`, `salt` FROM `accounts` WHERE `id` = (?);", accountID)

	if (password == passData.salt) then -- Player's local salt matches the one in DB.
		playerLoginCallback(true, thePlayer, accountID, username, passData.salt, saveDetails)
	else
		passwordVerify(password, passData.password, function(state)
			playerLoginCallback(state, thePlayer, accountID, username, passData.salt, saveDetails)
		end)
	end
end
addEvent("login:attemptLogin", true)
addEventHandler("login:attemptLogin", root, playerLogin)

function playerLoginCallback(state, thePlayer, accountID, a, pS, saveDetails)
	if (state) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "Authenticated!", 0, 255, 0)
		
		-- Save their details if they requested so, or remove if they unchecked it.
		if (saveDetails) then
			validatedLogin(thePlayer, accountID, pS)
			triggerClientEvent(thePlayer, "login:handleLoginDetails", thePlayer, "save", a, pS)
		else
			validatedLogin(thePlayer, accountID, false)
			triggerClientEvent(thePlayer, "login:handleLoginDetails", thePlayer, "delete")
		end
	else
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "That password is incorrect!", 255, 0, 0, 1)
		triggerClientEvent(thePlayer, "login:handleLoginDetails", thePlayer, "delete")
	end
end

-- If we've made it this far, we can assume the account is valid, and the details given are correct.
function validatedLogin(thePlayer, accountID, p)
	local accountData = mysql:QuerySingle("SELECT `username`, `appstate`, `serial`, `rank`, `ip` FROM `accounts` WHERE `id` = (?);", accountID)
	local thePlayerUsername = accountData.username
	local allPlayers = getElementsByType("player")

	-- Check to see if the account is already online.
	for _, loggedInPlayer in ipairs(allPlayers) do
		local loggedInAccount = getElementData(loggedInPlayer, "account:username")
		if (loggedInAccount) and (loggedInAccount == thePlayerUsername) then
			triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "That account is already logged in, logging them out..", 255, 0, 0, 1)
			exports.global:sendMessageToAdmins("[WARNING] " .. loggedInAccount .. " logged in whilst someone was already on that account.")
			kickPlayer(loggedInPlayer, "Someone logged into your account!")
			return false
		end
	end

	-- Check to see if the account has passed the application stage.
	local appState = accountData.appstate
	if (tonumber(appState) ~= 1) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "Your account has not passed the application stage - Visit emeraldgaming.net", 255, 0, 0, 1)
		return false
	end

	-- Check to see if the serial they are joining on is stored within their serial table.
	local serialTable = accountData.serial
	local thePlayerSerial = getPlayerSerial(thePlayer)
	local parsedSerialTable = split(serialTable, ",")
	local serialAuth = false

	for i, serial in ipairs(parsedSerialTable) do
		if (thePlayerSerial == serial) then
			serialAuth = true
		end
	end
	
	-- If the serial doesn't exist, it's not whitelisted. Prevent login.
	if not (serialAuth) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 1, "This device's serial is not whitelisted!", 255, 0, 0, 1)
		if (accountData.rank >= 1) then
			exports.global:sendMessageToAdmins("[LOGIN] Un-whitelisted serial '" .. thePlayerSerial .. "' attempted to log into staff account '".. thePlayerUsername .. "'.")
			return false
		end
	end

	-- Check to see if the IP they are joining on is the same as any of their previous IPs.
	local ipTable = accountData.ip
	local thePlayerIP = getPlayerIP(thePlayer)
	local parsedIPTable = split(ipTable, ",")
	local noIPMatch = false

	for i, ip in ipairs(parsedIPTable) do
		if (thePlayerIP == ip) then
			noIPMatch = true
		end
	end

	-- If it is not the same and is a new IP, add it to their IP table.
	if not (noIPMatch) then
		local newTable = ipTable .. "," .. thePlayerIP
		exports.mysql:Execute("UPDATE `accounts` SET `ip` = (?) WHERE `id` = (?);", newTable, accountID)
	end

	triggerClientEvent(thePlayer, "login:hideLoginMenu", thePlayer)
	setPlayerName(thePlayer, thePlayerUsername)

	----------------------------------------------------------------------- BEGIN SETTING ACCOUNT DATA -----------------------------------------------------------------------

	------------ [ Account Data ] ------------
	blackhawk:setElementDataEx(thePlayer, "account:id", accountID, true)
	blackhawk:setElementDataEx(thePlayer, "account:username", thePlayerUsername, true)

	exports["account-system"]:loadAccountData(thePlayer, accountID) -- TriggerEvent to load all account data.

	-- Initial account data is set, we can now also let the user proceed and select a character whilst we continue to set data.
	local randomDim = 50000 + getElementData(thePlayer, "player:id")
	setElementDimension(thePlayer, randomDim)
	setElementInterior(thePlayer, 0)

	triggerClientEvent(thePlayer, "login:onLoginSuccess", thePlayer)
	triggerEvent("character:showCharacterSelection", thePlayer, thePlayer)

	------------ [ Duty Status ] ------------
	blackhawk:setElementDataEx(thePlayer, "duty:staff", 0, true)
	blackhawk:setElementDataEx(thePlayer, "duty:developer", 0, true)
	blackhawk:setElementDataEx(thePlayer, "duty:vt", 0, true)
	blackhawk:setElementDataEx(thePlayer, "duty:mt", 0, true)

	------------ [ Other ] ------------
	blackhawk:setElementDataEx(thePlayer, "var:togmgtwarn", 0, true) -- Disable hiding management warnings by default.
	blackhawk:setElementDataEx(thePlayer, "var:toggledpms", 0, true) -- Turn toggled PMs on.
	blackhawk:setElementDataEx(thePlayer, "hud:vehicle:speedo", 1, true) -- Set vehicle Speedo to KM/H by default. (Temporary)
	blackhawk:setElementDataEx(thePlayer, "hud:reportpanel", 0, true) -- Hide the report panel on login.


	-- Send all reports from server to clientside for proper report panel function.
	if exports.global:isPlayerStaff(thePlayer, true) then
		triggerServerEvent("report:sendReportsToClient", root, thePlayer) -- Triggers an event in s_reports.lua that goes through all reports and adds them to clientside.
	end
	
	-- Log the login.
	exports.logs:addLog(thePlayer, 9, thePlayer, "[LOGIN] " .. thePlayerUsername .. " successfully logged in. (IP: " .. thePlayerIP .. " | Serial: " .. thePlayerSerial .. ")")

	-- Creates ACL account for the user if they are a lead manager and auto logs them in.
	if exports.global:isPlayerLeadManager(thePlayer, true) and (p) then
		if not getAccount(thePlayerUsername) then
			addAccount(thePlayerUsername, p, false)
			local userAcc = getAccount(thePlayerUsername)
			logIn(thePlayer, userAcc, p)
			aclGroupAddObject(aclGetGroup("Admin"), "user." .. thePlayerUsername)
			exports.global:sendMessageToManagers("[INFO] " .. thePlayerUsername .. " is logging in as a Lead Manager for the first time, created administrator account.", true)
		else
			local userAcc = getAccount(thePlayerUsername)
			logIn(thePlayer, userAcc, p)
		end
	end
end

function playerRegister(username, password, email)
	local thePlayer = source -- Because thePlayer sounds better (:

	-- Ensure all parameters are received.
	if not tostring(username) or not tostring(password) or not (email) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "Uh oh, something went wrong, try again!", 255, 0, 0, 2)
		return false
	end

	-- Check to see if the username already exists.
	local usernameExists = exports.mysql:QueryString("SELECT `username` FROM `accounts` WHERE `username` = (?)", username)

	if (usernameExists) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "That username is already taken!", 255, 0, 0, 2)
		return false
	end

	-- Check to see if the serial is already registered to another account.
	local playerSerial = getPlayerSerial(thePlayer)
	local serialExists = exports.mysql:QueryString("SELECT `serial` FROM `accounts` WHERE `serial` = (?)", playerSerial)

	if (serialExists) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "You already have an account, multiple accounts are prohibited!")
		return false
	end

	-- Check to see if the email already exists.
	local emailExists = exports.mysql:QueryString("SELECT `email` FROM `accounts` WHERE `email` = (?)", email)

	if (emailExists) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "That email is already in use!", 255, 0, 0, 2)
		return false
	end

	-- Check to see if the username is the same as the password.
	if (username == password) then
		triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "Your password can't be your username!", 255, 0, 0, 2)
		return false
	end

	----------------------------------------------------------------------- BEGIN CREATING ACCOUNT  -----------------------------------------------------------------------

	local pS = sha256(v .. sha256(password))

	passwordHash(password, "bcrypt", {cost = 11, salt = pS}, function(hash)
		if hash then
			registerAccountCallback(hash, pS, thePlayer, username, email)
		else
			triggerClientEvent(thePlayer, "login:setFeedbackText", thePlayer, 2, "Something went wrong whilst registering!", 255, 0, 0, 2)
		end
	end)
end
addEvent("login:attemptRegister", true)
addEventHandler("login:attemptRegister", root, playerRegister)

function registerAccountCallback(hash, pS, thePlayer, u, e)
	local username = tostring(u)
	local email = tostring(e)
	local hash = tostring(hash)
	local ip = getPlayerIP(thePlayer)
	local playerSerial = getPlayerSerial(thePlayer)
	local registeredDate = exports.global:getCurrentTime()

	-- Big query to save the account into database.
	mysql:Execute(
		"INSERT INTO `accounts` (`id`, `username`, `password`, `salt`, `serial`, `email`, `sessionkey`, `registered`, `lastlogin`, `ip`, `rank`, `appstate`, `app_info`, `developer`, `vehicleteam`, `factionteam`, `mappingteam`, `muted`, `reports`, `warns`, `anote`, `emeralds`, `monitor`, `punishments`) VALUES (NULL, (?), (?), (?), (?), (?), '', (?), (?), (?), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 0, 0);",
		username, hash, pS, playerSerial, email, registeredDate[3], registeredDate[3], ip
	)

	triggerClientEvent(thePlayer, "login:onRegisterSuccess", thePlayer, username)

	-- Log the registration.
	--exports.logs:addLog(thePlayer, 9, thePlayer, "[REGISTER] " .. username .. " registered a new account. (IP: " .. ip .. " | Serial: " .. playerSerial .. ")")
end

-- Temporary password change capability.
function tempPassChange(thePlayer, commandName, ...)
	if not (...) then
		outputChatBox("SYNTAX: /" .. commandName .. " [New Password]", thePlayer, 75, 230, 10)
	else
		local password = table.concat({...}, " ")
		local thePlayerName = getPlayerName(thePlayer)
		local pS = sha256(v .. sha256(password))

		outputChatBox(" ", thePlayer)
		passwordHash(password, "bcrypt", {cost = 11, salt = pS}, function(hash)
			if hash then
				outputChatBox("Your Password Hash: " .. tostring(hash), thePlayer, 75, 230, 10)
				outputChatBox(" ", thePlayer)
				outputChatBox("Your Password Salt: " .. tostring(pS), thePlayer, 75, 230, 10)
			end
		end)
	end
end
addCommandHandler("changepass", tempPassChange)