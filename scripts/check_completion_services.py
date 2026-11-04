#!/usr/bin/env python3
"""Read-only smoke checks for the services used by Mivo's current clients.

Uses only the public app configuration. It does not sign in, create sessions,
send AI prompts, or print credentials.
"""
import argparse
import json
from pathlib import Path
import plistlib
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plist", type=Path, default=Path(__file__).resolve().parent.parent / "Mivo/Info.plist")
    options = parser.parse_args()
    config = plistlib.loads(options.plist.read_bytes())
    base = config.get("MIVO_SUPABASE_URL", "").strip().removesuffix("/").removesuffix("/rest/v1")
    key = config.get("MIVO_SUPABASE_ANON_KEY", "").strip()
    if urlparse(base).scheme != "https" or not key or "$" in base:
        parser.error("Provide --plist pointing to an app configuration with a valid HTTPS service URL and public key")

    checks = [
        ("Study sync", "rest/v1/rpc/my_study_sessions", {}, "protected"),
        ("Linked computer study", "rest/v1/rpc/my_linked_study", {}, "protected"),
        ("Study rooms", "rest/v1/rpc/study_room_view", {"input_code": "INVALID"}, "room"),
        ("Milo AI", "functions/v1/mivo-ai", {}, "ai"),
    ]
    failures = 0
    for label, path, body, expected in checks:
        request = Request(f"{base}/{path}", data=json.dumps(body).encode(), method="POST", headers={
            "Content-Type": "application/json", "apikey": key, "Authorization": f"Bearer {key}",
        })
        try:
            with urlopen(request, timeout=20) as response:
                status, raw = response.status, response.read()
        except HTTPError as error:
            status, raw = error.code, error.read()
        except URLError:
            print(f"FAIL {label}: service could not be reached")
            failures += 1
            continue
        try:
            payload = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            payload = {}
        payload = payload if isinstance(payload, dict) else {}
        code = payload.get("code") or payload.get("error") or ""
        if expected == "protected":
            passed = status in (400, 401, 403) and (code == "42501" or "authentication_required" in str(payload.get("message", "")))
        elif expected == "room":
            passed = status == 200 and payload.get("found") is False
        else:
            passed = status == 401 and code == "authentication_required"
        print(f"{'PASS' if passed else 'FAIL'} {label}: HTTP {status}" + (f" ({code})" if code else ""))
        failures += not passed
    return int(failures > 0)


if __name__ == "__main__":
    raise SystemExit(main())
