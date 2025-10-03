TARGET = LinphoneUI

CONFIG += sailfishapp_qml

OTHER_FILES += qml/LinphoneUI.qml \
    qml/cover/CoverPage.qml \
    qml/pages/FirstPage.qml \
    qml/pages/SecondPage.qml \
    rpm/LinphoneUI.changes.in \
    rpm/LinphoneUI.spec \
    translations/*.ts \
    LinphoneUI.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 256x256


CONFIG += sailfishapp_i18n


TRANSLATIONS += translations/LinphoneUI.ts

DISTFILES += \
    qml/pages/button.py
