#!/usr/bin/env python3
"""Runs a release APK on an emulator and checks its Core is reachable.

A debug build does not exercise the obfuscation a phone gets: `flutter test` and
`flutter run` both ship unminified code, so a keep rule that stops matching after
a package rename only ever fails in the release artefact. This boots an emulator,
installs the release APK, and walks the first run far enough to make the app ask
the Core to compile a profile. The editor only opens once that answer arrives, so
an app whose Core stays silent fails here, and logcat is swept for the two ways
that has looked: "Core did not answer", and "Invalid shared state" from the
service channel, where Gson could not read the JSON a keep rule had obfuscated.

usage: python3 tool/android_smoke.py [--apk PATH] [--avd NAME] [--keep-emulator]

Default APK is a fresh x86_64 release build, since an emulator is x86_64.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYSTEM_IMAGE = "system-images/android-34/default/x86_64"
APP_ID = "icu.watermeko.clash"
DISCLAIMER = (
    "The Software itself does not provide any proxy server, node, subscription, "
    "or network access service, and has no partnership, agency, or guarantee "
    "relationship with any provider of such services."
)
# What a minified release got wrong, and what it looked like.
FAILURES = {
    "Invalid shared state": "the service channel rejected the shared state, so a "
    "keep rule lost the JSON models",
    "Core did not answer": "the Core never replied, so the app cannot start a run",
}


def log(line: str) -> None:
    print(line, flush=True)


def die(line: str) -> None:
    log(f"error: {line}")
    sys.exit(1)


def android_home() -> Path:
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        value = os.environ.get(name)
        if value and Path(value).is_dir():
            return Path(value)
    for guess in (Path.home() / "android-sdk", Path("/usr/lib/android-sdk")):
        if guess.is_dir():
            return guess
    die("no Android SDK; set ANDROID_HOME")


def adb(*args: str, serial: str | None = None, timeout: int = 300) -> str:
    command = ["adb"]
    if serial:
        command += ["-s", serial]
    command += list(args)
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0 and "error" not in result.stdout.lower():
        pass
    return result.stdout


def adb_shell(serial: str, command: str, timeout: int = 300) -> str:
    return adb("shell", command, serial=serial, timeout=timeout)


# --- emulator ---------------------------------------------------------------


def avd_home() -> Path:
    return Path.home() / ".android" / "avd"


def write_avd(name: str, sdk: Path) -> None:
    """A config.ini the emulator reads is enough; avdmanager needs the SDK to
    list the image, which a hand-unpacked one is not."""
    directory = avd_home() / f"{name}.avd"
    directory.mkdir(parents=True, exist_ok=True)
    (avd_home() / f"{name}.ini").write_text(
        "avd.ini.encoding=UTF-8\n"
        f"path={directory}\n"
        f"path.rel=avd/{name}.avd\n"
        "target=android-34\n"
    )
    (directory / "config.ini").write_text(
        f"""AvdId={name}
