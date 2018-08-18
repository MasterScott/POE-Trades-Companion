﻿Get_TradingLeagues(forceScriptLeagues=False) {
/*		Retrieves leagues from the API
		Parse them, to keep only non-solo or non-ssf leagues
		Return the resulting list
*/
	global PROGRAM, GAME, LEAGUES

	challengeLeagues := GAME.CHALLENGE_LEAGUE
	scriptLeagues := "Standard,Hardcore"
	Loop, Parse, challengeLeagues,% ","
		scriptLeagues .= "," A_LoopField ",Hardcore " A_LoopField

	if (forceScriptLeagues = True) {
		LEAGUES := scriptLeagues
		return scriptLeagues
	}

	; HTTP Request
	postData		:= ""
	options 	:= "TimeOut: 10"
	reqHeaders	:= []
	reqHeaders.push("Host: api.pathofexile.com")
	reqHeaders.push("Connection: keep-alive")
	reqHeaders.push("Cache-Control: max-age=0")
	reqHeaders.push("Content-type: application/x-www-form-urlencoded; charset=UTF-8")
	reqHeaders.push("Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8")
	reqHeaders.push("User-Agent: Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36")
	url := "http://api.pathofexile.com/leagues?type=main"
	leaguesJSON := cURL_Download(url, postData, reqHeaders, options, false, true, false, "", reqHeadersCurl)

	; Parse league names
	apiLeagues		:= ""
	try parsedLeaguesJSON := JSON.Load(leaguesJSON)
	Loop % parsedLeaguesJSON.MaxIndex() {
		arrID 		:= parsedLeaguesJSON[A_Index]
		leagueName 	:= arrID.ID
		if !IsIn(leagueName, apiLeagues) {
 			apiLeagues .= leagueName ","
		}
	}
	StringTrimRight, apiLeagues, apiLeagues, 1
	apiLeagues := IsContaining(apiLeagues, "Standard")?apiLeagues:""

	; Parse trading leagues only
	excludedWords 		:= "SSF,Solo"
	apiTradingLeagues 		:= ""
	Loop, Parse, apiLeagues,% ","
	{
		if !IsContaining(A_LoopField, excludedWords)
			apiTradingLeagues .= A_LoopField ","
	}
	StringTrimRight, apiTradingLeagues, apiTradingLeagues, 1

	; In case leagues api is down, get from my own list on github
	if !(apiTradingLeagues) {
		postData := ""
		reqHeaders := []
		url := "http://raw.githubusercontent.com/" PROGRAM.GITHUB_USER "/" PROGRAM.GITHUB_REPO "/master/data/TradingLeagues.txt"
		rawFile := cURL_Download(url, postData, reqHeaders, "", false, true, false, "", reqHeadersCurl)

		if IsContaining(rawFile, "Error,404") {
			 ; TO_DO logging
			rawFile := ""
		}
		gitLeagues := ""		
		Loop, Parse, rawFile,% "`n",% "`r"
			if (A_LoopField)
				gitLeagues .= A_LoopField ","
		StringTrimRight, gitLeagues, gitLeagues, 1
	}

	; Set LEAGUES var content
	tradingLeagues := apiTradingLeagues?apiTradingLeagues : gitLeagues?gitLeagues : scriptLeagues
	LEAGUES := tradingLeagues

	return tradingLeagues
}

