"""Forward Alexa Lambda invocations to the in-cluster AskNavidrome endpoint.

Amazon never delivers to our HTTPS endpoint (see
runs/20261028-2117-navisonic-unable-to-reach-skill.md): requests are built and
retried but never reach the gateway, on any hostname. Lambda uses a different
delivery path, so the skill points at this function instead, and this function
does the HTTPS call that Amazon will not.

Alexa signs HTTPS requests; Lambda invocations carry no Signature headers, so
the pod runs with RequestVerifier neutralised (see app/sitecustomize.yaml).
NAVI_SKILL_ID is what keeps the endpoint honest.
"""

import json
import os
import urllib.error
import urllib.request

ENDPOINT = os.environ["SKILL_ENDPOINT"]
# Alexa gives the whole round trip 8s, so give up before it does and let the
# error surface as a skill error rather than a silent timeout.
TIMEOUT = float(os.environ.get("TIMEOUT_SECONDS", "6"))


def lambda_handler(event, context):
    payload = json.dumps(event).encode("utf-8")
    request = urllib.request.Request(
        ENDPOINT,
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            # urllib's default agent is Python-urllib/3.x, which Cloudflare's
            # Browser Integrity Check answers with 403 error 1010 — the same
            # trap docs/en/12-asknavidrome-alexa.md records for the skill's
            # own Subsonic calls. Anything else passes.
            "User-Agent": "navisonic-forwarder/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read()[:300].decode("utf-8", "replace")
        raise RuntimeError(f"AskNavidrome returned {exc.code}: {detail}") from None
    except urllib.error.URLError as exc:
        raise RuntimeError(f"AskNavidrome unreachable: {exc.reason}") from None

    # The skill's JSON response is already an Alexa response envelope,
    # AudioPlayer directives included, so hand it back untouched.
    return json.loads(body)
