SAHSellEntries = {}
SAHSearchHistory = {}
SAH_AUCTION_DURATION = 3
SAH_ExactMatch = nil
SAH_IsUsable = nil

local SAH = { orig = {}, tabs = { sell = { index = 4 }, buy = { index = 5 } }
}
local currentJob,scanData,bestPriceOurStackSize,currentAuctionItem,postedItem,entries,searchQuery,SAH_PurchasedCount,SAH_OrderedCount,SAH_PurchasedNumber,SAH_OrderedNumber

local currentPage = 0
local state = 0 -- 0(Idle), 1(prequery), 2(postquery), 3(processing)
local sellstate = 0 -- 0(Idle), 1(make list of bag positions), 2(post multiple), 3(waiting to post another multiple after AUCTION_OWNED_LIST_UPDATE)
local totalbought = 0
local sellorbuy = 0
local numSellRepeat = 0
local SAH_timeOfLastUpdate = GetTime()
local SAH_timeOfLastPageScan = 0
local selectedEntries = {}
local lastSelectedEntry
local SellRepeat = {}
local SellRepeatBagPositions = {}
local selectedEntries = {}
local DoNotCapitalize = { ["the"] = true,["a"] = true,["of"] = true,["on"] = true,["by"] = true,["and"] = true, }
local SAH_PurchasedItems = {}
local SAH_ItemsToPurchasePages

--Core Functions
function SAH_OnEvent()
	if event == "AUCTION_ITEM_LIST_UPDATE" then
		if state == 2 then
			state = 3
			SAH_ProcessQueryResults()
		end
	elseif event == "AUCTION_OWNED_LIST_UPDATE" then
		if sellstate == 1 then
			SAH_AuctionSellRepeatSetup()
			sellstate = 2
		elseif SellRepeatBagPositions[1] then
			sellstate = 2
		end
		SAH_timeOfLastUpdate = GetTime() - .49999999999
	elseif event == "AUCTION_BIDDER_LIST_UPDATE" and AuctionFrame:IsShown() and (PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.buy.index) then
		SAH_timeOfLastUpdate = GetTime() - .49999999999
		SAH_HideElemsDelay = true
	elseif event == "ADDON_LOADED" then
		SAH_OnAddonLoaded()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		SAH_OnAuctionHouseClosed()
	end
end
function SAH_OnUpdate()
	if GetTime() - SAH_timeOfLastUpdate > 0.5 then
		if state == 1 then
			if CanSendAuctionQuery() then SAH_SubmitQuery() end
		end
		if SAH_HideElemsDelay then
			SAH_HideElems(SAH.tabs.buy.hiddenElements)
			SAH_HideElemsDelay = nil
		end
		SAH_timeOfLastUpdate = GetTime()
		if sellstate == 2 then
			if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index then
				SAH_AuctionSellRepeatAuctionPost()
			else
				SellRepeatBagPositions = {}
				sellstate = 0
				if numSellRepeat > 1 then DEFAULT_CHAT_FRAME:AddMessage("SAH: Posted "..(numSellRepeat).." items", 1, 1, 0.5) numSellRepeat = 0 end
			end
		elseif sellstate == 1 or sellstate == 3 then
			sellstate = 0
			if numSellRepeat > 1 then DEFAULT_CHAT_FRAME:AddMessage("SAH: Posted "..(numSellRepeat).." items", 1, 1, 0.5) numSellRepeat = 0 end
		end
	end
end
function SAH_OnAddonLoaded()
	if string.lower(arg1) == "blizzard_auctionui" then
		SAH_AddTabs()
		SAH_AddPanels()
		SAH_SetupHookFunctions()
		SAH.tabs.sell.hiddenElements = { AuctionsTitle, AuctionsScrollFrame, AuctionsButton1, AuctionsButton2, AuctionsButton3, AuctionsButton4, AuctionsButton5, AuctionsButton6, AuctionsButton7, AuctionsButton8, AuctionsButton9,
										 AuctionsQualitySort, AuctionsDurationSort, AuctionsHighBidderSort, AuctionsBidSort, AuctionsCancelAuctionButton }
		SAH.tabs.buy.hiddenElements = { BidTitle, BidScrollFrame, BidButton1, BidButton2, BidButton3, BidButton4, BidButton5, BidButton6, BidButton7, BidButton8, BidButton9, BidQualitySort, BidLevelSort, BidDurationSort,
										BidBuyoutSort, BidStatusSort, BidBidSort, BidBidButton, BidBuyoutButton, BidBidPrice, BidBidText }
		SAH.tabs.sell.recommendationElements = { SAHRecommendText, SAHRecommendPerItemText, SAHRecommendPerItemPrice, SAHRecommendPerStackText, SAHRecommendPerStackPrice, SAHRecommendBasisText, SAHRecommendItemTex, }
		SAH_QuickBuyUpdateButtons()
	end
end
function SAH_SetupHookFunctions()
	SAH.orig.AuctionFrameAuctions_OnShow = AuctionFrameAuctions_OnShow
	AuctionFrameAuctions_OnShow = SAH_Sell_AuctionFrameAuctions_OnShow

	SAH.orig.AuctionsRadioButton_OnClick = AuctionsRadioButton_OnClick
	AuctionsRadioButton_OnClick = SAH_Sell_AuctionsRadioButton_OnClick
	
	if IsAddOnLoaded("AdvancedTradeSkillWindow") then
		ATSWSkillIcon:RegisterForClicks("LeftButtonUp", "RightButtonDown")
		ATSWSkillIcon:SetScript("OnMouseDown", SAH_ATSWSkill_OnMouseDown)
		for i=1, 8 do
			getglobal("ATSWReagent"..i):RegisterForClicks("LeftButtonUp", "RightButtonDown")
			getglobal("ATSWReagent"..i):SetScript("OnMouseDown", SAH_ATSWReagent_OnMouseDown)
		end
	end
	SAH.orig.AuctionSellItemButton_OnEvent = AuctionSellItemButton_OnEvent
	AuctionSellItemButton_OnEvent = SAH_AuctionSellItemButton_OnEvent
	
	SAH.orig.AuctionFrameTab_OnClick = AuctionFrameTab_OnClick
	AuctionFrameTab_OnClick = SAH_AuctionFrameTab_OnClick
	
	SAH.orig.ContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick
	ContainerFrameItemButton_OnClick = SAH_ContainerFrameItemButton_OnClick
	
	SAH.orig.AuctionFrameBids_Update = AuctionFrameBids_Update
	AuctionFrameBids_Update = SAH_AuctionFrameBids_Update
	
	SAH.orig.AuctionFrameAuctions_Update = AuctionFrameAuctions_Update
	AuctionFrameAuctions_Update = SAH_AuctionFrameAuctions_Update
	
	SAH.orig.AuctionsCreateAuctionButton_OnClick = AuctionsCreateAuctionButton:GetScript('OnClick')
	AuctionsCreateAuctionButton:SetScript('OnClick', SAH_AuctionsCreateAuctionButton_OnClick)
end
function SAH_OnAuctionHouseClosed()
	if state ~= 0 then SAH_Scan_Abort() end
	SAHSellPanel:Hide()
    SAHBuyPanel:Hide()