avd.ini.displayname={name}
avd.ini.encoding=UTF-8
abi.type=x86_64
hw.cpu.arch=x86_64
hw.cpu.ncore=4
image.sysdir.1={SYSTEM_IMAGE}/
tag.id=default
tag.display=Default Android System Image
hw.ramSize=3072
vm.heapSize=256
disk.dataPartition.size=6G
hw.lcd.density=420
hw.lcd.width=1080
hw.lcd.height=2400
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.audioInput=no
hw.audioOutput=no
hw.camera.back=none
hw.camera.front=none
showDeviceFrame=no
fastboot.forceColdBoot=yes
"""
    )


def boot_emulator(sdk: Path, name: str) -> str:
    """Returns the adb serial of a ready emulator, starting one if needed."""
    for line in adb("devices").splitlines():
        match = re.match(r"(emulator-\d+)\s+device", line.strip())
        if match:
            serial = match.group(1)
            log(f"reusing {serial}")
            return serial

    if not (avd_home() / f"{name}.ini").exists():
        write_avd(name, sdk)
    if not (sdk / SYSTEM_IMAGE).is_dir():
        die(
            f"{SYSTEM_IMAGE} is missing; install it with\n"
            f"  sdkmanager --install '{SYSTEM_IMAGE}'"
        )

    environment = dict(os.environ, ANDROID_SDK_ROOT=str(sdk), ANDROID_HOME=str(sdk))
    log(f"booting {name}")
    subprocess.Popen(
        [
            str(sdk / "emulator" / "emulator"),
            "-avd",
            name,
            "-no-window",
            "-no-audio",
            "-no-snapshot",
            "-no-boot-anim",
            "-gpu",
            "swiftshader_indirect",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
        start_new_session=True,
    )

    deadline = time.time() + 300
    while time.time() < deadline:
        for line in adb("devices").splitlines():
            match = re.match(r"(emulator-\d+)\s+device", line.strip())
            if not match:
                continue
            serial = match.group(1)
            if "1" in adb_shell(serial, "getprop sys.boot_completed").strip():
                log(f"booted {serial}")
                return serial
        time.sleep(5)
    die("the emulator did not boot within 5 minutes")


# --- ui ---------------------------------------------------------------------


def nodes(serial: str) -> list[dict]:
    adb_shell(serial, "uiautomator dump /sdcard/ui.xml")
    xml = adb_shell(serial, "cat /sdcard/ui.xml")
    found = []
    for match in re.finditer(r"<node[^>]*>", xml):
        raw = match.group(0)

        def attr(name: str) -> str:
            found_attr = re.search(rf'{name}="([^"]*)"', raw)
            return found_attr.group(1) if found_attr else ""

        bounds = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", attr("bounds"))
        if not bounds:
            continue
        x1, y1, x2, y2 = map(int, bounds.groups())
        found.append(
            {
                "text": attr("text"),
                "desc": attr("content-desc"),
                "cls": attr("class"),
                "cx": (x1 + x2) // 2,
                "cy": (y1 + y2) // 2,
            }
        )
    return found


def find(serial: str, want: str, timeout: float = 20) -> dict | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for node in nodes(serial):
            if want in (node["text"], node["desc"]):
                return node
        time.sleep(2)
    return None


def tap(serial: str, want: str, timeout: float = 20) -> bool:
    node = find(serial, want, timeout)
    if node is None:
        return False
    adb_shell(serial, f"input tap {node['cx']} {node['cy']}")
    log(f"tapped {want!r}")
    return True


def tap_or_die(serial: str, want: str, timeout: float = 20) -> None:
    if not tap(serial, want, timeout):
        die(f"{want!r} never appeared")


# --- the check --------------------------------------------------------------


def install(serial: str, apk: Path) -> None:
    adb_shell(serial, f"pm uninstall {APP_ID}")
    output = adb("install", "-r", str(apk), serial=serial, timeout=900)
    if "Success" not in output:
        die(f"the APK did not install: {output.strip()}")


def launch(serial: str) -> None:
    adb_shell(serial, "logcat -c")
    adb_shell(serial, f"am start -n {APP_ID}/icu.watermeko.clash.MainActivity")


def accept_disclaimer(serial: str) -> None:
    """The first run asks for a typed restatement, which is the only part of the
    flow that needs the keyboard; everything else is a tap on a label."""
    if not tap(serial, "Agree", timeout=30):
        log("no disclaimer, carrying on")
        return
    if not find(serial, "Restate the statement", 10):
        log("the disclaimer needed no restatement")
        return
    field = next(
        (node for node in nodes(serial) if "EditText" in node["cls"]), None
    )
    if field is None:
        die("the restatement dialog has no text field")
    adb_shell(serial, f"input tap {field['cx']} {field['cy']}")
    time.sleep(2)
    adb_shell(serial, f"input text '{DISCLAIMER.replace(' ', '%s')}'")
    time.sleep(2)
    tap_or_die(serial, "Confirm", 15)
    time.sleep(4)


def add_custom_profile(serial: str) -> None:
    if not find(serial, "Dashboard", 40) and not find(serial, "Add profile", 5):
        die("the app never reached its dashboard")
    if find(serial, "Add profile", 5):
        tap(serial, "Add profile")
    elif find(serial, "Profiles", 5):
        tap(serial, "Profiles")
        tap_or_die(serial, "Add profile", 15)
    else:
        die("the Profiles sheet did not open")
    if not tap(serial, "Custom", 15):
        die("the profile sources menu did not offer Custom")
    # "Proxy group" only exists in the editor: the list page shows "No Profiles
    # yet" and its own Import button, so matching that would pass on a Core that
    # never answered.
    if not find(serial, "Proxy group", 40):
        die("adding a profile opened no editor; the Core did not answer setupConfig")
    log("the editor opened, so the Core compiled the profile")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", help="release APK to check, x86_64")
    parser.add_argument("--avd", default="flclash")
    parser.add_argument("--keep-emulator", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    sdk = android_home()
    apk = Path(args.apk) if args.apk else ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    if not args.apk and not args.skip_build:
        log("building a release APK for x86_64")
        subprocess.run(
            [
                "flutter",
                "build",
                "apk",
                "--release",
                "--target-platform",
                "android-x64",
                "--dart-define-from-file=env.json",
            ],
            cwd=ROOT,
            check=True,
        )
    if not apk.exists():
        die(f"{apk} does not exist")

    serial = boot_emulator(sdk, args.avd)
    install(serial, apk)
    launch(serial)
    time.sleep(20)
    accept_disclaimer(serial)
    add_custom_profile(serial)

    logcat = adb_shell(serial, "logcat -d")
    problems = [
        f"{marker}: {reason}"
        for marker, reason in FAILURES.items()
        if marker in logcat
    ]

    if problems:
        for problem in problems:
            log(f"FAIL {problem}")
        lines = [
            line
            for line in logcat.splitlines()
            if any(marker in line for marker in FAILURES)
        ]
        for line in lines[:10]:
            log(f"  {line}")
        return 1

    log("ok: the release build compiled a profile, so its Core answered")
    if not args.keep_emulator:
        adb("emu", "kill", serial=serial)
    return 0


if __name__ == "__main__":
    sys.exit(main())