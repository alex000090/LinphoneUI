import QtQuick 2.0
import Sailfish.Silica 1.0

import "pages"

ApplicationWindow {
    id: app
    
    initialPage: Component { MainPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    
    // This will be called when the app is launched by the daemon for incoming calls
    function showIncomingCall(number) {
        // If app is not active, bring it to foreground
        if (!app.applicationActive) {
            app.activate()
        }
        
        // Navigate to call page
        pageStack.push(Qt.resolvedUrl("pages/CallPage.qml"), {
            callState: "incoming",
            phoneNumber: number
        })
    }
    
    Component.onCompleted: {
        console.log("LinphoneUI application started")
    }
}