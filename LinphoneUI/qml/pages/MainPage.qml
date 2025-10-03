import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import Nemo.Configuration 1.0

Page {
    id: mainPage
    
    property bool isRegistered: false
    property var callHistory: []
    
    DBusInterface {
        id: linphoneService
        service: 'org.sailfishos.LinphoneUI'
        path: '/LinphoneUI'
        iface: 'org.sailfishos.LinphoneUI'
        
        function makeCall(number) {
            call('make_call', [number])
        }
        
        signal call_state_changed(string state, string number)
        signal registration_state_changed(bool registered)
    }
    
    ConfigurationGroup {
        id: appSettings
        path: "/apps/LinphoneUI"
        property string callHistory: "[]"
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        
        PullDownMenu {
            MenuItem {
                text: "Refresh History"
                onClicked: loadCallHistory()
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
            
            // Registration status
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                
                Rectangle {
                    anchors.fill: parent
                    color: isRegistered ? "#4CAF50" : "#F44336"
                    opacity: 0.3
                }
                
                Label {
                    anchors.centerIn: parent
                    text: isRegistered ? "SIP REGISTERED" : "SIP NOT REGISTERED"
                    color: isRegistered ? Theme.primaryColor : Theme.errorColor
                    font.pixelSize: Theme.fontSizeSmall
                }
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
            
            // Call button
            Button {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                text: "Make Call"
                onClicked: {
                    if (numberField.text.length > 0) {
                        makeCall(numberField.text)
                    }
                }
            }
            
            // Call history
            SectionHeader {
                text: "Call History"
                visible: callHistory.length > 0
            }
            
            Repeater {
                model: callHistory.slice(0, 10)
                
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
    
    function makeCall(number) {
        // Add to history
        addToHistory(number, "outgoing")
        
        // Make call
        linphoneService.makeCall(number)
        
        // Navigate to call page
        pageStack.push(Qt.resolvedUrl("CallPage.qml"), {
            callState: "outgoing",
            phoneNumber: number
        })
        
        // Clear input field
        numberField.text = ""
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
            console.log("Error loading call history:", e)
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
        loadCallHistory()
        
        // Connect D-Bus signals
        linphoneService.registration_state_changed.connect(function(registered) {
            isRegistered = registered
            console.log("Registration state changed:", registered)
        })
        
        linphoneService.call_state_changed.connect(function(state, number) {
            console.log("MainPage: Call state changed:", state, number)
            
            if (state === "incoming") {
                // Incoming call - navigate to call page
                addToHistory(number, "incoming")
                pageStack.push(Qt.resolvedUrl("CallPage.qml"), {
                    callState: "incoming",
                    phoneNumber: number
                })
            } else if (state === "connected") {
                // Call connected - update current call page if exists
                var currentPage = pageStack.currentPage
                if (currentPage && currentPage.callState) {
                    currentPage.callState = "active"
                }
            } else if (state === "ended") {
                // Call ended - navigate back to main page
                if (pageStack.depth > 1) {
                    pageStack.pop()
                }
            }
        })
    }
}