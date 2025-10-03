import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0

Page {
    id: callPage
    
    property string callState: "incoming" // incoming, outgoing, active
    property string phoneNumber: ""
    property string callDuration: ""
    
    DBusInterface {
        id: linphoneService
        service: 'org.sailfishos.LinphoneUI'
        path: '/LinphoneUI'
        iface: 'org.sailfishos.LinphoneUI'
        
        function hangUp() {
            call('hang_up')
        }
        
        function answerCall() {
            call('answer_call')
        }
        
        signal call_state_changed(string state, string number)
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingLarge
            
            PageHeader {
                title: {
                    if (callState === "incoming") return "Incoming Call"
                    if (callState === "outgoing") return "Outgoing Call"
                    if (callState === "active") return "Active Call"
                    return "Call"
                }
            }
            
            // Phone number display
            Rectangle {
                width: parent.width
                height: Theme.itemSizeExtraLarge * 2
                color: "transparent"
                
                Label {
                    anchors.centerIn: parent
                    text: phoneNumber
                    font.pixelSize: Theme.fontSizeExtraLarge
                    color: Theme.highlightColor
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width - 2*Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                }
            }
            
            // Call status
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (callState === "incoming") return "Incoming call..."
                    if (callState === "outgoing") return "Calling..."
                    if (callState === "active") return "In call"
                    return "Call"
                }
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeLarge
            }
            
            // Call duration for active calls
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: callDuration
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
                visible: callState === "active"
            }
            
            // Call controls
            Column {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge
                
                // Incoming call controls
                Row {
                    width: parent.width
                    spacing: Theme.paddingLarge
                    visible: callState === "incoming"
                    
                    Button {
                        text: "Answer"
                        width: (parent.width - Theme.paddingLarge) / 2
                        onClicked: {
                            linphoneService.answerCall()
                            callState = "active"
                            callStartTime = new Date()
                            callDurationTimer.start()
                        }
                    }
                    
                    Button {
                        text: "Decline"
                        width: (parent.width - Theme.paddingLarge) / 2
                        onClicked: endCall()
                    }
                }
                
                // Outgoing/Active call controls
                Button {
                    text: "End Call"
                    width: parent.width
                    visible: callState === "outgoing" || callState === "active"
                    onClicked: endCall()
                }
            }
            
            // Additional call info
            Label {
                width: parent.width - 2*Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: "Linphone VoIP Call"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                opacity: 0.7
            }
        }
    }
    
    property var callStartTime: null
    
    function endCall() {
        linphoneService.hangUp()
        // The page will be closed by the main page when call_state_changed signal is received
    }
    
    function updateCallDuration() {
        if (callStartTime && callState === "active") {
            var now = new Date()
            var diff = Math.floor((now - callStartTime) / 1000) // difference in seconds
            var minutes = Math.floor(diff / 60)
            var seconds = diff % 60
            callDuration = minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            callDuration = ""
        }
    }
    
    Timer {
        id: callDurationTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: updateCallDuration()
    }
    
    Component.onCompleted: {
        // Start timer for outgoing calls
        if (callState === "outgoing") {
            callStartTime = new Date()
            callDurationTimer.start()
        }
        
        // Connect to call state changes
        linphoneService.call_state_changed.connect(function(state, number) {
            console.log("CallPage: Call state changed:", state, number)
            
            if (state === "connected" && callState === "incoming") {
                // Call answered
                callState = "active"
                callStartTime = new Date()
                callDurationTimer.start()
            } else if (state === "ended") {
                // Call ended - stop timer and let main page handle navigation
                callDurationTimer.stop()
            }
        })
    }
}