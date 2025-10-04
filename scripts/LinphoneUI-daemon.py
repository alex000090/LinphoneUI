#!/usr/bin/python3
import os
import sys
import time
import signal
import logging
import subprocess
import threading
from pathlib import Path
import pulsectl
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
import gi
gi.require_version('GLib', '2.0')
from gi.repository import GLib

class LinphoneDaemon:
    def __init__(self):
        self.setup_logging()
        self.running = True
        self.in_call = False
        self.current_call_number = None
        self.is_registered = False
        self.linphone_started = False
        
        # Initialize PulseAudio
        self.pulse = pulsectl.Pulse('linphoneui-daemon')
        
        # Initialize D-Bus with main loop
        self.setup_dbus()
        
        # Start linphone with config file
        self.start_linphone()
        
        self.logger.info("Linphone daemon started")
    
    def setup_logging(self):
        """Setup logging"""
        log_dir = Path.home() / '.local' / 'share' / 'LinphoneUI'
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / 'linphone_daemon.log'
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('LinphoneDaemon')
    
    def setup_dbus(self):
        """Setup D-Bus communication with main loop"""
        try:
            DBusGMainLoop(set_as_default=True)
            self.bus = dbus.SessionBus()
            self.bus_name = dbus.service.BusName('org.sailfishos.LinphoneUI', self.bus)
            # Pass self (daemon instance) to D-Bus object
            self.dbus_object = LinphoneDBusObject(self.bus, '/LinphoneUI', self)
            self.logger.info("D-Bus service registered")
        except Exception as e:
            self.logger.error(f"D-Bus error: {e}")
    
    def start_linphone(self):
        """Start linphonecsh with config file and wait for initialization"""
        try:
            # Ensure config directory exists
            config_path = Path.home() / '.linphonerc'
            
            self.logger.info(f"Starting linphone with config: {config_path}")
            
            # Start linphone with config file
            result = subprocess.run(
                ['linphonecsh', 'init', '-c', str(config_path)], 
                check=True, timeout=15, capture_output=True, text=True
            )
            
            self.linphone_started = True
            self.logger.info(f"Linphone started successfully")
            self.logger.debug(f"Linphone init output: {result.stdout}")
            
            # Wait a bit for linphone to fully initialize
            time.sleep(3)
            
            # Check initial status and force update WITH SIGNAL EMISSION
            self.check_and_update_registration_status(force_update=True)
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Linphone start error: {e}")
            self.logger.error(f"Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            self.logger.error("Linphone start timeout")
        except Exception as e:
            self.logger.error(f"Linphone start exception: {e}")
    
    def launch_gui(self):
        """Launch the GUI application"""
        try:
            self.logger.info("Launching GUI application...")
            
            # Use invoker to launch Sailfish OS application
            subprocess.Popen([
                'invoker', '--type=silica-qt5', 'sailfish-qml',
                'LinphoneUI'
            ])
            self.logger.info("GUI launch command sent")
            
        except Exception as e:
            self.logger.error(f"Error launching GUI: {e}")
    
    def check_linphone_status(self):
        """Check linphone registration status with detailed output"""
        try:
            result = subprocess.run(
                ['linphonecsh', 'status', 'register'],
                capture_output=True, text=True, timeout=10
            )
            self.logger.debug(f"Raw registration output: '{result.stdout}'")
            return result.stdout.strip()
        except Exception as e:
            self.logger.error(f"Registration status check error: {e}")
            return ""
    
    def parse_registration_status(self, status_output):
        """Parse registration status from linphonecsh output"""
        if not status_output:
            return False
            
        # Successful registration: "registered, identity=sip:1001@bregz.sknt.ru duration=300"
        if status_output.startswith("registered,"):
            return True
            
        # Failed registration: "registered=0"
        if status_output == "registered=0":
            return False
            
        # Other cases
        if "registered" in status_output.lower():
            return True
            
        return False
    
    def check_and_update_registration_status(self, force_update=False):
        """Check and update registration status with proper parsing"""
        reg_output = self.check_linphone_status()
        was_registered = self.is_registered
        
        self.is_registered = self.parse_registration_status(reg_output)
        
        self.logger.info(f"Registration check: was={was_registered}, now={self.is_registered}, output='{reg_output}'")
        
        if self.is_registered:
            if not was_registered or force_update:
                self.logger.info(f"SIP registration: SUCCESS - {reg_output}")
                # Send signal to GUI
                self.dbus_object.emit_registration_state(True)
        else:
            if was_registered or force_update:
                self.logger.info(f"SIP registration: FAILED - {reg_output}")
                # Send signal to GUI
                self.dbus_object.emit_registration_state(False)
    
    def check_linphone_calls(self):
        """Check current calls using linphonecsh"""
        try:
            result = subprocess.run(
                ['linphonecsh', 'generic', 'calls'],
                capture_output=True, text=True, timeout=10
            )
            return result.stdout
        except Exception as e:
            self.logger.error(f"Calls check error: {e}")
            return ""
    
    def parse_linphone_calls(self, calls_output):
        """Parse linphonecsh generic calls output"""
        call_info = {
            'has_call': False,
            'call_type': None,
            'number': None,
            'call_id': None
        }
        
        try:
            lines = calls_output.split('\n')
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                
                parts = line.split('|')
                if len(parts) >= 3:
                    call_id = parts[0].strip()
                    call_info_str = parts[1].strip()
                    status = parts[2].strip()

                    
                    self.logger.debug(f"Call: ID={call_id}, Info={call_info_str}, Status={status}")
                    
                    number = self.extract_number_from_sip(call_info_str)
                    
                    call_info['has_call'] = True
                    call_info['call_id'] = call_id
                    call_info['number'] = number
                    
                    if status == "IncomingReceived":
                        call_info['call_type'] = 'incoming'
                    elif status == "OutgoingRinging":
                        call_info['call_type'] = 'outgoing'
                    elif status == "StreamsRunning":
                        call_info['call_type'] = 'active'
                    else: continue
                    break
                    
        except Exception as e:
            self.logger.error(f"Error parsing calls: {e}")
        
        return call_info
    
    def extract_number_from_sip(self, sip_info):
        """Extract phone number from SIP info"""
        try:
            if '<' in sip_info and '>' in sip_info:
                start = sip_info.find('<sip:') + 5
                end = sip_info.find('@', start)
                if start > 4 and end > start:
                    return sip_info[start:end]
            else:
                if sip_info.startswith('sip:'):
                    start = 4
                    end = sip_info.find('@', start)
                    if end > start:
                        return sip_info[start:end]
            
            return sip_info
        except Exception as e:
            self.logger.debug(f"Error extracting number: {e}")
            return "Unknown"
    
    def setup_call_audio(self):
        """Setup audio for call"""
        try:
            time.sleep(1)
            
            for sink_input in self.pulse.sink_input_list():
                props = sink_input.proplist
                app_name = props.get('application.name', '')
                
                if any(keyword in app_name.lower() for keyword in ['linphone', 'call', 'voip']):
                    for sink in self.pulse.sink_list():
                        if any(name in sink.name for name in ['handsfree', 'output', 'speaker']):
                            self.pulse.sink_input_move(sink_input.index, sink.index)
                            self.logger.info(f"Audio redirected to {sink.name}")
                            break
                            
        except Exception as e:
            self.logger.error(f"Audio setup error: {e}")
    
    def restore_audio(self):
        """Restore normal audio settings"""
        try:
            self.logger.info("Audio settings restored")
        except Exception as e:
            self.logger.error(f"Audio restore error: {e}")
    
    def handle_incoming_call(self, number):
        """Handle incoming call"""
        self.logger.info(f"Incoming call: {number}")
        self.in_call = True
        self.current_call_number = number
        
        # Launch GUI to show the call interface
        self.launch_gui()
        
        # Setup audio
        self.setup_call_audio()
        
        # Notify GUI - передаем номер как строку
        self.dbus_object.emit_call_state("incoming", str(number))

    def handle_outgoing_call(self, number):
        """Handle outgoing call initiation"""
        self.logger.info(f"Outgoing call: {number}")
        self.in_call = True
        self.current_call_number = number
        
        # Notify GUI - передаем номер как строку
        self.dbus_object.emit_call_state("outgoing", str(number))

    def handle_call_connected(self, number):
        """Handle connected call"""
        self.logger.info(f"Call connected: {number}")
        self.in_call = True
        self.current_call_number = number
        
        # Notify GUI - передаем номер как строку
        self.dbus_object.emit_call_state("connected", str(number))

    def handle_call_ended(self):
        """Handle call end"""
        self.logger.info("Call ended")
        self.in_call = False
        
        # Restore audio
        self.restore_audio()
        
        # Notify GUI - передаем пустую строку вместо false
        self.dbus_object.emit_call_state("ended", "")
        
        self.current_call_number = None


    def monitor_linphone(self):
        """Main monitoring loop"""
        while self.running:
            try:
                if not self.linphone_started:
                    self.logger.warning("Linphone not started, skipping monitoring cycle")
                    time.sleep(5)
                    continue
                
                # Check registration status
                self.check_and_update_registration_status()
                
                # Check current calls
                calls_output = self.check_linphone_calls()
                call_info = self.parse_linphone_calls(calls_output)
                
                # Handle call state changes
                if call_info['has_call']:
                    if not self.in_call:
                        # New call detected
                        self.in_call = True
                        self.current_call_number = call_info['number']
                        
                        if call_info['call_type'] == 'incoming':
                            self.handle_incoming_call(self.current_call_number)
                        elif call_info['call_type'] == 'outgoing':
                            self.handle_outgoing_call(self.current_call_number)
                        elif call_info['call_type'] == 'active':
                            self.handle_call_connected(self.current_call_number)
                    
                    else:
                        # Existing call changed state
                        if call_info['call_type'] == 'active' and self.current_call_number:
                            # Call became active
                            self.handle_call_connected(self.current_call_number)
                        
                elif not call_info['has_call'] and self.in_call:
                    # Call ended
                    self.handle_call_ended()
                
            except Exception as e:
                self.logger.error(f"Monitoring error: {e}")
            
            time.sleep(1)
    
    def shutdown(self):
        """Clean shutdown"""
        self.logger.info("Shutting down daemon...")
        self.running = False
        try:
            subprocess.run(['linphonecsh', 'exit'], timeout=5)
        except:
            pass


class LinphoneDBusObject(dbus.service.Object):
    """D-Bus object for GUI communication"""
    
    def __init__(self, bus, object_path, daemon):
        super().__init__(bus, object_path)
        self.daemon = daemon
    
    @dbus.service.signal('org.sailfishos.LinphoneUI', signature='b')
    def registration_state_changed(self, registered):
        """Signal for registration state changes"""
        pass
    
    @dbus.service.signal('org.sailfishos.LinphoneUI', signature='ss')
    def call_state_changed(self, state, number):
        """Signal for call state changes with number"""
        pass
    
    @dbus.service.method('org.sailfishos.LinphoneUI', in_signature='s', out_signature='b')
    def make_call(self, number):
        """Make call using linphonecsh"""
        try:
            self._log_call_action(f"Making call to {number}")
            result = subprocess.run(
                ['linphonecsh', 'dial', number], 
                check=True, timeout=10, capture_output=True, text=True
            )
            self._log_call_action(f"Call result: {result.stdout}")
            return True
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Call error: {e}")
            return False
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='b')
    def hang_up(self):
        """Hang up call using linphonecsh"""
        try:
            self._log_call_action("Hanging up call")
            result = subprocess.run(
                ['linphonecsh', 'generic', 'terminate'], 
                check=True, timeout=10, capture_output=True, text=True
            )
            self._log_call_action(f"Hangup result: {result.stdout}")
            return True
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Hangup error: {e}")
            return False
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='b')
    def answer_call(self):
        """Answer call using linphonecsh"""
        try:
            self._log_call_action("Answering call")
            result = subprocess.run(
                ['linphonecsh', 'generic', 'answer'], 
                check=True, timeout=10, capture_output=True, text=True
            )
            self._log_call_action(f"Answer result: {result.stdout}")
            return True
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Answer error: {e}")
            return False


    @dbus.service.method('org.sailfishos.LinphoneUI', in_signature='s', out_signature='b')
    def make_call(self, number):
        """Make call using linphonecsh"""
        try:
            self._log_call_action(f"Making call to {number}")
            result = subprocess.run(
                ['linphonecsh', 'dial', number], 
                check=True, timeout=10, capture_output=True, text=True
            )
            self._log_call_action(f"Call result: {result.stdout}")
            
            # Notify about outgoing call initiation
            import __main__ as main
            if hasattr(main, 'daemon'):
                main.daemon.handle_outgoing_call(number)
                
            return True
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Call error: {e}")
            return False


    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='b')
    def check_registration_status(self):
        """Force check and update registration status"""
        try:
            if self.daemon:
                self.daemon.check_and_update_registration_status(force_update=True)
                return True
            else:
                logging.getLogger('LinphoneDaemon').error("Daemon instance not available")
                return False
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Status check error: {e}")
            return False
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='s')
    def get_registration_status(self):
        """Get current registration status as string"""
        try:
            if self.daemon:
                status_output = self.daemon.check_linphone_status()
                return status_output
            else:
                return "Daemon not available"
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Get status error: {e}")
            return f"Error: {e}"
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='b')
    def is_registered(self):
        """Check if currently registered to SIP"""
        try:
            if self.daemon:
                return self.daemon.is_registered
            else:
                return False
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Registration check error: {e}")
            return False
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='s')
    def get_current_call_info(self):
        """Get information about current call"""
        try:
            if self.daemon:
                calls_output = self.daemon.check_linphone_calls()
                call_info = self.daemon.parse_linphone_calls(calls_output)
                
                if call_info['has_call']:
                    return f"Call: {call_info['number']} ({call_info['call_type']})"
                else:
                    return "No active call"
            else:
                return "Daemon not available"
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Call info error: {e}")
            return f"Error: {e}"
    
    @dbus.service.method('org.sailfishos.LinphoneUI', out_signature='b')
    def restart_linphone(self):
        """Restart linphone service"""
        try:
            self._log_call_action("Restarting linphone service")
            if self.daemon:
                self.daemon.shutdown()
                time.sleep(2)
                self.daemon.start_linphone()
                return True
            else:
                return False
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Restart error: {e}")
            return False
    
    def _log_call_action(self, message):
        logging.getLogger('LinphoneDaemon').info(message)
    
    def emit_call_state(self, state, number):
        """Send call state change signal"""
        try:
            self.call_state_changed(state, str(number))  # Убедитесь, что number это строка
            logging.getLogger('LinphoneDaemon').info(f"Emitted call state signal: {state}, {number}")
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Error emitting call state: {e}")
    
    def emit_registration_state(self, registered):
        """Send registration state change signal"""
        try:
            self.registration_state_changed(registered)
            logging.getLogger('LinphoneDaemon').info(f"Emitted registration state signal: {registered}")
        except Exception as e:
            logging.getLogger('LinphoneDaemon').error(f"Error emitting registration state: {e}")


def main():
    daemon = None
    
    def signal_handler(signum, frame):
        if daemon:
            daemon.shutdown()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        daemon = LinphoneDaemon()
        
        # Start monitoring in background thread
        monitor_thread = threading.Thread(target=daemon.monitor_linphone, daemon=True)
        monitor_thread.start()
        
        # Start GLib main loop
        loop = GLib.MainLoop()
        loop.run()
            
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.error(f"Main function error: {e}")
    finally:
        if daemon:
            daemon.shutdown()


if __name__ == "__main__":
    main()