Send_GameMessage(actionType, msgString, gamePID="") {
	global PROGRAM, GAME
	Thread, NoTimers

	sendMsgMode := PROGRAM.SETTINGS.SETTINGS_MAIN.SendMsgMode

;	Retrieve the virtual key id for chat opening
	chatVK := GAME.SETTINGS.ChatKey_VK
	if (!chatVK) {
		MsgBox(4096, PROGRAM.NAME " - Operation Cancelled.", "Could not detect the chat key!"
		. "`nKey Name: " GAME.SETTINGS.ChatKey_Name
		. "`nKey VK: " GAME.SETTINGS.ChatKey_VK
		. "`nKey SC: " GAME.SETTINGS.ChatKey_SC
		. "`n"
		. "`nPlease send me an archive containing the Logs folder."
		. "`nYou can find links to GitHub / GGG / Reddit in the [About?] tray menu."
		. "`n`n(The local folder containing the Logs folder will open upon closing this box).")
		Run, % PROGRAM.MAIN_FOLDER
		Return 1
	}

	titleMatchMode := A_TitleMatchMode
	SetTitleMatchMode, RegEx ; RegEx = Fix some case where specifying only the pid does not work

	firstChar := SubStr(msgString, 1, 1) ; Get first char, to compare if its a special chat command

	if (gamePID) {
		WinActivate,[a-zA-Z0-9_] ahk_group POEGameGroup ahk_pid %gamePID%
		WinWaitActive,[a-zA-Z0-9_] ahk_group POEGameGroup ahk_pid %gamePID%, ,2
	}
	else {
		WinActivate,[a-zA-Z0-9_] ahk_group POEGameGroup
		WinWaitActive,[a-zA-Z0-9_] ahk_group POEGameGroup, ,2
	}
	if (ErrorLevel) {
		return "WINWAITACTIVE_TIMEOUT", ; TO_DO logs + notif?
	}
	GoSub, Send_GameMessage_OpenChat
	GoSub, Send_GameMessage_ClearChat

	if (actionType = "WRITE_SEND") {
		if (sendMsgMode = "Clipboard")
			Clip(msgString)
		else if (sendMsgMode = "SendInput")
			SendInput,%msgString%
		else if (sendMsgMode = "SendEvent")
			SendEvent,%msgString%

		SendEvent,{Enter}
	}
	else if (actionType = "WRITE_DONT_SEND") {
		if (sendMsgMode = "Clipboard")
			Clip(msgString)
		else if (sendMsgMode = "SendInput")
			SendInput,%msgString%
		else if (sendMsgMode = "SendEvent")
			SendEvent,%msgString%
	}
	else if (actionType = "WRITE_GO_BACK") {
		foundPos := InStr(msgString, "{X}"), _strLen := StrLen(msgString), leftPresses := _strLen-foundPos+1-3
		msgString := StrReplace(msgString, "{X}", "")

		if (sendMsgMode = "Clipboard")
			Clip(msgString)
		else if (sendMsgMode = "SendInput")
			SendInput,%msgString%
		else if (sendMsgMode = "SendEvent")
			SendEvent,%msgString%

		SendInput {Left %leftPresses%}
	}

	SetTitleMatchMode, %titleMatchMode%
	Return

	Send_GameMessage_ClearChat:
		if !IsIn(firstChar, "/,`%,&,#,@") ; Not a command. We send / then remove it to make sure chat is empty
			SendEvent,{sc035}{BackSpace} ; Slash		
	Return

	Send_GameMessage_OpenChat:
		if IsIn(chatVK, "0x1,0x2,0x4,0x5,0x6,0x9C,0x9D,0x9E,0x9F") { ; Mouse buttons
			keyDelay := A_KeyDelay, keyDuration := A_KeyDuration
			SetKeyDelay, 10, 10
			if (gamePID)
				ControlSend, ,{VK%keyVK%}, [a-zA-Z0-9_] ahk_groupe POEGameGroup ahk_pid %gamePID% ; Mouse buttons tend to activate the window under the cursor.
																	  						  	  ; Therefore, we need to send the key to the actual game window.
			else {
				WinGet, activeWinHandle, ID, A
				ControlSend, ,{VK%keyVK%}, [a-zA-Z0-9_] ahk_groupe POEGameGroup ahk_pid %activeWinHandle%
			}
			SetKeyDelay,% keyDelay,% keyDuration
		}
		else
			SendEvent,{VK%chatVK%}
	Return
}

