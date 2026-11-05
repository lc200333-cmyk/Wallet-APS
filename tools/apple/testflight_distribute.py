#!/usr/bin/env python3
"""Hand an uploaded build to TestFlight testers.

Waits until App Store Connect has processed the build, records export
compliance, adds it to the external TestFlight group (the one with the public
link) and submits it for beta review when Apple requires that.

Credentials come only from the environment and are never printed:
ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (path to the AuthKey .p8 file).
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
RETRY_PAUSES = (30, 60, 120, 240, 300)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw_signature(der):
    # openssl emits an ASN.1 SEQUENCE of two INTEGERs (r, s); JWT ES256 needs
    # them as two fixed 32-byte big-endian values.
    index = 2
    parts = []
    for _ in range(2):
        length = der[index + 1]
        value = der[index + 2:index + 2 + length]
        parts.append(value[-32:].rjust(32, b"\0"))
        index += 2 + length
    return parts[0] + parts[1]


def make_token():
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    key_path = os.environ["ASC_KEY_PATH"]
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({
        "iss": issuer,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }).encode())
    message = header + b"." + payload
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=message, capture_output=True, check=True,
    ).stdout
    return (message + b"." + b64url(der_to_raw_signature(der))).decode()


def call(method, path, body=None, allow=()):
    # Every request here is safe to repeat: re-adding a build to a group changes
    # nothing and a repeated review submission is answered with an allowed 409/422.
    attempt = 0
    while True:
        request = urllib.request.Request(
            API + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": "Bearer " + make_token(),
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            if error.code in allow:
                print(f"App Store Connect answered {error.code}: {detail[:500]}")
                return None
            if error.code != 429 and error.code < 500 or attempt >= len(RETRY_PAUSES):
                raise SystemExit(f"{method} {path} failed with {error.code}: {detail[:1000]}")
            problem = f"answered {error.code}"
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt >= len(RETRY_PAUSES):
                raise SystemExit(f"{method} {path} failed: {error}")
            problem = f"failed: {error}"
        pause = RETRY_PAUSES[attempt]
        attempt += 1
        print(f"{method} {path} {problem}; retrying in {pause} seconds.")
        time.sleep(pause)


def query(params):
    return urllib.parse.urlencode(params, safe="[],")


def find_app(bundle_id):
    apps = call("GET", "/v1/apps?" + query({"filter[bundleId]": bundle_id}))["data"]
    if not apps:
        raise SystemExit(f"No App Store Connect app with bundle id {bundle_id}")
    return apps[0]["id"]


def wait_for_build(app_id, platform, version, build_number, timeout):
    params = query({
        "filter[app]": app_id,
        "filter[version]": build_number,
        "filter[preReleaseVersion.version]": version,
        "filter[preReleaseVersion.platform]": platform,
    })
    deadline = time.time() + timeout
    while True:
        builds = call("GET", "/v1/builds?" + params)["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_FOUND"
        print(f"{platform} {version} ({build_number}): {state}")
        if state == "VALID":
            return builds[0]
        if state in ("FAILED", "INVALID"):
            raise SystemExit("App Store Connect rejected the build; see the email from Apple.")
        if time.time() > deadline:
            raise SystemExit("Timed out waiting for App Store Connect to process the build.")
        time.sleep(60)


def find_group(app_id, name):
    groups = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=200")["data"]
    for group in groups:
        if group["attributes"]["name"] == name:
            return group["id"]
    raise SystemExit(f"No TestFlight group named {name!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--platform", required=True, choices=["IOS", "MAC_OS"])
    parser.add_argument("--version", required=True, help="Marketing version, e.g. 0.7.19")
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--group", required=True, help="External TestFlight group name")
    parser.add_argument("--timeout", type=int, default=45 * 60)
    args = parser.parse_args()

    app_id = find_app(args.bundle_id)
    build = wait_for_build(app_id, args.platform, args.version, args.build_number, args.timeout)
    build_id = build["id"]

    # Info.plist declares ITSAppUsesNonExemptEncryption; set it explicitly in
    # case App Store Connect still waits for the answer.
    if build["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/v1/builds/{build_id}", {
            "data": {
                "type": "builds",
                "id": build_id,
                "attributes": {"usesNonExemptEncryption": False},
            }
        })

    group_id = find_group(app_id, args.group)
    call("POST", f"/v1/betaGroups/{group_id}/relationships/builds", {
        "data": [{"type": "builds", "id": build_id}],
    })
    print(f"Added build to TestFlight group {args.group!r}.")

    submitted = call("POST", "/v1/betaAppReviewSubmissions", {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    }, allow=(409, 422))
    if submitted is not None:
        print("Submitted the build for TestFlight beta review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
