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
    
    DBusInterface {
        id: linphoneService
        service: 'org.sailfishos.LinphoneUI'
        path: '/LinphoneUI'
        iface: 'org.sailfishos.LinphoneUI'
        
        signal call_state_changed(string state, string number)
        signal registration_state_changed(bool registered)
        
        // ПОДКЛЮЧИТЬ СИГНАЛЫ СРАЗУ ПРИ СОЗДАНИИ
        Component.onCompleted: {
            console.log("GUI: DBusInterface created, connecting signals...")
            call_state_changed.connect(handleCallStateChanged)
            registration_state_changed.connect(handleRegistrationStateChanged)
        }
    }
    
    ConfigurationGroup {
        id: appSettings
        path: "/apps/LinphoneUI"
        property string callHistory: "[]"
    }
    
    // Timer for automatic status checking
    Timer {
        id: statusCheckTimer
        interval: 3000 // Check every 3 seconds
        repeat: true
        running: true
        onTriggered: {
            console.log("GUI: Auto-checking status...")
            autoCheckStatus()
        }
    }
    
    // Timer for call duration
    Timer {
        id: callDurationTimer
        interval: 1000
        repeat: true
        running: callState === "active"
        onTriggered: updateCallDuration()
        onRunningChanged: console.log("GUI: Call duration timer running:", running)
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        
        PullDownMenu {
            MenuItem {
                text: "Refresh Status"
                onClicked: checkRegistrationStatus()
            }
            MenuItem {
                text: "Check Call State"
                onClicked: checkCurrentCallState()
            }
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
            
            // Auto-check info
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: "Last auto-check: " + lastStatusCheck
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeTiny
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
                    
                    BusyIndicator {
                        size: BusyIndicatorSize.Small
                        running: statusCheckTimer.running
                        visible: running
                    }
                }
            }
            
            // Current call info
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (callState === "incoming") return "Incoming: " + currentCallNumber
                    if (callState === "outgoing") return "Calling: " + currentCallNumber
                    if (callState === "active") return "Active: " + currentCallNumber + " (" + callDuration + ")"
                    return ""
                }
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
                visible: callState !== "none"
            }
            
            // Debug info
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                text: debugInfo
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
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
                
                EnterKey.iconSource: "image://theme/icon-m-call"
                EnterKey.onClicked: {
                    if (text.length > 0) {
                        makeCall(text)
                    }
                }
            }
            
            // Dial pad
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
            
            // Call buttons
            Column {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingSmall
                
                Button {
                    width: parent.width
                    text: "Make Call"
                    enabled: isRegistered && numberField.text.length > 0 && callState === "none"
                    onClicked: {
                        if (numberField.text.length > 0) {
                            makeCall(numberField.text)
                        }
                    }
                }
                
                Button {
                    width: parent.width
                    text: {
                        if (callState === "incoming") return "Answer Call"
                        else return "End Call"
                    }
                    visible: callState !== "none"
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
        console.log("GUI: updateCallDuration called, callState:", callState, "callStartTime:", callStartTime)
        if (callStartTime && callState === "active") {
            var now = new Date()
            var diff = Math.floor((now - callStartTime) / 1000)
            var minutes = Math.floor(diff / 60)
            var seconds = diff % 60
            callDuration = minutes + ":" + (seconds < 10 ? "0" : "") + seconds
            console.log("GUI: Call duration updated to:", callDuration)
        }
    }
    
    function updateStatusTime() {
        lastStatusCheck = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")
    }
    
    function autoCheckStatus() {
        console.log("GUI: Auto-checking registration and call state...")
        
        // Check registration status
        linphoneService.call('is_registered', [], function(registeredResult) {
            console.log("GUI: Auto-check registered:", registeredResult)
            isRegistered = registeredResult
            
            // Check current call state
            linphoneService.call('get_current_call_info', [], function(callInfo) {
                console.log("GUI: Auto-check call info:", callInfo)
                
                // Update debug info
                debugInfo = "Auto: reg=" + registeredResult + " call=" + callInfo
                updateStatusTime()
                
                // If we think there's no call but daemon reports one, sync state
                if (callState === "none" && callInfo !== "No active call" && callInfo !== "Daemon not available") {
                    console.log("GUI: Auto-check detected missed call state:", callInfo)
                    debugInfo = "Missed call state: " + callInfo
                    
                    // Try to parse call info and update state
                    if (callInfo.includes("Outgoing")) {
                        callState = "outgoing"
                        currentCallNumber = extractNumberFromCallInfo(callInfo)
                    } else if (callInfo.includes("active")) {
                        callState = "active"
                        currentCallNumber = extractNumberFromCallInfo(callInfo)
                        callStartTime = new Date()
                    }
                }
            })
        })
    }
    
    function extractNumberFromCallInfo(callInfo) {
        // Simple extraction from "Call: 1010 (outgoing)" format
        var match = callInfo.match(/Call:\s*([^\s\(]+)/)
        return match ? match[1] : "Unknown"
    }
    
    function checkRegistrationStatus() {
        linphoneService.call('check_registration_status', [], function(result) {
            debugInfo = "Manual check: " + result
            updateStatusTime()
        })
    }
    
    function checkCurrentCallState() {
        linphoneService.call('get_current_call_info', [], function(result) {
            debugInfo = "Call state: " + result
            updateStatusTime()
        })
    }
    
    function makeCall(number) {
        if (!isRegistered) {
            debugInfo = "Call failed: not registered"
            return
        }
        
        if (callState !== "none") {
            debugInfo = "Another call in progress"
            return
        }
        
        addToHistory(number, "outgoing")
        
        linphoneService.call('make_call', [number], function(result) {
            console.log("GUI: make_call result:", result)
            if (result) {
                callState = "outgoing"
                currentCallNumber = number
                callStartTime = new Date()
                numberField.text = ""
                debugInfo = "Calling " + number
                console.log("GUI: Set state to 'outgoing' for number:", number)
            } else {
                debugInfo = "Call failed"
            }
        })
    }
    
    function endCall() {
        console.log("GUI: Ending call, current state:", callState)
        linphoneService.call('hang_up', [], function(result) {
            console.log("GUI: Hang up result:", result)
        })
    }
    
    function answerCall() {
        console.log("GUI: Answering call")
        linphoneService.call('answer_call', [], function(result) {
            console.log("GUI: Answer call result:", result)
            if (result) {
                callState = "active"
                callStartTime = new Date()
                console.log("GUI: Set state to 'active' after answer")
            }
        })
    }
    
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
    }
    
    function handleRegistrationStateChanged(registered) {
        console.log("GUI: Registration state signal received:", registered)
        isRegistered = registered
        debugInfo = "SIP " + (registered ? "registered" : "not registered")
        updateStatusTime()
    }
    
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
        autoCheckStatus()
    }
}