Get_RunningInstances() {
	global POEGameArr

	runningInstances := {}
	runningInstances.Count := 0

	for id, pName in POEGameArr {
		hwndList := Get_Windows_ID(pName, "ahk_exe")
		if (hwndList) {
			matchingHwnd .= hwndList ","
		}
	}
	StringTrimRight, matchingHwnd, matchingHwnd, 1

	Loop, Parse, matchingHwnd,% ","
	{
		runningInstances[A_Index] := {}
		runningInstances.Count := A_Index

		WinGet, pPID, PID, ahk_id %A_LoopField%
		WinGet, pPath, ProcessPath, ahk_id %A_LoopField%
		SplitPath, pPath, pFile, pFolder

		runningInstances[A_Index]["Hwnd"] := A_LoopField
		runningInstances[A_Index]["Folder"] := pFolder
		runningInstances[A_Index]["File"] := pFile
		runningInstances[A_Index]["PID"] := pPID
	}
	
	return runningInstances
}

Get_GameLogsFile() {
	global POEGameArr

	runningInstances := Get_RunningInstances()
	Loop % runningInstances.Count {
		thisInstanceFolder := runningInstances[A_Index]["Folder"]
		hasDifferentFolders := (thisInstanceFolder && prevInstanceFolder && thisInstanceFolder != prevInstanceFolder)?(True):(False)
		prevInstanceFolder := thisInstanceFolder
	}
	if (runningInstances.Count = 0)
		Return
	else if (runningInstances.Count > 1 && hasDifferentFolders) {
		instanceInfos := GUI_ChooseInstance.Create(runningInstances, "Folder")
		logsFile := instanceInfos["Folder"] "\logs\Client.txt"
	}
	else {
		logsFile := runningInstances[1]["Folder"] "\logs\Client.txt"
	}
	if !FileExist(logsFile) && (logsFile != "\logs\Client.txt") {
		TrayNotifications.Show("Logs file not found", "The specified file does not exist:`n" logsFile)
		Return
	}

	Return logsFile
}

Monitor_GameLogs() {
	global RUNTIME_PARAMETERS
	static logsFile

	if !(logsFile) {
		SetTimer,% A_ThisFunc, Delete

		if (RUNTIME_PARAMETERS.GameFolder)
			logsFile := RUNTIME_PARAMETERS.GameFolder "\logs\Client.txt"
		else
			logsFile := Get_GameLogsFile()

		if (logsFile)
			SetTimer,% A_ThisFunc, 500
		else {
			SetTimer,% A_ThisFunc, -10000 ; TO_DO logs
		}
	}

	newFileContent := Read_GameLogs(logsFile)
	if (newFileContent)
		Parse_GameLogs(newFileContent)
}

