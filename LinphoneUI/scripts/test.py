#!/usr/bin/python3
import dbus

def check_voicecall_providers():
    """Check available voicecall providers"""
    try:
        bus = dbus.SessionBus()
        voicecall_mgr = bus.get_object('org.nemomobile.voicecall', '/')
        
        providers = voicecall_mgr.Get('org.nemomobile.voicecall.VoiceCallManager', 'providers',
                                    dbus_interface='org.freedesktop.DBus.Properties')
        
        print("=== Available VoiceCall Providers ===")
        for provider in providers:
            print(f"Provider: {provider}")
            
            # Try to get provider details
            try:
                provider_obj = bus.get_object('org.nemomobile.voicecall', provider)
                properties = provider_obj.GetAll('org.nemomobile.voicecall.VoiceCallProvider',
                                               dbus_interface='org.freedesktop.DBus.Properties')
                print(f"  Properties: {properties}")
            except Exception as e:
                print(f"  Could not get properties: {e}")
                
    except Exception as e:
        print(f"Error: {e}")

def test_dial_with_different_providers():
    """Test dialing with different providers"""
    bus = dbus.SessionBus()
    voicecall_mgr = bus.get_object('org.nemomobile.voicecall', '/')
    
    providers = voicecall_mgr.Get('org.nemomobile.voicecall.VoiceCallManager', 'providers',
                                dbus_interface='org.freedesktop.DBus.Properties')
    
    test_number = "+1234567890"  # Test number
    
    print("\n=== Testing Dial with Different Providers ===")
    for provider in providers:
        print(f"Testing provider: {provider}")
        try:
            result = voicecall_mgr.dial(provider, test_number, 
                                      dbus_interface='org.nemomobile.voicecall.VoiceCallManager')
            print(f"  Result: {result}")
        except Exception as e:
            print(f"  Error: {e}")

if __name__ == "__main__":
    check_voicecall_providers()
    test_dial_with_different_providers()