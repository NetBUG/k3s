# Lambda endpoint for the Navisonic skill

## Why this exists

Amazon builds the skill request and retries it, but **never puts it on the
network** — proven across two hostnames, two skills, several locales and three
independent detectors, with nothing arriving at the Traefik gateway. See
`runs/20261028-2117-navisonic-unable-to-reach-skill.md`.

Lambda invocations travel a different Amazon path, so the skill points at a
Lambda function and the function makes the HTTPS call Amazon will not.

```
Echo -> Alexa -> Lambda (this function) -> https://asknavidrome.nb3.me/ -> pod
```

## The security trade-off, stated plainly

Alexa **signs** HTTPS requests. Lambda invocations carry **no** `Signature` or
`SignatureCertChainUrl` headers, so the forwarded body cannot satisfy
`RequestVerifier` — every request would be rejected with 400.

So `app/sitecustomize.yaml` neutralises that one verifier. After it lands,
**anyone who can reach `asknavidrome.nb3.me` and knows the skill ID can drive
playback.** `TimestampVerifier` (replay protection) and the `NAVI_SKILL_ID`
check still run; the skill ID is a UUID held in SOPS and is the only secret
protecting the endpoint. This was chosen deliberately over a shared-secret
header. If that stops being acceptable, add a header match to
`app/httproute.yaml` and send it from `handler.py`.

## Order of operations

The order matters — getting it wrong produces confusing 400s.

### 1. Land the cluster patch first

```sh
git add apps/asknavidrome/ && git commit && git push
```

Flux applies it and the pod restarts. Confirm the patch loaded:

```sh
ssh sowilo kubectl -n asknavidrome logs deploy/asknavidrome | grep sitecustomize
```

Expect `[sitecustomize] RequestVerifier.verify neutralised for Lambda delivery`.
If that line is missing the patch did **not** apply — stop and fix it, because
every forwarded request will 400.

Sanity-check that verification really is off, from anywhere:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://asknavidrome.nb3.me/ \
  -H 'Content-Type: application/json' --data '{"version":"1.0"}'
```

Before the patch this is `400`. After it, it is no longer a signature
rejection — the body is simply not a valid skill request.

### 2. AWS account

Needed, and there is none yet. <https://portal.aws.amazon.com/billing/signup> —
a payment card is required even on the free tier. This function's usage is far
inside the perpetual free allowance (1M requests/month).

### 3. Create the function

Console -> Lambda -> **Create function** -> *Author from scratch*

| Setting | Value |
|---|---|
| Name | `navisonic-forwarder` |
| Runtime | **Python 3.14** |
| Architecture | `arm64` (cheaper; `x86_64` is fine) |

Paste `handler.py` into `lambda_function.py`, keeping the handler name
`lambda_handler`, and **Deploy**. It is stdlib-only — no packaging, no layers.

Then:

- **Configuration -> Environment variables**:
  `SKILL_ENDPOINT` = `https://asknavidrome.nb3.me/`
  (optionally `TIMEOUT_SECONDS`, default `6`)
- **Configuration -> General configuration -> Timeout**: `8` seconds.
  Alexa abandons the turn at ~8s, so a longer timeout only hides failures.

### 4. Add the Alexa trigger

**Add trigger -> Alexa Skills Kit**, then paste the **Navidrome-home** skill ID
and enable Skill ID verification. Use the real skill, not *Navisonic Test* —
its ID is already in `secret.sops.yaml`, so `NAVI_SKILL_ID` stays correct.

Copy the function **ARN** from the top right.

### 5. Point the skill at it

Developer console -> **Navidrome-home** -> Build -> Endpoint: switch from
**HTTPS** to **AWS Lambda ARN**, paste the ARN into *Default Region*, **Save
Endpoints**, then **Build Model**.

### 6. Verify

Test tab (Development) -> `open navi sonic`. The invocation name on
*Navidrome-home* is two words.

```sh
ssh sowilo kubectl -n asknavidrome logs -f deploy/asknavidrome
```

A `POST / … 200` means the whole chain works — the first inbound request this
skill has ever received. CloudWatch holds the Lambda side if it does not.

## What was actually built (2026-10-29)

Created via **CloudShell** rather than the console code editor: the editor sits
in a cross-origin frame and auto-indent mangles pasted Python. CloudShell is
already authenticated, so no access keys were handled.

| | |
|---|---|
| Region | **eu-west-1** (Ireland) — the Alexa principal is accepted here |
| Function | `navisonic-forwarder`, Python 3.14 |
| Timeout | 8s, `SKILL_ENDPOINT=https://asknavidrome.nb3.me/` |
| Trigger | `add-permission` with principal `alexa-appkit.amazon.com`, statement id `alexa-navidrome-home`, `EventSourceToken` = the Navidrome-home skill ID |

The ARN is on the function page in the console; it embeds the AWS account ID,
so it is deliberately not written down in this public repo.

Source was transferred base64-encoded and verified by sha256 against the local
`handler.py` — the two matched exactly.

Remaining, in order: land the cluster patch (step 1 above), then switch the
skill endpoint from HTTPS to the Lambda ARN (step 5), then verify (step 6).

## Gotcha that bit us: Cloudflare error 1010

The first deploy failed with the skill saying *"There was a problem with the
requested skill's response"*. CloudWatch had the real reason:

```
[ERROR] RuntimeError: AskNavidrome returned 403: Error 1010: Access denied
  "The site owner has blocked access based on your browser's signature"
```

`urllib` sends `User-Agent: Python-urllib/3.x`, and Cloudflare's Browser
Integrity Check rejects exactly that — the same trap
`docs/en/12-asknavidrome-alexa.md` already records for the skill's own Subsonic
calls, which is why the pod pins `music.nb3.me` to the Traefik VIP. The
forwarder therefore sets an explicit `User-Agent`. Any value but the urllib
default passes; measured 2026-10-29.

If this endpoint ever moves behind Cloudflare again under a different name,
check the agent first.

## Tidy-up

- Delete the **Navisonic Test** skill; its endpoint is still pointed at
  `music.nb3.me` from the discriminator test.
- *Navidrome-home*'s HTTPS endpoint is saved without its trailing slash; moot
  once it switches to Lambda.
- `docs/en/12-asknavidrome-alexa.md` still documents the HTTPS endpoint and
  writes the invocation name as "Navisonic" (it is `navi sonic`). Worth
  updating once this works.
- `TZ: Europe/Moscow` in `app/helmrelease.yaml` has no effect in this image —
  pod log timestamps are UTC.