end
function SAH_AuctionFrameTab_OnClick(index)
	if not index then index = this:GetID() end
	if state ~= 0 then SAH_Scan_Abort() end
	SAHSellPanel:Hide()
    SAHBuyPanel:Hide()
	if index == 2 then SAH_ShowElems(SAH.tabs.buy.hiddenElements) end
	if index == 3 then SAH_ShowElems(SAH.tabs.sell.hiddenElements) end
	if index == SAH.tabs.sell.index then
		AuctionFrameTab_OnClick(3)
		PanelTemplates_SetTab(AuctionFrame, SAH.tabs.sell.index)
		SAHSellPanel:Show()
		SAH_HideElems(SAH.tabs.sell.hiddenElements)
		AuctionFrame:EnableMouse(false)
		SAH_OnNewAuctionUpdate()
		SAHSellStopScanningButton:Disable()
    elseif index == SAH.tabs.buy.index then
        AuctionFrameTab_OnClick(2)
		PanelTemplates_SetTab(AuctionFrame, SAH.tabs.buy.index)
		SAHBuyPanel:Show()
		SAH_HideElems(SAH.tabs.buy.hiddenElements)
		AuctionFrame:EnableMouse(false)
		SAH_Buy_StatisticsUpdate()
		SAH_Buy_ScrollbarUpdate()
		SAH_timeOfLastUpdate = GetTime() - .49999999999
		SAH_HideElemsDelay = true
		SAHBuyStopScanningButton:Disable()
    else
        SAH.orig.AuctionFrameTab_OnClick(index)
		lastItemPosted = nil
	end
end
function SAH_Log(msg)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0) end
end
function SAH_AddPanels()
	local sellFrame = CreateFrame("Frame", "SAHSellPanel", AuctionFrame, "SAHSellTemplate")
	sellFrame:SetParent("AuctionFrame")
	sellFrame:SetPoint("TOPLEFT", "AuctionFrame", "TOPLEFT")
	SAH_ReLevel(sellFrame)
	sellFrame:Hide()
    
    local buyFrame = CreateFrame("Frame", "SAHBuyPanel", AuctionFrame, "SAHBuyTemplate")
	buyFrame:SetParent("AuctionFrame")
	buyFrame:SetPoint("TOPLEFT", "AuctionFrame", "TOPLEFT")
	SAH_ReLevel(buyFrame)
	buyFrame:Hide()
end
function SAH_AddTabs()
	SAH.tabs.sell.index = AuctionFrame.numTabs + 1
    SAH.tabs.buy.index = AuctionFrame.numTabs + 2
	local sellTabName = "AuctionFrameTab"..SAH.tabs.sell.index
    local buyTabName = "AuctionFrameTab"..SAH.tabs.buy.index
	local sellTab = CreateFrame("Button", sellTabName, AuctionFrame, "AuctionTabTemplate")
    local buyTab = CreateFrame("Button", buyTabName, AuctionFrame, "AuctionTabTemplate")
	setglobal(sellTabName, sellTab)
    setglobal(buyTabName, buyTab)
	sellTab:SetID(SAH.tabs.sell.index)
	sellTab:SetText("Sell")
	sellTab:SetPoint("LEFT", getglobal("AuctionFrameTab"..AuctionFrame.numTabs), "RIGHT", -8, 0)
    buyTab:SetID(SAH.tabs.buy.index)
	buyTab:SetText("Buy")
	buyTab:SetPoint("LEFT", getglobal("AuctionFrameTab"..SAH.tabs.sell.index), "RIGHT", -8, 0)
	if pfUI and pfUI.api.SkinTab and pfUI.api.GetPerfectPixel then
		local rawborder, border = pfUI.api.GetBorderSize()
		local bpad = rawborder > 1 and border - pfUI.api.GetPerfectPixel() or pfUI.api.GetPerfectPixel()
		pfUI.api.SkinTab(getglobal("AuctionFrameTab"..SAH.tabs.sell.index))
		getglobal("AuctionFrameTab"..SAH.tabs.sell.index):ClearAllPoints()
		getglobal("AuctionFrameTab"..SAH.tabs.sell.index):SetPoint("LEFT", getglobal("AuctionFrameTab"..AuctionFrame.numTabs), "RIGHT", border*2 + 1, 0)
		pfUI.api.SkinTab(getglobal("AuctionFrameTab"..SAH.tabs.buy.index))
		getglobal("AuctionFrameTab"..SAH.tabs.buy.index):ClearAllPoints()
		getglobal("AuctionFrameTab"..SAH.tabs.buy.index):SetPoint("LEFT", getglobal("AuctionFrameTab"..AuctionFrame.numTabs + 1), "RIGHT", border*2 + 1, 0)
	end
	PanelTemplates_SetNumTabs(AuctionFrame, SAH.tabs.buy.index)
    PanelTemplates_EnableTab(AuctionFrame, SAH.tabs.sell.index)
	PanelTemplates_EnableTab(AuctionFrame, SAH.tabs.buy.index)
end
function SAH_HideElems(tt)
	if not tt then return end
	for i,x in ipairs(tt) do x:Hide() x:SetAlpha(0) end
end
function SAH_ShowElems(tt)
	for i,x in ipairs(tt) do x:Show() x:SetAlpha(1) end
end
function SAH_PluralizeIf(word, count)
	if count and count == 1 then return word else return word.."s" end
end
function SAH_Round(v)
	return math.floor(v + 0.5)
end
function SAH_SetSize(set)
    local size = 0
	for _,_ in pairs(set) do size = size + 1 end
	return size
end
function SAH_ReLevel(frame)
	local myLevel = frame:GetFrameLevel() + 1
	local children = { frame:GetChildren() }
	for _,child in pairs(children) do
		child:SetFrameLevel(myLevel)
		SAH_ReLevel(child)
	end
end
function SAH_ATSWReagent_OnMouseDown()
	if arg1 == "LeftButton" and IsShiftKeyDown() and not ChatFrameEditBox:IsVisible() and AuctionFrame:IsVisible() then
		local link = ATSW_GetTradeSkillReagentItemLink(ATSWFrame.selectedSkill, this:GetID())
		local name = string.gsub(link,"^.-%[(.*)%].*", "%1")
		SAHBuySearchBox:SetText(name)
		SAHBuySearchButton_OnClick()
	end
end
function SAH_ATSWSkill_OnMouseDown()
	if arg1 == "LeftButton" and IsShiftKeyDown() and not ChatFrameEditBox:IsVisible() and AuctionFrame:IsVisible() then
		local link = ATSW_GetTradeSkillItemLink(ATSWFrame.selectedSkill)
		local name = string.gsub(link,"^.-%[(.*)%].*", "%1")
		SAHBuySearchBox:SetText(name)
		SAHBuySearchButton_OnClick()
	end
