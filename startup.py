#!/usr/bin/env python3
"""Manage NotchNook's per-user login startup and crash recovery. No administrator access."""
import argparse
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import time

LABEL = 'local.notchharbor.startup'
DOMAIN = 'gui/{}'.format(os.getuid())
SERVICE = DOMAIN + '/' + LABEL
APP = Path.home() / 'Applications/NotchNook.app'
EXECUTABLE = APP / 'Contents/MacOS/NotchHarbor'
AGENT = Path.home() / 'Library/LaunchAgents' / (LABEL + '.plist')
LOGS = Path.home() / 'Library/Logs/NotchHarbor'


def call(*args, check=True):
    return subprocess.run(list(args), check=check, capture_output=True, text=True)


def status():
    result = call('launchctl', 'print', SERVICE, check=False)
    if result.returncode:
        print('Automatic startup is not loaded.')
        return False
    for line in result.stdout.splitlines():
        value = line.strip()
        if line.startswith('\t') and not line.startswith('\t\t') and value.startswith(('state =', 'pid =', 'runs =', 'last exit code =', 'last terminating signal =')):
            print(value)
    return True


def enable():
    if not EXECUTABLE.is_file():
        raise SystemExit('Install NotchNook in ~/Applications first.')
    with (APP / 'Contents/Info.plist').open('rb') as file:
        if plistlib.load(file).get('CFBundleIdentifier') != 'local.notchharbor.app':
            raise SystemExit('The installed app is not NotchNook.')
    call('codesign', '--verify', '--deep', '--strict', str(APP))
    shelf = Path.home() / 'Library/Application Support/NotchHarbor/Shelf'
    if shelf.exists() and any(shelf.glob('.import-*')):
        raise SystemExit('A file import may be active. Finish it before changing startup settings.')
    LOGS.mkdir(parents=True, exist_ok=True)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    config = {
        'Label': LABEL,
        'ProgramArguments': [str(EXECUTABLE)],
        'AssociatedBundleIdentifiers': ['local.notchharbor.app'],
        'LimitLoadToSessionType': 'Aqua',
        'ProcessType': 'Interactive',
        'RunAtLoad': True,
        # Relaunch abnormal exits. A deliberate Quit (exit 0) remains respected.
        'KeepAlive': {'SuccessfulExit': False},
        'ThrottleInterval': 5,
        'StandardOutPath': str(LOGS / 'startup.log'),
        'StandardErrorPath': str(LOGS / 'errors.log'),
    }
    running = call('launchctl', 'print', SERVICE, check=False)
    if AGENT.exists():
        with AGENT.open('rb') as file:
            existing = plistlib.load(file)
        if existing == config and running.returncode == 0 and 'state = running' in running.stdout:
            print('Already enabled and running.')
            status()
            return
    if running.returncode == 0:
        call('launchctl', 'bootout', SERVICE)
    # Adopt the existing app without creating two competing notch windows.
    listing = call('ps', '-axo', 'pid=,command=').stdout
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and (fields[1] == str(EXECUTABLE) or fields[1].startswith(str(EXECUTABLE) + ' ')):
            pid = int(fields[0])
            os.kill(pid, signal.SIGTERM)
            for _ in range(40):
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.05)
    temporary = AGENT.with_suffix('.plist.tmp')
    with temporary.open('wb') as file:
        plistlib.dump(config, file)
    temporary.chmod(0o644)
    temporary.replace(AGENT)
    call('plutil', '-lint', str(AGENT))
    call('launchctl', 'enable', SERVICE)
    call('launchctl', 'bootstrap', DOMAIN, str(AGENT))
    print('Enabled login startup and crash recovery.')
    status()


def disable():
    running = call('launchctl', 'print', SERVICE, check=False)
    if running.returncode == 0:
        call('launchctl', 'bootout', SERVICE)
    if AGENT.exists():
        # Keep an easy-to-restore copy rather than deleting the startup configuration.
        AGENT.replace(AGENT.with_name(AGENT.name + '.disabled'))
    print('Automatic startup disabled. Open the app normally to use it without automatic startup.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['enable', 'disable', 'status'])
    action = parser.parse_args().action
    try:
        {'enable': enable, 'disable': disable, 'status': status}[action]()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr.strip() or str(error))
