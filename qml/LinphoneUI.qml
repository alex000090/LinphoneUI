import QtQuick 2.0
import Sailfish.Silica 1.0

import "pages"

ApplicationWindow {
    id: app
    
    initialPage: Component { MainPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    
    function showIncomingCall(number) {
        console.log("Incoming call received in ApplicationWindow:", number)
        
        if (!app.applicationActive) {
            console.log("Activating application for incoming call")
            app.activate()
        }
        
        // Navigation is now handled within MainPage via D-Bus signals
        // No need to push CallPage since everything is in MainPage
    }
    
    Component.onCompleted: {
        console.log("LinphoneUI application started")
    }
}