end
function SAH_ContainerFrameItemButton_OnClick(button)
	if button == "LeftButton" and IsShiftKeyDown() and not ChatFrameEditBox:IsVisible() and AuctionFrame:IsVisible() and (PanelTemplates_GetSelectedTab(AuctionFrame) == 1 or PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.buy.index) then
		local itemLink = GetContainerItemLink(this:GetParent():GetID(), this:GetID())
		if itemLink then
			local itemName = string.gsub(itemLink, "^.-%[(.*)%].*", "%1")
			if PanelTemplates_GetSelectedTab(AuctionFrame) == 1 then
				BrowseName:SetText(itemName)
			elseif PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.buy.index then
				SAHBuySearchBox:SetText(itemName)
				SAHBuySearchButton_OnClick()
			end
		end
	else
		if button == "RightButton" and AuctionFrame:IsVisible() and PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index and not IsShiftKeyDown() and not IsAltKeyDown() and not IsControlKeyDown() then
			PickupContainerItem(this:GetParent():GetID(),this:GetID())
			ClickAuctionSellItemButton()
			ClearCursor()
		else
			SAH.orig.ContainerFrameItemButton_OnClick(button)
		end
	end
end
function SAH_QualityColor(code)
	if code == 0 then return "ff9d9d9d" -- poor, gray
	elseif code == 1 then return "ffffffff" -- common, white
	elseif code == 2 then return "ff1eff00" -- uncommon, green
	elseif code == 3 then return "ff0070dd" -- rare, blue
	elseif code == 4 then return "ffa335ee" -- epic, purple
	elseif code == 5 then return "ffff8000" end -- legendary, orange
end

--Scan Functions
function SAH_Scan_Complete()
	if state ~= 0 then
		if currentJob.onComplete then currentJob.onComplete(scanData) end
		currentJob = nil
		currentPage = 0
		scanData = nil
		state = 0
		SAHBuyStopScanningButton:Disable()
		SAHSellStopScanningButton:Disable()
		SAH_PurchasedItems = {}
		SAH_ItemsToPurchasePages = nil
	end
end
function SAH_Scan_Abort()
	if state ~= 0 then
		if currentJob and currentJob.onAbort then currentJob.onAbort() end
		currentJob = nil
		currentPage = 0
		scanData = nil
		state = 0
		SAHBuyStopScanningButton:Disable()
		SAHSellStopScanningButton:Disable()
		SAH_PurchasedItems = {}
		SAH_ItemsToPurchasePages = nil
	end
end
function SAH_Scan_Start(job)
	if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index then SAH_SetSellMessage("Scanning auctions ...") else SAH_SetBuyMessage("Scanning auctions ...") end
	if state ~= 0 then SAH_Scan_Abort() end
	currentJob = job
	scanData = {}
	state = 1
	if SAH_OrderedCount > 0 and SAH_timeOfLastPageScan > GetTime() then
		SAH_ProcessQueryResults(true)
		if sellorbuy == 1 and SAH_OrderedCount > 0 and SAH_PurchasedCount == SAH_OrderedCount then
			SAH_Scan_Complete()
			return
		end
	else
		scanData = {}
	end
	SAHBuyStopScanningButton:Enable()
	SAHSellStopScanningButton:Enable()
end
function SAH_Scan_CreateQuery(parameterMap)
	local query = { name = nil, minLevel = "", maxLevel = "", invTypeIndex = nil, classIndex = nil, subclassIndex = nil, isUsable = nil, qualityIndex = nil }
	for k,v in pairs(parameterMap) do query[k] = v end
	return query
end
function SAH_SubmitQuery()
	if SAH_ItemsToPurchasePages and SAH_ItemsToPurchasePages[1] then
		currentPage = SAH_ItemsToPurchasePages[1]
		QueryAuctionItems(currentJob.query.name, currentJob.query.minLevel, currentJob.query.maxLevel, currentJob.query.invTypeIndex, currentJob.query.classIndex, currentJob.query.subclassIndex, SAH_ItemsToPurchasePages[1] - 1, currentJob.query.isUsable, currentJob.query.qualityIndex)
		table.remove(SAH_ItemsToPurchasePages,1)
	else
		QueryAuctionItems(currentJob.query.name, currentJob.query.minLevel, currentJob.query.maxLevel, currentJob.query.invTypeIndex, currentJob.query.classIndex, currentJob.query.subclassIndex, currentPage, currentJob.query.isUsable, currentJob.query.qualityIndex)
		currentPage = currentPage + 1
	end
	state = 2
end
function SAH_Scan_ClearTooltip()
	for j=1, 30 do
		leftEntry = getglobal('SAHScanTooltipTextLeft'..j):SetText()
		rightEntry = getglobal('SAHScanTooltipTextRight'..j):SetText()
	end
end
function SAH_Scan_ExtractTooltip()
	local tooltip = {}
	for j=1, 30 do
		local leftEntry = getglobal('SAHScanTooltipTextLeft'..j):GetText()
		if leftEntry then tinsert(tooltip, leftEntry) end
		local rightEntry = getglobal('SAHScanTooltipTextRight'..j):GetText()
		if rightEntry then tinsert(tooltip, rightEntry) end
	end
	return tooltip
end
function SAH_Scan_ItemCharges(tooltip)
	for _,entry in ipairs(tooltip) do
		local chargesString = gsub(entry, "(%d+) Charges", "%1")
		local charges = tonumber(chargesString)
		if charges then return charges end
	end
end	
function SAH_ProcessQueryResults(processDataOnly)
	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")
	for i = 1, numBatchAuctions do
		local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", i)
		local itemLink = GetAuctionItemLink("list", i)
		local duration = GetAuctionItemTimeLeft("list", i)
		SAH_Scan_ClearTooltip()
		SAHScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		SAHScanTooltip:SetAuctionItem("list", i)
		SAHScanTooltip:Show()
		local tooltip = SAH_Scan_ExtractTooltip()
		count = SAH_Scan_ItemCharges(tooltip) or count
		local scanDatum = { name = name, texture = texture, count = count, quality = quality, canUse = canUse, level = level, minBid = minBid, minIncrement = minIncrement, buyoutPrice = buyoutPrice,
							bidAmount = bidAmount, highBidder = highBidder, owner = owner, duration = duration, itemLink = itemLink, page = currentPage, pageIndex = i }
		if currentJob.onReadDatum then
			local keepDatum = currentJob.onReadDatum(scanDatum)
			if keepDatum then tinsert(scanData, scanDatum) else totalbought = totalbought + 1 end
		else
			tinsert(scanData, scanDatum)
		end
	end
	if sellorbuy == 1 then
		SAHSellProcessScanResults(scanData, currentAuctionItem.name)
		SAH_SelectSAHEntry()
		SAH_UpdateRecommendation()
	elseif sellorbuy == 2 then
		SAHBuyProcessScanResults(scanData)
		SAH_Buy_ScrollbarUpdate()
	end
	if processDataOnly then return end

	local numAucPages = 0
	while totalAuctions > 0 do totalAuctions = totalAuctions - 50; numAucPages = numAucPages + 1; end
	if sellorbuy == 2 and SAH_OrderedCount and SAH_OrderedCount > 0 then
		SAH_SetBuyMessage("Scanning: page "..currentPage.." / "..numAucPages.." .. Stack "..SAH_PurchasedCount.."/"..SAH_OrderedCount.." .. Item "..SAH_PurchasedNumber.."/"..SAH_OrderedNumber)
	else
		if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index then
			SAH_SetSellMessage("Scanning auctions: page "..currentPage.." of "..numAucPages.." ...")
		else
			SAH_SetBuyMessage("Scanning auctions: page "..currentPage.." of "..numAucPages.." ...")
		end
	end
	if SAH_ItemsToPurchasePages and not SAH_ItemsToPurchasePages[1] then
		SAH_Scan_Complete()
		totalbought = 0
	elseif currentPage < numAucPages then
		state = 1
	else
		SAH_Scan_Complete()
		totalbought = 0
	end
	SAH_timeOfLastPageScan = GetTime() + 15
