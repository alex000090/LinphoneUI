import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import Nemo.Configuration 1.0

Page {
    id: mainPage
    
    property bool isRegistered: false
    property var callHistory: []
    property string debugInfo: "Initializing..."
    property string callState: "none" // none, outgoing, incoming, active
    property string currentCallNumber: ""
    property string callDuration: ""
    property var callStartTime: null
    property string lastStatusCheck: "Never"
    property bool isMicON: true
    property bool isSpeaker: false
    
    // Вычисляемые свойства для автоматического обновления UI
    property string callStatusText: {
        if (callState === "incoming") return "Incoming: " + currentCallNumber + " (" + callDuration + ")"
        if (callState === "outgoing") return "Calling: " + currentCallNumber + " (" + callDuration + ")"
        if (callState === "active") return "Active: " + currentCallNumber + " (" + callDuration + ")"
        return "No calls"
    }
    
    property string endCallButtonText: callState === "incoming" ? "Answer Call" : "End Call"
    
    DBusInterface {
        id: linphoneService
        service: 'org.sailfishos.LinphoneUI'
        path: '/LinphoneUI'
        iface: 'org.sailfishos.LinphoneUI'
        
		/*
        signal call_state_changed(string state, string number)
        signal registration_state_changed(bool registered)
        
        // ПОДКЛЮЧИТЬ СИГНАЛЫ СРАЗУ ПРИ СОЗДАНИИ
        Component.onCompleted: {
            console.log("GUI: DBusInterface created, connecting signals...")
            call_state_changed.connect(handleCallStateChanged)
            registration_state_changed.connect(handleRegistrationStateChanged)
        }
		*/
    }
    
    ConfigurationGroup {
        id: appSettings
        path: "/apps/LinphoneUI"
        property string callHistory: "[]"
    }
    
    // Timer for automatic status checking
    Timer {
        id: statusCheckTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            //console.log("GUI: Auto-checking status...")
            autoCheckStatus()
        }
    }
	
	Timer {
        id: focusing_numberField
        interval: 100
        repeat: true
        running: true
        onTriggered: {
			numberField.forceActiveFocus()
        }
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        
        PullDownMenu {
            MenuItem {
                text: "Clear History"
                onClicked: clearCallHistory()
            }
        }
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: "Linphone"
            }
            
            // Registration status
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                
                Rectangle {
                    anchors.fill: parent
                    color: isRegistered ? "#4CAF50" : "#F44336"
                    opacity: 0.3
                }
                
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingSmall
                    
                    Label {
                        text: isRegistered ? "SIP REGISTERED" : "SIP NOT REGISTERED"
                        color: isRegistered ? Theme.primaryColor : Theme.errorColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    /*
                    BusyIndicator {
                        size: BusyIndicatorSize.Small
                        running: statusCheckTimer.running
                        visible: running
                    }
					*/
                }
            }
            
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: callStatusText
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
                visible: true
            }
            
            // Number input
            SectionHeader {
                text: "Dial Number"
            }
            
            TextField {
                id: numberField
                width: parent.width
                placeholderText: "Enter phone number"
                label: "Phone Number"
                inputMethodHints: Qt.ImhDialableCharactersOnly
                focus: true
                EnterKey.iconSource: "image://theme/icon-m-call"
                EnterKey.onClicked: {
                    if ( (callState === "none") && (text.length > 0) ) makeCall(text)
                    else if (callState === "incoming") answerCall()
                    else if (callState === "active") endCall()
                    else if (callState === "outgoing") endCall()
                }
                
            }
            
            // Dial pad
			/*
            Grid {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                columns: 3
                spacing: Theme.paddingSmall
                
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
                    
                    BackgroundItem {
                        width: (parent.width - 2*Theme.paddingSmall) / 3
                        height: Theme.itemSizeMedium
                        
                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: Theme.fontSizeExtraLarge
                            color: parent.pressed ? Theme.highlightColor : Theme.primaryColor
                        }
                        
                        onClicked: {
                            numberField.text = numberField.text + modelData
                        }
                    }
                }
            }
			*/
            
            // Call buttons
            Row {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingSmall
                
                Button {
                    width: 0.5*parent.width
                    text: isMicON ? "Mic: ON" : "Mic: OFF"
                    enabled: callState === "active"
                    onClicked: micChange()
                }

                Button {
                    width: 0.5*parent.width
                    text: isSpeaker ? "Out: Speaker" : "Out: Earpiece"
                    enabled: callState === "active"
                    onClicked: {
                        if (callState === "incoming") {
                            answerCall()
                        } else {
                            endCall()
                        }
                    }
                }
            
            }
        
            
            // Warning if not registered
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: "Cannot make calls - SIP not registered"
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                visible: !isRegistered
            }
            
            // Call history
            SectionHeader {
                text: "Call History"
                visible: callHistory.length > 0
            }
            
            Repeater {
                model: callHistory.slice(0, 5)
                
                ListItem {
                    id: historyItem
                    width: parent.width
                    contentHeight: Theme.itemSizeMedium
                    
                    menu: ContextMenu {
                        MenuItem {
                            text: "Call"
                            onClicked: makeCall(modelData.number)
                        }
                        MenuItem {
                            text: "Delete"
                            onClicked: removeFromHistory(index)
                        }
                    }
                    
                    Row {
                        width: parent.width - 2*Theme.horizontalPageMargin
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingMedium
                        
                        Image {
                            source: {
                                if (modelData.type === "outgoing") return "image://theme/icon-m-outgoing-call"
                                if (modelData.type === "incoming") return "image://theme/icon-m-incoming-call"
                                return "image://theme/icon-m-missed-call"
                            }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Column {
                            width: parent.width - Theme.itemSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                text: modelData.number
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: historyItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            }
                            
                            Label {
                                text: modelData.time
                                width: parent.width
                                font.pixelSize: Theme.fontSizeSmall
                                color: historyItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            }
                        }
                    }
                    
                    onClicked: makeCall(modelData.number)
                }
            }
            
            Label {
                text: "Call history is empty"
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryColor
                visible: callHistory.length === 0
            }
        }
    }
    
    function updateCallDuration() {
        //console.log("GUI: updateCallDuration called, callState:", callState, "callStartTime:", callStartTime)
        if (callStartTime && callState !== "none") {
            var now = new Date()
            var diff = Math.floor((now - callStartTime) / 1000)
            var minutes = Math.floor(diff / 60)
            var seconds = diff % 60
            callDuration = minutes + ":" + (seconds < 10 ? "0" : "") + seconds
            //console.log("GUI: Call duration updated to:", callDuration)
            
            // Принудительно обновляем UI после изменения callDuration
            //callStatusTextChanged()
        }
    }
    
    function updateStatusTime() {
        lastStatusCheck = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")
    }
    
    function autoCheckStatus() {
        //console.log("GUI: Auto-checking registration and call state...")
        // Check registration status

        linphoneService.call('is_registered', [], function(registeredResult) {
            //console.log("GUI: Auto-check registered:", registeredResult)
            isRegistered = registeredResult
            
            // Check current call state
            linphoneService.call('get_current_call_info', [], function(callInfo) {
                //console.log("GUI: Auto-check call info:", callInfo)

                // Update debug info
                debugInfo = "Auto: reg=" + registeredResult + " call=" + callInfo
                updateStatusTime()
				
				
                
                // If we think there's no call but daemon reports one, sync state
                //if (0 && callState === "none" && callInfo !== "No active call" && callInfo !== "Daemon not available") {
                if (callInfo !== "Daemon not available") {
					callInfoHandler(callInfo)
                }
            })
        })
    }
	
	function callInfoHandler(callInfo) {
		var status = callInfo.match(/\(([^)]+)\)$/)
		status = status ? status[1] : "none"
		//if (callState==="outgoing" && status==="active") callStartTime = new Date()
		if (callState!==status) {
			callStartTime = new Date()
			callState = status
		}
		
		var number = callInfo.match(/Call:\s*([^\s\(]+)/)
		number = number ? number[1] : "Unknown"
		
		if (status!=="none") {
			currentCallNumber = number
			updateCallDuration()
		}
		
		//console.log("GUI: callInfoHandler:", status, number)
	}
	
	function makeCallHandler(result) {
		console.log("GUI: make_call result:", result)
		if (result) {
			callState = "outgoing"
			numberField.text = ""
			callStartTime = new Date()
		}
	}

    function makeCall(number) {
        if ( (!isRegistered) || (callState !== "none") ) return
        addToHistory(number, "outgoing")
        linphoneService.call('make_call', [number], makeCallHandler)
		//currentCallNumber = number
		//console.log("GUI: Set state to 'outgoing' for number:", number)
    }

	function endCallHandler(result) {
		callState = "none"
		console.log("GUI: Hang up result:", result)
	}
    
    function endCall() {
        console.log("GUI: Ending call, current state:", callState)
        linphoneService.call('hang_up', [], endCallHandler)
    }
	
	function answerCallHandler(result) {
		console.log("GUI: Answer call result:", result)
		if (result) {
			callState = "active"
			callStartTime = new Date()
			console.log("GUI: Set state to 'active' after answer")
			
		}
	}
	
    function answerCall() {
        console.log("GUI: Answering call")
        linphoneService.call('answer_call', [], answerCallHandler)
    }
	
	function micChange() {
		console.log("GUI: Mic - " + (isMicON ? "ON" : "OFF") )
		linphoneService.call('setMic', [isMicON], makeCallHandler)
	}
    
	/*
    function handleCallStateChanged(state, number) {
        console.log("GUI: Call state changed - state:'" + state + "', number:'" + number + "', current state:'" + callState + "'")
        
        if (state === "incoming") {
            callState = "incoming"
            currentCallNumber = number
            addToHistory(number, "incoming")
            debugInfo = "Incoming call from " + number
            console.log("GUI: Set state to 'incoming'")
        }
        else if (state === "connected") {
            callState = "active"
            currentCallNumber = number
            callStartTime = new Date()
            debugInfo = "Call connected to " + number
            console.log("GUI: Set state to 'active', started timer")
        }
        else if (state === "ended") {
            callState = "none"
            currentCallNumber = ""
            callDuration = ""
            callStartTime = null
            debugInfo = "Call ended"
            console.log("GUI: Set state to 'none', stopped timer")
        }
        else if (state === "outgoing") {
            debugInfo = "Calling " + number
            console.log("GUI: Outgoing call to " + number)
        }
        else {
            console.log("GUI: Unknown call state: '" + state + "'")
        }
        
        updateStatusTime()
        
        // Принудительно обновляем UI после изменения состояний
        //callStateChanged()
        //currentCallNumberChanged()
        debugInfoLabel.text = debugInfo // Прямое обновление Label
    }
    
    function handleRegistrationStateChanged(registered) {
        console.log("GUI: Registration state signal received:", registered)
        isRegistered = registered
        debugInfo = "SIP " + (registered ? "registered" : "not registered")
        updateStatusTime()
        
        // Принудительно обновляем UI
        debugInfoLabel.text = debugInfo
    }
	*/
	
    
    function addToHistory(number, type) {
        var timestamp = new Date().toLocaleString(Qt.locale(), "dd.MM.yyyy HH:mm")
        var entry = {
            "number": number,
            "type": type,
            "time": timestamp
        }
        callHistory.unshift(entry)
        saveCallHistory()
    }
    
    function removeFromHistory(index) {
        callHistory.splice(index, 1)
        saveCallHistory()
    }
    
    function loadCallHistory() {
        try {
            var history = JSON.parse(appSettings.callHistory)
            callHistory = history
        } catch (e) {
            callHistory = []
        }
    }
    
    function saveCallHistory() {
        try {
            appSettings.callHistory = JSON.stringify(callHistory)
        } catch (e) {
            console.log("Error saving call history:", e)
        }
    }
    
    function clearCallHistory() {
        callHistory = []
        appSettings.callHistory = "[]"
    }
    
    Component.onCompleted: {
        console.log("GUI: MainPage component completed")
        loadCallHistory()
        
        // Start auto-check immediately
        //autoCheckStatus()
    }
}