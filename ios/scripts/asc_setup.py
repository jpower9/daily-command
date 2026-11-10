#!/usr/bin/env python3
"""Register the bundle ID and point the App Store Connect app record at it, using the team's
App Store Connect API key (no Apple ID login, no 2FA). Idempotent.

  ASC_KEY_ID=… ASC_ISSUER_ID=… python3 scripts/asc_setup.py [--app-name "Daily Command by ExecClone"]

Key file: $ASC_KEY_PATH or ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. The key never
leaves this machine; only the signed JWT is sent to Apple.
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error

BUNDLE = "com.execclone.dailycommand"
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    # DER SEQUENCE { INTEGER r, INTEGER s } -> r||s, 32 bytes each.
    assert sig[0] == 0x30
    i = 2
    assert sig[i] == 0x02; rl = sig[i + 1]; r = sig[i + 2:i + 2 + rl]; i += 2 + rl
    assert sig[i] == 0x02; sl = sig[i + 1]; s = sig[i + 2:i + 2 + sl]
    return r[-32:].rjust(32, b"\0") + s[-32:].rjust(32, b"\0")


def jwt(key_id: str, issuer: str, key_path: str) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(signing_input); f.flush()
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path, f.name], check=True, capture_output=True).stdout
    os.unlink(f.name)
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def call(token: str, method: str, path: str, body=None):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, (json.loads(r.read() or b"{}") if r.status != 204 else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-name", default="Daily Command by ExecClone")
    ap.add_argument("--sku", default="dailycommand")
    args = ap.parse_args()
    key_id = os.environ.get("ASC_KEY_ID") or sys.exit("ASC_KEY_ID is required")
    issuer = os.environ.get("ASC_ISSUER_ID") or sys.exit("ASC_ISSUER_ID is required")
    key_path = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(key_path):
        sys.exit(f"App Store Connect key not found at {key_path}")
    token = jwt(key_id, issuer, key_path)

    # 1. Bundle ID
    st, res = call(token, "GET", f"/bundleIds?filter[identifier]={BUNDLE}&limit=5")
    if st != 200:
        sys.exit(f"bundleIds lookup failed ({st}): {json.dumps(res)[:300]}")
    exact = [b for b in res.get("data", []) if b["attributes"]["identifier"] == BUNDLE]
    if exact:
        print(f"bundle ID {BUNDLE} already registered ({exact[0]['id']})")
    else:
        st, res = call(token, "POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": BUNDLE, "name": "Daily Command", "platform": "IOS"}}})
        if st not in (200, 201):
            sys.exit(f"bundle ID registration failed ({st}): {json.dumps(res)[:300]}")
        print(f"registered bundle ID {BUNDLE} ({res['data']['id']})")

    # 2. App record
    st, res = call(token, "GET", "/apps?fields[apps]=name,bundleId,sku,primaryLocale&limit=200")
    if st != 200:
        sys.exit(f"apps lookup failed ({st}): {json.dumps(res)[:300]}")
    apps = res.get("data", [])
    for a in apps:
        print(f"  app: {a['attributes']['name']!r}  bundle={a['attributes']['bundleId']}  sku={a['attributes'].get('sku')}  id={a['id']}")
    mine = [a for a in apps if a["attributes"]["bundleId"] == BUNDLE]
    if mine:
        print(f"app record already on {BUNDLE}: {mine[0]['attributes']['name']!r} ({mine[0]['id']}) — ready for upload")
        return
    cands = [a for a in apps if "daily command" in a["attributes"]["name"].lower() or (a["attributes"].get("sku") or "").lower() == args.sku.lower()]
    if not cands:
        sys.exit("No app record named like 'Daily Command' exists, and the App Store Connect API cannot create one. "
                 "Create it once in App Store Connect (New App → bundle ID is now in the dropdown).")
    app = cands[0]
    print(f"retargeting {app['attributes']['name']!r} ({app['id']}) from {app['attributes']['bundleId']} to {BUNDLE}")
    st, res = call(token, "PATCH", f"/apps/{app['id']}", {"data": {"type": "apps", "id": app["id"], "attributes": {"bundleId": BUNDLE}}})
    if st == 200:
        print("done — the app record now uses", BUNDLE)
    else:
        sys.exit(f"could not change the app's bundle ID ({st}): {json.dumps(res)[:400]}\n"
                 "If Apple refuses, the record already has a build or the API does not allow it; "
                 "then it is one click in App Store Connect: app → App Information → Bundle ID.")


if __name__ == "__main__":
    main()