end

--Sell Functions
function SAH_Sell_AuctionFrameAuctions_OnShow()
	SAH.orig.AuctionFrameAuctions_OnShow()
	SAH_Sell_AuctionsRadioButton_OnClick(SAH_AUCTION_DURATION)
end
function SAH_Sell_AuctionsRadioButton_OnClick(index,nosave)
	if not nosave then
		if index == 1 then
			SAH_AUCTION_DURATION = 1
		elseif index == 2 then
			SAH_AUCTION_DURATION = 2
		elseif index == 3 then
			SAH_AUCTION_DURATION = 3
		end
	end
	return SAH.orig.AuctionsRadioButton_OnClick(index)
end
function SAH_AuctionFrameAuctions_Update()
	SAH.orig.AuctionFrameAuctions_Update()
	if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index and AuctionFrame:IsShown() then SAH_HideElems(SAH.tabs.sell.hiddenElements) end
end
function SAH_AuctionsCreateAuctionButton_OnClick()
	if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.sell.index and AuctionFrame:IsShown() then postedItem = { name = currentAuctionItem.name, price = MoneyInputFrame_GetCopper(BuyoutPrice), } end
	local auctionTime = 2
	if AuctionsMediumAuctionButton:GetChecked() then auctionTime = 3 elseif AuctionsLongAuctionButton:GetChecked() then auctionTime = 4 end
	SAHSellEntries[currentAuctionItem.name].sold = { stackSize = currentAuctionItem.stackSize, count = 1, buyoutPrice = MoneyInputFrame_GetCopper(BuyoutPrice), itemPrice = SAH_Round(MoneyInputFrame_GetCopper(BuyoutPrice)/currentAuctionItem.stackSize), numYours = 1, maxTimeLeft = auctionTime, }
	for i=1,getn(SAHSellEntries[currentAuctionItem.name]) do
		if SAHSellEntries[currentAuctionItem.name][i].stackSize == currentAuctionItem.stackSize and SAHSellEntries[currentAuctionItem.name][i].buyoutPrice == MoneyInputFrame_GetCopper(BuyoutPrice) then
			SAHSellEntries[currentAuctionItem.name][i] = { stackSize = currentAuctionItem.stackSize, count = SAHSellEntries[currentAuctionItem.name][i].count + 1, buyoutPrice = MoneyInputFrame_GetCopper(BuyoutPrice), itemPrice = SAH_Round(MoneyInputFrame_GetCopper(BuyoutPrice)/currentAuctionItem.stackSize), numYours = SAHSellEntries[currentAuctionItem.name][i].numYours + 1, maxTimeLeft = auctionTime, }
			SAHSellRepeatBox:ClearFocus()
			if sellstate == 0 and tonumber(SAHSellRepeatBox:GetText()) > 1 then
				sellstate = 1
				SAH_timeOfLastUpdate = GetTime() + .5
				SellRepeat = { currentAuctionItem.name,currentAuctionItem.stackSize,tonumber(SAHSellRepeatBox:GetText()) }
				numSellRepeat = 1
			end
			SAH.orig.AuctionsCreateAuctionButton_OnClick()
			return
		end
	end
	table.insert(SAHSellEntries[currentAuctionItem.name],1,{ stackSize = currentAuctionItem.stackSize, count = 1, buyoutPrice = MoneyInputFrame_GetCopper(BuyoutPrice), itemPrice = SAH_Round(MoneyInputFrame_GetCopper(BuyoutPrice)/currentAuctionItem.stackSize), numYours = 1, maxTimeLeft = auctionTime, })
	SAHSellRepeatBox:ClearFocus()
	if sellstate == 0 and tonumber(SAHSellRepeatBox:GetText()) > 1 then
		sellstate = 1
		SAH_timeOfLastUpdate = GetTime() + .5
		SellRepeat = { currentAuctionItem.name,currentAuctionItem.stackSize,tonumber(SAHSellRepeatBox:GetText()) }
		numSellRepeat = 1
	end
	SAH.orig.AuctionsCreateAuctionButton_OnClick()
end
function SAH_AuctionSellRepeatSetup()
	SellRepeatBagPositions = {}
	for bag=0,NUM_BAG_FRAMES do
		for slot=1,GetContainerNumSlots(bag) do
			local _,itemCount = GetContainerItemInfo(bag, slot)
			if itemCount then
				local itemLink = GetContainerItemLink(bag,slot)
				local _,_,itemParse = strfind(itemLink, "(%d+):")
				local queryName = GetItemInfo(itemParse)
				if queryName and queryName ~= "" and queryName == SellRepeat[1] and itemCount == SellRepeat[2] then
					SellRepeat[3] = SellRepeat[3] - 1
					if SellRepeat[3] == 0 then return end
					table.insert(SellRepeatBagPositions,{bag,slot})
				end
			end
		end
	end
end
function SAH_AuctionSellRepeatAuctionPost()
	if SellRepeatBagPositions[1] and GetContainerItemLink(SellRepeatBagPositions[1][1],SellRepeatBagPositions[1][2]) then
		ClearCursor()
		PickupContainerItem(SellRepeatBagPositions[1][1],SellRepeatBagPositions[1][2])
		ClickAuctionSellItemButton()
		ClearCursor()
		for i=1,getn(SAHSellEntries[currentAuctionItem.name]) do
			if SAHSellEntries[currentAuctionItem.name][i].numYours > 0 and SAHSellEntries[currentAuctionItem.name][i].stackSize == currentAuctionItem.stackSize and SAHSellEntries[currentAuctionItem.name][i].buyoutPrice == MoneyInputFrame_GetCopper(BuyoutPrice) then
				SAHSellEntries[currentAuctionItem.name][i] = { stackSize = currentAuctionItem.stackSize, count = SAHSellEntries[currentAuctionItem.name][i].count + 1, buyoutPrice = MoneyInputFrame_GetCopper(BuyoutPrice), itemPrice = SAH_Round(MoneyInputFrame_GetCopper(BuyoutPrice)/currentAuctionItem.stackSize), numYours = SAHSellEntries[currentAuctionItem.name][i].numYours + 1, maxTimeLeft = SAHSellEntries[currentAuctionItem.name][i].maxTimeLeft, }
				break
			end
		end
		SAH.orig.AuctionsCreateAuctionButton_OnClick()
		table.remove(SellRepeatBagPositions,1)
		sellstate = 3
		SAH_timeOfLastUpdate = GetTime() + .5
		numSellRepeat = numSellRepeat + 1
	else
		sellstate = 0
		if numSellRepeat > 1 then DEFAULT_CHAT_FRAME:AddMessage("SAH: Posted "..(numSellRepeat).." items", 1, 1, 0.5) numSellRepeat = 0 end
	end
end
function SAH_AuctionSellItemButton_OnEvent()
	SAH.orig.AuctionSellItemButton_OnEvent()
	SAH_OnNewAuctionUpdate()