Parse_GameLogs(strToParse) {
	global PROGRAM, GuiTrades, LEAGUES

	static poeTradeRegex 			:= {String:"(.*)Hi, I would like to buy your (.*) listed for (.*) in (.*)" ; 1: Other, 2: Item, 3: Price, 4: League + Tab + Other
										, Other:1, Item:2, Price:3, League:4}
	static poeTradeUnpricedRegex 	:= {String:"(.*)Hi, I would like to buy your (.*) in (.*)" ; 1: Other, 2: Item, 3: League + Tab + Other
										, Other:1, Item:2, League:3}
	static poeTradeCurrencyRegex	:= {String:"(.*)Hi, I'd like to buy your (.*) for my (.*) in (.*)" ; 1: Other, 2: Currency, 3: Price, 4: League + Tab + Other
										, Other:1, Item:2, Price:3, League:4}
	static poeTradeStashRegex 		:= {String:"\(stash tab ""(.*)""; position: left (.*), top (.*)\)(.*)" ; 1: Tab, 2: Left, 3: Top, 4: Other
										, Tab:1, Left:2, Top:3, Other:4}
	static poeTradeQualityRegEx 		:= {String:"level (.*) (.*)% (.*)" ; 1: Item level, 2: Item quality, 3: Item name
										, Level:1, Quality:2, Item:3}


	static poeAppRegEx 				:= {String:"(.*)wtb (.*) listed for (.*) in (.*)" ; 1: Other, 2: Item, 3: Price, 4: League + Tab + Other
										, Other:1, Item:2, Price:3, League:4}
	static poeAppUnpricedRegex 		:= {String:"(.*)wtb (.*) in (.*)" ; 1: Other, 2: Item, 3: League + Tab + Other
										, Other:1, Item:2, League:3}
	static poeAppStashRegex 		:= {String:"\(stash ""(.*)""; left (.*), top(.*)\)(.*)" ; 1: Tab, 2: Left, 3: Top, 4: Other
										, Tab:1, Left:2, Top:3, Other:4}
	static poeAppQualityRegEx 		:= {String:"(.*) \((.*)/(.*)%\)" ; 1: Item name, 2: Item level, 3: Item quality
										, Item:1, Level:2, Quality:3}


	static allTradingRegex := {"poeTrade":poeTradeRegex
						 	  ,"poeTrade_Unpriced":poeTradeUnpricedRegex
							  ,"currencyPoeTrade":poeTradeCurrencyRegex
							  ,"poeApp":poeAppRegEx
							  ,"poeApp_Unpriced":poeAppUnpricedRegex}

	static areaRegexStr := ("^(?:[^ ]+ ){6}(\d+)\] : (.*?) (?:has) (joined|left) (?:the area.*)") 

	Loop, Parse,% strToParse,`n,`r ; For each line
	{
		if RegExMatch(A_LoopField, "SO)" areaRegexStr, areaPat) {
			instancePID := areaPat.1, playerName := areaPat.2, joinedOrLeft := areaPat.3
			if (joinedOrLeft = "Joined")
				GUI_Trades.SetTabStyleJoinedArea(playerName)
			else 
				GUI_Trades.UnSetTabStyleJoinedArea(playerName)
		}
		else if RegExMatch(A_LoopField, "SO)^(?:[^ ]+ ){6}(\d+)\] (?=[^#$&%]).*@(?:From|De|От кого|จาก|Von|Desde) (.*?): (.*)", whisperPat ) { ; If it's a whisper
			instancePID := whisperPat.1, whispNameFull := whisperPat.2, whispMsg := whisperPat.3
			nameAndGuild := SplitNameAndGuild(whispNameFull), whispName := nameAndGuild.Name, whispGuild := nameAndGuild.Guild
			GuiTrades.Last_Whisper_Name := whispName

			; Retrieve the regEx pattern specific to the whisper type
			for subRegEx, nothing in allTradingRegex {
				if RegExMatch(whispMsg, "iS)" allTradingRegex[subRegEx]["String"]) { ; Match found
					matchingRegEx := allTradingRegex[subRegEx]
					tradeRegExStr := allTradingRegex[subRegEx]["String"]
					tradeRegExName := subRegEx
					Break
				}
			}

			if (matchingRegEx) { ; Trade whisper match
				RegExMatch(whispMsg, "iSO)" tradeRegExStr, tradePat)

				tradeBuyerName := whispName, tradeBuyerGuild := whispGuild
				tradeOtherStart := tradePat[matchingRegEx["Other"]]
				tradeItem := tradePat[matchingRegEx["Item"]]
				tradePrice := tradePat[matchingRegEx["Price"]]
				tradeLeagueAndMore := tradePat[matchingRegEx["League"]]
				AutoTrimStr(tradeBuyerName, tradeItem, tradePrice, tradeOtherStart)

				Loop, Parse, LEAGUES,% ","
				{
					if RegExMatch(tradeLeagueAndMore, "iSO)" A_LoopField "(.*)", leagueAndMorePat) {
						tradeLeague := A_LoopField
						restOfWhisper := leagueAndMorePat.1

						AutoTrimStr(tradeLeague, restOfWhisper)
						Break
					}
				}
				if !(tradeLeague) {
					MsgBox(4096, "", "Failed to parse the league from whisper message:`n`n""" whispMsg """") ; TO_DO tray notif instead
					Return
				}

				isPoeTrade := IsIn(tradeRegExName, "poeTrade,poeTrade_Unpriced,currencyPoeTrade")
				isPoeApp := IsIn(tradeRegExName, "poeApp,poeApp_Unpriced")
				qualRegEx := (isPoeTrade)?(poeTradeQualityRegEx):(isPoeApp)?(poeAppQualityRegEx):("")
				stashRegEx := (isPoeTrade)?(poeTradeStashRegex):(isPoeApp)?(poeAppStashRegex):("")

				if RegExMatch(tradeItem, "iSO)" qualRegEx.String, qualPat) {
					tradeItem := qualPat[qualRegEx["Item"]]
					tradeItemLevel := qualPat[qualRegEx["Level"]]
					tradeItemQual := qualPat[qualregEx["Quality"]]
					AutoTrimStr(tradeItem, tradeItemLevel, tradeItemQual)

					tradeItemFull := tradeItem " (Lvl:" tradeItemLevel " / Qual:" tradeItemQual "%)"
				}
				else {
					tradeItemFull := tradeItem
					AutoTrimStr(tradeItemFull)
				}
				if RegExMatch(restOfWhisper, "iSO)" stashRegEx.String, stashPat) {
					tradeStashTab := stashPat[stashRegEx["Tab"]]
					tradeStashLeft := stashPat[stashRegEx["Left"]]
					tradeStashTop := stashPat[stashRegEx["Top"]]
					tradeOtherEnd := stashPat[stashRegEx["Other"]]
					AutoTrimStr(tradeStashTab, tradeStashLeft, tradeStashTop, tradeOtherEnd)

					tradeStashLeftAndTop := tradeStashLeft ";" tradeStashTop
				}
				else {
					tradeOtherEnd := restOfWhisper
					AutoTrimStr(tradeOtherEnd)
				}

				tradeOther := (tradeOtherStart && tradeOtherEnd)?(tradeOtherStart "`n" tradeOtherEnd)
				: (tradeOtherStart && !tradeOtherEnd)?(tradeOtherStart)
				: (tradeOtherEnd && !tradeOtherStart)?(tradeOtherEnd)
				: ("")

				tradeStashFull := (tradeLeague && !tradeStashTab)?(tradeLeague)
				: (tradeLeague && tradeStashTab)?(tradeLeague " (Tab:" tradeStashTab " / Pos:" tradeStashLeftAndTop ")")
				: ("ERROR")

				timeStamp := A_YYYY "/" A_MM "/" A_DD " " A_Hour ":" A_Min ":" A_Sec

				tradeInfos := {Buyer:tradeBuyerName, Item:tradeItemFull, Price:tradePrice, Stash:tradeStashFull, Other:tradeOther
					,BuyerGuild:tradeBuyerGuild, TimeStamp:timeStamp,PID:instancePID, IsInArea:False, HasNewMessage:False, WithdrawTally:0, Time: A_Hour ":" A_Min
					,WhisperSite:tradeRegExName,TimeStamp:A_YYYY "/" A_MM "/" A_DD " " A_Hour ":" A_Min ":" A_Sec,UniqueID:GUI_Trades.GenerateUniqueID()
					,TradeVerify:"Grey"}
				err := Gui_Trades.PushNewTab(tradeInfos)

				if !(err) {
					if (PROGRAM.SETTINGS.SETTINGS_MAIN.TradingWhisperSFXToggle = "True") && FileExist(PROGRAM.SETTINGS.SETTINGS_MAIN.TradingWhisperSFXPath)
						SoundPlay,% PROGRAM.SETTINGS.SETTINGS_MAIN.TradingWhisperSFXPath

					doPBNote := (PROGRAM.SETTINGS.SETTINGS_MAIN.PushBulletOnTradingWhisper = "True")
					if (PROGRAM.SETTINGS.SETTINGS_MAIN.PushBulletOnlyWhenAFK = "True" && idk) { ; TO_DO afk state global
						doPBNote := True
					}
					else {
						doPBNote := True
					}

					if (doPBNote = True) {
						; pbErr := PB_PushNote(PROGRAM.SETTINGS.SETTINGS_MAIN.PushBulletToken, "Buying request from " whispName ":"
						; , "Item: " tradeItemFull "\nPrice: " tradePrice "\nStash: " tradeStashFull)
						pbErr := PB_PushNote("a", "Buying request from " whispName ":"
						, "Item: " tradeItemFull "\nPrice: " tradePrice "\nStash: " tradeStashFull)

						; TO_DO logs pbErr
					}
					; }

					if !WinActive("ahk_pid " instancePID) { ; If the instance is not active
						if ( PROGRAM.SETTINGS.SETTINGS_MAIN.ShowTabbedTrayNotificationOnWhisper = "True" ) {
							; TrayNotifications.Show("Buying request from " whispName ":", "Item: " A_Tab tradeItemFull "`nPrice: " A_Tab tradePrice "`nStash: " A_Tab tradeStashFull)
						}
					}
				}
			}
			else { ; No trading whisper match
				; Add whisper to buyer's tab if existing
				Loop % GuiTrades.Tabs_Count {
					tabInfos := Gui_Trades.GetTabContent(A_Index)
					if (tabInfos.Buyer = whispName) {
						Gui_Trades.UpdateSlotContent(A_Index, "Other", "[" A_Hour ":" A_Min "] " whispMsg)
						GUI_Trades.SetTabStyleWhisperReceived(whispName)
					}
				}
				if (PROGRAM.SETTINGS.SETTINGS_MAIN.RegularWhisperSFXToggle = "True") && FileExist(PROGRAM.SETTINGS.SETTINGS_MAIN.RegularWhisperSFXPath)
					SoundPlay,% PROGRAM.SETTINGS.SETTINGS_MAIN.RegularWhisperSFXPath

				if !WinActive("ahk_pid " instancePID) { ; If the instance is not active
					if ( PROGRAM.SETTINGS.SETTINGS_MAIN.ShowTabbedTrayNotificationOnWhisper = "True" ) {
						TrayNotifications.Show("Whisper from " whispName ":", whispMsg)
					}
				}
			}
		}
	}
}

Read_GameLogs(logsFile) {
	global sLOGS_FILE, sLOGS_TIMER
	static logsFileObj

	if (!logsFileObj && logsFile) {
		logsFileObj := FileOpen(logsFile, "r")
		logsFileObj.Read()
		; TO_DO add logs, start monitoring logs file 
	}

	if ( logsFileObj.pos < logsFileObj.length ) {
		newFileContent := logsFileObj.Read()
		return newFileContent 
	}
	else if (logsFileObj.pos > logsFileObj.length) || (logsFileObj.pos < 0) {
		; TO_DO add logs, file was shorten 
		logsFileObj.Close()
		logsFileObj := FileOpen(logsFile, "r")
		logsFileObj.Read()
	}
}

SplitNameAndGuild(str) {
	if RegExMatch(str, "O)<(.*)>(.*)", guildPat) {
		guild := guildPat.1
		name := guildPat.2

		_autoTrim := A_AutoTrim
		AutoTrim, On
		name = %name%
		guild = %guild%
		AutoTrim, %_autoTrim%

		Return {Guild:guild,Name:name}
	}
	else
		Return {Guild:"",Name:str}
}

IsTradingWhisper(str) {
	firstChar := SubStr(str, 1, 1)

	; poe.trade regex
	poeTradeRegex := "@.* Hi, I would like to buy your .* listed for .* in"
	poeTradeUnpricedRegex := "@.* Hi, I would like to buy your .* in"
	currencyPoeTradeRegex := "@.* Hi, I'd like to buy your .* for my .* in"
	; poeapp.com regex
	poeAppRegex := "@.* wtb .* listed for .* in .*"
	poeAppUnpricedRegex := "@.* wtb .* in"

	allRegexes := []
	allRegexes.Push(poeTradeRegex, poeTradeUnpricedRegex, currencyPoeTradeRegex
		, poeAppRegex, poeAppUnpricedRegex)

	; Make sure it starts with @ and doesnt contain line break
	if InStr(str, "`n") || (firstChar != "@")  {
		Return 0
	}

	; Check if trading whisper
	Loop % allRegexes.MaxIndex() { ; compare whisper with regex
		if RegExMatch(str, "S)" allRegexes[A_Index]) { ; Trading whisper detected
			isTradingWhisper := True
		}
		if (isTradingWhisper)
			Break
	}

	Return isTradingWhisper
}