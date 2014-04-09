// configure pin1 as wakeup
hardware.pin1.configure(DIGITAL_IN_WAKEUP);

// if we wokeup because of a button press
if(hardware.wakereason() == WAKEREASON_PIN1) {
    agent.send("buttonPress", null);
}

// go to deepsleep to save batteries
imp.onidle(function() { imp.deepsleepfor(2419198); });