end
function SAH_CreateSellOrder()
	local order = {}
	SAH_ItemsToPurchasePages = {}
	order[currentAuctionItem.name.."_"..SAHSellEntries[currentAuctionItem.name].selected.stackSize.."_"..SAHSellEntries[currentAuctionItem.name].selected.buyoutPrice] = 1
	table.insert(SAH_ItemsToPurchasePages,SAHSellEntries[currentAuctionItem.name].selected.page)
	return order
end
function SAHSellBuySelectedButton_OnClick()
	sellorbuy = 1
	local order = SAH_CreateSellOrder()
	SAHSellRefreshButton:Disable()
	SAH_OrderedCount = 1
	SAH_PurchasedCount = 0
	searchQuery = SAH_Scan_CreateQuery{
		name = currentAuctionItem.name,
	}
	SAH_Scan_Start{
		query = searchQuery,
		onReadDatum = function(datum)
			if datum.name and datum.count and datum.buyoutPrice then
				local key = datum.name.."_"..datum.count.."_"..datum.buyoutPrice
				if order[key] then
					if GetMoney() >= datum.buyoutPrice then
						PlaceAuctionBid("list", datum.pageIndex, datum.buyoutPrice)
						SAH_PurchasedCount = 1
						table.insert(SAH_PurchasedItems,datum)
					end
					order[key] = nil
					return false
				else
					return true
				end
			end
		end,
		onComplete = function(data)
			SAHSellRefreshButton:Enable()
			SAH_SetSellMessage("Scan Completed: Bought Stacks "..SAH_PurchasedCount.." / 1")
			SAH_OrderedCount = 0
		end,
		onAbort = function()
			SAHSellRefreshButton:Enable()
			SAH_SetSellMessage("Scan Completed: Bought Stacks "..SAH_PurchasedCount.." / 1")
			SAH_OrderedCount = 0
		end
	}
end
function SAH_SetSellMessage(msg)
	SAH_HideElems(SAH.tabs.sell.recommendationElements)
	SAHSellMessage:SetText(msg)
	SAHSellMessage:Show()
end
function SAH_SelectSAHEntry()
	if currentAuctionItem and SAHSellEntries[currentAuctionItem.name] and not SAHSellEntries[currentAuctionItem.name].selected then
		local bestPrice	= {} -- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
		local absoluteBest -- the overall cheapest auction
		for _,SAHEntry in ipairs(SAHSellEntries[currentAuctionItem.name]) do
			if not bestPrice[SAHEntry.stackSize] or bestPrice[SAHEntry.stackSize].itemPrice >= SAHEntry.itemPrice then bestPrice[SAHEntry.stackSize] = SAHEntry end
			if not absoluteBest or absoluteBest.itemPrice > SAHEntry.itemPrice then absoluteBest = SAHEntry end	
		end
		SAHSellEntries[currentAuctionItem.name].selected = absoluteBest
		if bestPrice[currentAuctionItem.stackSize] then
			SAHSellEntries[currentAuctionItem.name].selected = bestPrice[currentAuctionItem.stackSize]
			bestPriceOurStackSize = bestPrice[currentAuctionItem.stackSize]
		end
	end
end
function SAH_UpdateRecommendation()
	SAHRecommendStaleText:Hide()
	if not currentAuctionItem then
		SAHSellRefreshButton:Disable()
		if postedItem then	
			SAHSellMessage:Hide()
			SAHRecommendText:SetText("Auction Created for "..postedItem.name)
			MoneyFrame_Update("SAHRecommendPerStackPrice", postedItem.price)
			SAHRecommendPerStackPrice:Show()
			SAHRecommendPerItemPrice:Hide()
			SAHRecommendPerItemText:Hide()
			SAHRecommendBasisText:Hide()
			postedItem = nil
		else	
			SAH_SetSellMessage("Drag an item to the Auction Item area\n\nto see recommended pricing information")
		end
	else
		SAHSellRefreshButton:Enable()	
		if SAHSellEntries[currentAuctionItem.name] then
			local newBuyoutPrice,newStartPrice
			SAH_ShowElems(SAH.tabs.sell.recommendationElements)
			if SAHSellEntries[currentAuctionItem.name].selected then
				if not SAHSellEntries[currentAuctionItem.name].created or GetTime() - SAHSellEntries[currentAuctionItem.name].created > 1800 then
					SAHRecommendStaleText:SetText("STALE DATA") -- data older than half an hour marked as stale
					SAHRecommendStaleText:Show()
				end
				newBuyoutPrice = SAHSellEntries[currentAuctionItem.name].selected.itemPrice * currentAuctionItem.stackSize
				if SAHSellEntries[currentAuctionItem.name].selected.numYours < SAHSellEntries[currentAuctionItem.name].selected.count then newBuyoutPrice = math.max(0, newBuyoutPrice - 1) end
				if SAHSellEntries[currentAuctionItem.name][1] and SAHSellEntries[currentAuctionItem.name].selected.stackSize == SAHSellEntries[currentAuctionItem.name][1].stackSize and SAHSellEntries[currentAuctionItem.name].selected.buyoutPrice == SAHSellEntries[currentAuctionItem.name][1].buyoutPrice then
					SAHRecommendBasisText:SetText("(based on cheapest)")
				elseif bestPriceOurStackSize and SAHSellEntries[currentAuctionItem.name].selected.stackSize == bestPriceOurStackSize.stackSize and SAHSellEntries[currentAuctionItem.name].selected.buyoutPrice == bestPriceOurStackSize.buyoutPrice then
					SAHRecommendBasisText:SetText("(based on cheapest stack of the same size)")
				else
					SAHRecommendBasisText:SetText("(based on auction selected below)")
				end
			elseif SAHSellEntries[currentAuctionItem.name].sold then
				newBuyoutPrice = SAHSellEntries[currentAuctionItem.name].sold.itemPrice
			else
				newBuyoutPrice = math.max(0, CalculateAuctionDeposit(1440) - 1) * 3
			end
			newStartPrice = newBuyoutPrice * 0.95
			SAHSellMessage:Hide()	
			SAHRecommendText:SetText("Recommended Buyout Price")
			SAHRecommendPerStackText:SetText("for your stack of "..currentAuctionItem.stackSize)
			if currentAuctionItem.texture then
				SAHRecommendItemTex:SetNormalTexture(currentAuctionItem.texture)
				if currentAuctionItem.stackSize > 1 then
					SAHRecommendItemTexCount:SetText(currentAuctionItem.stackSize)
					SAHRecommendItemTexCount:Show()
				else
					SAHRecommendItemTexCount:Hide()
				end
			else
				SAHRecommendItemTex:Hide()
			end
			MoneyFrame_Update("SAHRecommendPerItemPrice",  SAH_Round(newBuyoutPrice / currentAuctionItem.stackSize))
			MoneyFrame_Update("SAHRecommendPerStackPrice", SAH_Round(newBuyoutPrice))
			MoneyInputFrame_SetCopper(BuyoutPrice, SAH_Round(newBuyoutPrice))
			MoneyInputFrame_SetCopper(StartPrice, SAH_Round(newStartPrice))
		else 
			SAH_HideElems(SAH.tabs.sell.shownElements)
		end
	end
	SAH_ScrollbarUpdate()
end
function SAH_OnNewAuctionUpdate()
	if PanelTemplates_GetSelectedTab(AuctionFrame) ~= SAH.tabs.sell.index then return end
	if state ~= 0 then SAH_Scan_Abort() end
	local auctionItemName, auctionItemTexture, auctionItemStackSize = GetAuctionSellItemInfo()
	SAH_Scan_ClearTooltip()
	SAHScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	SAHScanTooltip:SetAuctionSellItem()
	SAHScanTooltip:Show()
	local tooltip = SAH_Scan_ExtractTooltip()
	currentAuctionItem = auctionItemName and {
		name = auctionItemName,
		texture = auctionItemTexture,
		stackSize = SAH_Scan_ItemCharges(tooltip) or auctionItemStackSize,
	}
	if currentAuctionItem then
		if not SAHSellEntries[currentAuctionItem.name] then
			SAH_RefreshEntries()
		elseif SAHSellEntries[currentAuctionItem.name].sold then
			SAHSellEntries[currentAuctionItem.name].selected = SAHSellEntries[currentAuctionItem.name].sold
			bestPriceOurStackSize = SAHSellEntries[currentAuctionItem.name].sold
			SAH_UpdateRecommendation()
			SAH_Sell_AuctionsRadioButton_OnClick(SAHSellEntries[currentAuctionItem.name].sold.maxTimeLeft - 1, true)
			return
		end
	end
	SAHSellBuySelectedButton:Disable()
	SAH_Sell_AuctionsRadioButton_OnClick(SAH_AUCTION_DURATION)
	SAH_SelectSAHEntry()
	SAH_UpdateRecommendation()
end
function SAH_RefreshEntries()
	sellorbuy = 1
	SAH_OrderedCount = 0
	if currentAuctionItem then
		local _,_,_,_,_,sType = GetItemInfo(currentAuctionItem.name)
		local currentAuctionClass = SAH_GetItemClass(sType)
		if SAHSellEntries[currentAuctionItem.name] then
			SAHSellEntries[currentAuctionItem.name] = { created=GetTime(), sold=SAHSellEntries[currentAuctionItem.name].sold }
		else
			SAHSellEntries[currentAuctionItem.name] = { created=GetTime() }
		end
		SAH_Scan_Start{
			query = SAH_Scan_CreateQuery{
				name = currentAuctionItem.name,
				classIndex = currentAuctionClass,
				subclassIndex = nil
			},
			onComplete = function(data)
				SAH_UpdateRecommendation()
				if not SAHSellEntries[currentAuctionItem.name][1] then
					SAH_SetSellMessage("No auctions were found for \n\n"..currentAuctionItem.name)
					SAHSellEntries[currentAuctionItem.name] = { sold=SAHSellEntries[currentAuctionItem.name].sold }
				end
			end,
			onAbort = function()
				SAH_UpdateRecommendation()
				if not SAHSellEntries[currentAuctionItem.name][1] then
					SAH_SetSellMessage("No auctions were found for \n\n"..currentAuctionItem.name)
					SAHSellEntries[currentAuctionItem.name] = { sold=SAHSellEntries[currentAuctionItem.name].sold }
				end
			end
		}
	end
end
function SAH_ScrollbarUpdate()
	local numrows
	if not currentAuctionItem or not SAHSellEntries[currentAuctionItem.name] then numrows = 0 else numrows = getn(SAHSellEntries[currentAuctionItem.name]) end
	FauxScrollFrame_Update(SAHScrollFrame, numrows, 12, 16)
	for line = 1,12 do
		local dataOffset = line + FauxScrollFrame_GetOffset(SAHScrollFrame)	
		local lineEntry = getglobal("SAHSellEntry"..line)
		if numrows <= 12 then lineEntry:SetWidth(603) else lineEntry:SetWidth(585) end
		lineEntry:SetID(dataOffset)
		if currentAuctionItem and dataOffset <= numrows and SAHSellEntries[currentAuctionItem.name] then
			local entry = SAHSellEntries[currentAuctionItem.name][dataOffset]
			if SAHSellEntries[currentAuctionItem.name].selected and entry.itemPrice == SAHSellEntries[currentAuctionItem.name].selected.itemPrice and entry.stackSize == SAHSellEntries[currentAuctionItem.name].selected.stackSize then
				lineEntry:LockHighlight()
			else
				lineEntry:UnlockHighlight()
			end
			local lineEntry_stacks	= getglobal("SAHSellEntry"..line.."_Stacks")
			local lineEntry_time	= getglobal("SAHSellEntry"..line.."_Time")
			if entry.maxTimeLeft == 1 then
				lineEntry_time:SetText("Short")
			elseif entry.maxTimeLeft == 2 then
				lineEntry_time:SetText("Medium")			
			elseif entry.maxTimeLeft == 3 then
				lineEntry_time:SetText("Long")
			elseif entry.maxTimeLeft == 4 then
				lineEntry_time:SetText("Very Long")
			end
			if entry.stackSize == currentAuctionItem.stackSize then
				lineEntry_stacks:SetTextColor(0.2, 0.9, 0.2)
			else
				lineEntry_stacks:SetTextColor(1.0, 1.0, 1.0)
			end
			local own
			if entry.numYours == 0 then
				own = ""
			elseif
				entry.numYours == entry.count then
				own = "(yours)"
			else
				own = "(yours: "..entry.numYours..")"
			end
			local tx = string.format("%i %s of %i %s", entry.count, SAH_PluralizeIf("stack", entry.count), entry.stackSize, own)
			lineEntry_stacks:SetText(tx)
			MoneyFrame_Update("SAHSellEntry"..line.."_UnitPrice", SAH_Round(entry.buyoutPrice/entry.stackSize))
			MoneyFrame_Update("SAHSellEntry"..line.."_TotalPrice", SAH_Round(entry.buyoutPrice))
			lineEntry:Show()
		else
			lineEntry:Hide()
		end
	end
end
function SAHSellEntry_OnClick()
	local entryIndex = this:GetID()
	SAHSellEntries[currentAuctionItem.name].selected = SAHSellEntries[currentAuctionItem.name][entryIndex]
	SAH_UpdateRecommendation()
	PlaySound("igMainMenuOptionCheckBoxOn")
	if SAHSellEntries[currentAuctionItem.name].selected.page and SAHSellEntries[currentAuctionItem.name].selected.count > SAHSellEntries[currentAuctionItem.name].selected.numYours then SAHSellBuySelectedButton:Enable() else SAHSellBuySelectedButton:Disable() end
end
function SAHSellRefreshButton_OnClick()
	if state ~= 0 then SAH_Scan_Abort() end
	SAH_RefreshEntries()
	SAH_SelectSAHEntry()
	SAH_UpdateRecommendation()
end
function SAHMoneyFrame_OnLoad()
	this.small = 1
	SmallMoneyFrame_OnLoad()
	MoneyFrame_SetType("AUCTION")
end
function SAHSellProcessScanResults(rawData, auctionItemName)
	if SAH_OrderedCount == 0 then
		local condData = {}
		SAHSellEntries[auctionItemName] = { created=GetTime(), sold=SAHSellEntries[auctionItemName].sold }
		for _,rawDatum in ipairs(rawData) do
			if auctionItemName == rawDatum.name and rawDatum.buyoutPrice > 0 then
				local key = "_"..rawDatum.count.."_"..rawDatum.buyoutPrice
				if not condData[key] then
					condData[key] = {
						stackSize 	= rawDatum.count,
						buyoutPrice	= rawDatum.buyoutPrice,
						itemPrice	= rawDatum.buyoutPrice / rawDatum.count,
						maxTimeLeft	= rawDatum.duration,
						count		= 1,
						numYours	= rawDatum.owner == UnitName("player") and 1 or 0,
						page 		= rawDatum.page,
				}
				else
					condData[key].maxTimeLeft = math.max(condData[key].maxTimeLeft, rawDatum.duration)
					condData[key].count = condData[key].count + 1
					if rawDatum.owner == UnitName("player") then
						condData[key].numYours = condData[key].numYours + 1
					end
				end
			end
		end
		local n = 1
		for _,condDatum in pairs(condData) do
			SAHSellEntries[auctionItemName][n] = condDatum
			n = n + 1
		end
	else
		SAHBuyDeleteEntries(SAH_PurchasedItems)
	end
	table.sort(SAHSellEntries[auctionItemName], function(a,b) return a.itemPrice < b.itemPrice end)
end
function SAHSellStopScanningButton_OnClick()
	SAH_Scan_Abort()
end
function SAH_GetItemClass(itemType)
	local itemClasses = { GetAuctionItemClasses() }
	if itemClasses and getn(itemClasses) > 0 then
		for x,itemClass in pairs(itemClasses) do
			if itemClass == itemType then return x end
		end
	end
end

--Buy Functions
function SAH_AuctionFrameBids_Update()
	SAH.orig.AuctionFrameBids_Update()
	if PanelTemplates_GetSelectedTab(AuctionFrame) == SAH.tabs.buy.index and AuctionFrame:IsShown() then SAH_HideElems(SAH.tabs.buy.hiddenElements) end
end
function SAHBuySearchButton_OnClick()
	sellorbuy = 2
	SAHBuyBuySelectedButton:Disable()
	SAH_OrderedCount = 0
	SAH_PurchasedCount = 0
	SAH_PurchasedNumber = 0
	entries = nil
	selectedEntries = {}
	SAH_Buy_ScrollbarUpdate()
	searchQuery = SAH_Scan_CreateQuery{
		name = SAHBuySearchBox:GetText(),
		exactmatch = SAH_ExactMatch,
		isUsable = SAH_IsUsable,
	}
	SAH_Scan_Start{
		query = searchQuery,
		onComplete = function(data)
			SAH_SetBuyMessage("Scan Completed")
			SAH_Buy_StatisticsUpdate()
		end,
		onAbort = function()
			SAH_SetBuyMessage("Scan Aborted")
			SAH_Buy_StatisticsUpdate()
		end
	}
	local entryName = string.lower(SAHBuySearchBox:GetText())
	local lfs,lfe,wordString = 1
	while true do
		lfs,lfe,wordString = string.find(entryName,"([%a%p]+)",lfs)
		if not wordString then break end
		if not DoNotCapitalize[wordString] or lfs == 1 then
			entryName = string.sub(entryName,1,lfs-1)..string.upper(string.sub(entryName,lfs,lfs))..string.sub(entryName,lfs+1,lfe)..string.sub(entryName,lfe+1)
		end
		lfs = lfe+1
	end
	if string.len(entryName) > 20 then entryName = string.sub(entryName,1,20) end
	SAH_QuickBuyUpdateButtons(entryName)
end
function SAH_CreateBuyOrder()
	local order = {}
	local pages = {}
	SAH_ItemsToPurchasePages = {}
	for entry,_ in pairs(selectedEntries) do
		local key = entry.name.."_"..entry.stackSize.."_"..entry.buyoutPrice
		if order[key] then order[key] = order[key] + 1 else order[key] = 1 end
		pages[entry.page] = true
	end
	for page,_ in pages do
		table.insert(SAH_ItemsToPurchasePages,page)
	end
	table.sort(SAH_ItemsToPurchasePages, function(a,b) return a > b end)
	return order
end
function SAHBuyBuySelectedButton_OnClick()
	sellorbuy = 2
	SAHBuySearchButton:Disable()
	SAHBuyBuySelectedButton:Disable()
	local order = SAH_CreateBuyOrder(selectedEntries)
	SAH_OrderedCount = SAH_SetSize(selectedEntries)
	SAH_PurchasedCount = 0
	SAH_PurchasedNumber = 0
	selectedEntries = {}
	SAH_Buy_ScrollbarUpdate()					
	SAH_Scan_Start{
		query = searchQuery,
		onReadDatum = function(datum)
			if datum.name and datum.count and datum.buyoutPrice then
				local key = datum.name.."_"..datum.count.."_"..datum.buyoutPrice
				if order[key] then
					if GetMoney() >= datum.buyoutPrice then
						PlaceAuctionBid("list", datum.pageIndex, datum.buyoutPrice)
						SAH_PurchasedCount = SAH_PurchasedCount + 1
						SAH_PurchasedNumber = SAH_PurchasedNumber + datum.count
						table.insert(SAH_PurchasedItems,datum)
					end
					if order[key] > 1 then order[key] = order[key] - 1 else order[key] = nil end
					return false
				else
					return true
				end
			end
		end,
		onComplete = function(data)
			SAHBuySearchButton:Enable()
			SAH_SetBuyMessage("Scan Completed: Bought Stacks "..SAH_PurchasedCount.."/"..SAH_OrderedCount.." .. Items "..SAH_PurchasedNumber.."/"..SAH_OrderedNumber)
			selectedEntries = {}
			SAH_OrderedCount = 0
		end,
		onAbort = function()
			SAHBuySearchButton:Enable()
			SAH_SetBuyMessage("Scan Aborted: Bought Stacks "..SAH_PurchasedCount.."/"..SAH_OrderedCount.." .. Items "..SAH_PurchasedNumber.."/"..SAH_OrderedNumber)
			selectedEntries = {}
			SAH_OrderedCount = 0
		end
	}
end
function SAH_SetBuyMessage(msg)
	SAHBuyMessage:SetText(msg)
	SAHBuyMessage:Show()
end
function SAHBuyEntry_OnClick(id)
	if IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
		ChatFrameEditBox:Insert(entries[id]["itemLink"])
	elseif selectedEntries[entries[id]] ~= nil then
		selectedEntries[entries[id]] = nil
		lastSelectedEntry = nil
	else
		if IsShiftKeyDown() and lastSelectedEntry and lastSelectedEntry ~= id then
			if lastSelectedEntry < id then
				for i=lastSelectedEntry, id do selectedEntries[entries[i]] = i end
			else
				for i=id, lastSelectedEntry do selectedEntries[entries[i]] = i end
			end
		else
			selectedEntries[entries[id]] = id
		end
		lastSelectedEntry = id
	end
	SAH_Buy_StatisticsUpdate()
	SAH_Buy_ScrollbarUpdate()
	PlaySound("igMainMenuOptionCheckBoxOn")
end
function SAHBuyEntry_OnEnter(id)
	local found,_,itemString = string.find(entries[id].itemLink, "^|%x+|H(.+)|h%[.+%]")
	if found then
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(itemString)
		if RedSearch then
			RedSearch.TooltipHook(entries[id].itemLink,entries[id].stackSize)
		elseif EnhTooltip then
			EnhTooltip.TooltipCall(GameTooltip, entries[id].name, entries[id].itemLink, entries[id].quality, entries[id].stackSize)
		end
		GameTooltip:Show()
	end
end
function SAHBuyProcessScanResults(rawData)
	if SAH_OrderedCount == 0 then 
		entries = {}
		for _,rawDatum in ipairs(rawData) do
			if rawDatum.buyoutPrice > 0 and rawDatum.owner ~= UnitName("player") and (not currentJob.query.exactmatch or string.lower(currentJob.query.name) == string.lower(rawDatum.name)) then
				tinsert(entries, {
					name		= rawDatum.name,
					stackSize	= rawDatum.count,
					buyoutPrice	= rawDatum.buyoutPrice,
					itemPrice	= rawDatum.buyoutPrice / rawDatum.count,
					quality		= rawDatum.quality,
					itemLink	= rawDatum.itemLink,
					page 		= rawDatum.page,
				})
			end
		end
	else
		SAHBuyDeleteEntries(SAH_PurchasedItems)
	end
	table.sort(entries, function(a,b) return a.itemPrice < b.itemPrice end)
	selectedEntries = {}
	SAH_Buy_StatisticsUpdate()
end
function SAHBuyDeleteEntries(dataTable,Scanning)
	for i=1, getn(dataTable) do
		if entries then
			for j=1, getn(entries) do
				if dataTable[i] and dataTable[i].name == entries[j].name and dataTable[i].count == entries[j].stackSize and dataTable[i].buyoutPrice == entries[j].buyoutPrice then
					table.remove(entries, j)
					break
				end
			end
		end
		if currentAuctionItem then
			for j=1, getn(SAHSellEntries[currentAuctionItem.name]) do
				if dataTable[i] and dataTable[i].name == currentAuctionItem.name and dataTable[i].count == SAHSellEntries[currentAuctionItem.name][j].stackSize and dataTable[i].buyoutPrice == SAHSellEntries[currentAuctionItem.name][j].buyoutPrice then
					if SAHSellEntries[currentAuctionItem.name][j].count == 1 then
						table.remove(SAHSellEntries[currentAuctionItem.name], j)
						SAHSellBuySelectedButton:Disable()
					else
						SAHSellEntries[currentAuctionItem.name][j].count = SAHSellEntries[currentAuctionItem.name][j].count - 1
					end
					break
				end
			end
		end
		if Scanning and scanData then
			for j=1, getn(scanData) do
				if dataTable[i] and dataTable[i].name == scanData[j].name and dataTable[i].count == scanData[j].count and dataTable[i].buyoutPrice == scanData[j].buyoutPrice then
					table.remove(scanData, j)
					break
				end
			end
		end
	end
end
function SAH_Buy_StatisticsUpdate()
	local total = 0
	local number = 0
	for entry,_ in selectedEntries do
		total = total + entry.buyoutPrice
		number = number + entry.stackSize
		SAH_OrderedNumber = number
	end	
	MoneyFrame_Update("SAHBuyTotal", SAH_Round(total))
	SAHNumberTotalText:SetText("Total to buy:  "..number)
	if SAH_SetSize(selectedEntries) > 0 and GetMoney() >= total then
		SAHBuyBuySelectedButton:Enable()
	else
		SAHBuyBuySelectedButton:Disable()
	end
end
function SAH_Buy_ScrollbarUpdate()
	local numrows
	if not entries then numrows = 0 else numrows = getn(entries) end
	FauxScrollFrame_Update(SAHBuyScrollFrame, numrows, 19, 16)
	for line = 1,19 do
		local dataOffset = line + FauxScrollFrame_GetOffset(SAHBuyScrollFrame)
		local lineEntry = getglobal("SAHBuyEntry"..line)
		if numrows <= 19 then lineEntry:SetWidth(800) else lineEntry:SetWidth(782) end
		lineEntry:SetID(dataOffset)
		if dataOffset <= numrows and entries[dataOffset] then
			local entry = entries[dataOffset]
			local lineEntry_name = getglobal("SAHBuyEntry"..line.."_Name")
			local lineEntry_stackSize = getglobal("SAHBuyEntry"..line.."_StackSize")
			local color = "ffffffff"
			if SAH_QualityColor(entry.quality) then color = SAH_QualityColor(entry.quality) end
			lineEntry_name:SetText("\124c" .. color ..  entry.name .. "\124r")

			if selectedEntries[entry] ~= nil then lineEntry:LockHighlight() else lineEntry:UnlockHighlight() end
			lineEntry_stackSize:SetText(entry.stackSize)
			
			MoneyFrame_Update("SAHBuyEntry"..line.."_UnitPrice", SAH_Round(entry.buyoutPrice/entry.stackSize))
			MoneyFrame_Update("SAHBuyEntry"..line.."_TotalPrice", SAH_Round(entry.buyoutPrice))
			lineEntry:Show()
		else
			lineEntry:Hide()
		end
	end
end
function SAHBuyStopScanningButton_OnClick()
	SAH_Scan_Abort()
end

function SAH_QuickBuyButtonPressed(id)
	SAHBuySearchBox:SetText(getglobal("SAHQuickBuyButton"..id):GetText())
	SAHBuySearchButton_OnClick()
end
function SAH_QuickBuyUpdateButtons(name)
	local numPriority = 0
	local NameWasPriority
	local counter = 1
	while true do
		if not name or not SAHSearchHistory[counter] or counter == 21 then break end
		if SAHSearchHistory[counter][2] then numPriority = numPriority+1 end
		if name == SAHSearchHistory[counter][1] then if SAHSearchHistory[counter][2] then NameWasPriority = true end table.remove(SAHSearchHistory,counter) else counter = counter+1 end
	end
	if name then
		if NameWasPriority then
			table.insert(SAHSearchHistory,1,{name,true})
		else
			table.insert(SAHSearchHistory,1+numPriority,{name,nil})
		end
	end
	for i=1, 17 do
		if SAHSearchHistory[i] then
			if SAHSearchHistory[i][2] then
				getglobal("SAHQuickBuyCheckButton"..i):SetChecked(true)
				getglobal("SAHQuickBuyButton"..i.."TextureGold"):Show()
			else
				getglobal("SAHQuickBuyCheckButton"..i):SetChecked(false)
				getglobal("SAHQuickBuyButton"..i.."TextureGold"):Hide()
			end
			getglobal("SAHQuickBuyButton"..i):SetText(SAHSearchHistory[i][1])
			getglobal("SAHQuickBuyButton"..i):Show()
			getglobal("SAHQuickBuyCheckButton"..i):Show()
		else
			getglobal("SAHQuickBuyButton"..i):SetText("")
			getglobal("SAHQuickBuyButton"..i):Hide()
			getglobal("SAHQuickBuyCheckButton"..i):Hide()
		end
	end
	if getn(SAHSearchHistory) > 17 then table.remove(SAHSearchHistory,18) end	
end
function SAH_QuickBuyPriorityCheckButtonPressed(id,priority)
	SAHSearchHistory[id][2] = priority
	SAH_QuickBuyUpdateButtons(SAHSearchHistory[id][1])
end