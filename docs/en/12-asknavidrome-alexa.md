# 12 — AskNavidrome: the Navidrome library on Alexa

> Result: "Alexa, ask my jukebox to play <artist / album / playlist / genre>"
> plays music from Navidrome on an Echo. The skill stays in development mode
> on our own Amazon account, so it is never certified or published.

## How a request flows

1. The Echo sends the intent to Amazon. Amazon invokes the **Lambda**
   function `navisonic-forwarder` (eu-west-1), which POSTs the event to
   `https://asknavidrome.nb3.me/`. That goes through the Cloudflare tunnel and
   Traefik to the `asknavidrome` pod (`apps/asknavidrome/`).

   Amazon does **not** post to the HTTPS endpoint directly. It builds the
   request and retries it, but never puts it on the network — measured across
   two hostnames, two skills and three detectors on 2026-10-29. Lambda travels
   a different Amazon path and works. See `apps/asknavidrome/lambda/` and
   `runs/20261028-2117-navisonic-unable-to-reach-skill.md`.

   Because Lambda invocations carry no `Signature` headers, the pod runs with
   `RequestVerifier` neutralised (`apps/asknavidrome/app/sitecustomize.yaml`).
   The skill ID in `NAVI_SKILL_ID` is therefore the only secret protecting the
   public endpoint.
2. The skill searches Navidrome through the Subsonic API as the non-admin user
   `alexa`, then answers with a queue of stream URLs:
   `https://music.nb3.me:443/rest/stream.view?...&u=alexa&s=<salt>&t=md5(password+salt)&id=<id>`.
3. The Echo fetches those URLs itself, from the internet. That is why
   Navidrome needs a public hostname, port 443 and a CA-signed certificate.

The pod keeps the play queue in memory. It runs as one replica, and a restart
forgets the current queue.

## Cloudflare blocks the skill's own client

The skill's API calls go to `NAVI_URL`, which must be the public URL because
the same base goes into the stream URLs. In-cluster, `music.nb3.me` resolves to
Cloudflare. Cloudflare's Browser Integrity Check answers the `Python-urllib`
user agent with **403, error 1010**, while curl gets 200 (measured 2026-10-26,
and again on 2026-10-29 — it also bit the Lambda forwarder, which now sends an
explicit `User-Agent`; anything but the urllib default passes). The HelmRelease therefore pins `music.nb3.me` to the Traefik VIP
`192.168.1.100` via `hostAliases`. Traefik serves that name with a verified
certificate, so the calls stay on the LAN.

The Echo's own fetches and Amazon's posts to the skill still go through
Cloudflare. If playback fails with the skill logging no error, check
Cloudflare's Security Events for blocks on those two hostnames, and add a
Configuration Rule that turns off Browser Integrity Check for them.

## Setup

### 1. Navidrome user

`alexa` is a regular, non-admin user. Create it once by hand, because the CLI
reads the password from a terminal:

```sh
ssh -t sowilo 'kubectl -n navidrome exec -it deploy/navidrome -- sh -c "cd /tmp && ND_DATAFOLDER=/data /app/navidrome user create -u alexa --name Alexa"'
```

The password travels in every stream URL Amazon fetches, as a salted MD5. It
can only be the password itself, because the skill recomputes the token for
every track. Use a long random password that nothing else uses.

### 2. Alexa skill

In the [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask):

1. Create a skill: **Custom** model, **Provision your own** backend, in the
   same locale as the Echo. Nothing works if the locales differ.
2. **Interaction Model → JSON Editor**: paste
   [`alexa.json`](https://github.com/rosskouk/asknavidrome/blob/main/alexa.json)
   and build the model.
3. **Interfaces**: enable **Audio Player**.
4. **Endpoint → AWS Lambda ARN**: the ARN of `navisonic-forwarder`. Set the
   function up first — `apps/asknavidrome/lambda/README.md` has the steps.
   (The **HTTPS** option is the obvious choice and does not work; Amazon never
   delivers to it. That is what the Lambda exists to work around.)
5. Copy the skill ID (`amzn1.ask.skill.…`) from the endpoint page.

### 3. Secret

```sh
scripts/set_navisonic_skill.sh
```

It asks for the password and the skill ID and pipes them straight into sops,
encrypted for the cluster's age key (the same recipient as `.sops.yaml`), so
the plaintext never touches disk or shell history. It replaces
`apps/asknavidrome/app/secret.sops.yaml` only after both values come out
encrypted. Re-run it to change either value; `sops
apps/asknavidrome/app/secret.sops.yaml` also opens an editor (values under
`data` are base64).

### 4. Public hostname

Commit and push the app together with `secret.sops.yaml`. The `asknavidrome`
Kustomization fails to build without that file. Once the HTTPRoute is
Accepted, add the tunnel entry to `nb3_tf/terraform.tfvars` under
`k8s_services` and run `tofu apply`. If you apply before the route exists, the
name answers with Traefik's 404.

```hcl
  asknavidrome = {
    hostname = "asknavidrome"
    service  = "https://traefik.traefik.svc.cluster.local:443"
    comment  = "AskNavidrome Alexa skill endpoint"
  }
```

### 5. Navidrome transcoding

The Alexa audio player can't play FLAC. It accepts MP3, AAC/MP4 and HLS at
16–384 kbps. After the first play request, Navidrome lists a player named
**AskNavidrome** under *Settings → Players*. Set its transcoding to MP3 (for
example 320 kbps). Until then, FLAC tracks fail to play.

## Checks

```sh
ssh sowilo kubectl -n asknavidrome logs deploy/asknavidrome | grep -E 'Navidrome|ready'
```

A good start logs `AskNavidrome Web Service is ready to start!` and **no**
`Failed to connect to Navidrome`. A wrong password still starts the web
service and passes the TCP probes. Only that log line shows it.

In the Developer Console, the **Test** tab (set to *Development*) accepts
typed utterances such as `ask my jukebox to play music by <artist>`. It shows the JSON
the skill returned, but plays no audio.

`NAVI_DEBUG: "2"` logs every request and response. Level 3 also serves
`/queue`, `/history` and `/buffer` on the public hostname, so use it only
briefly.

## Phrases that actually work

The grammar is fixed by `alexa.json` — Alexa matches these shapes and little
else. Patterns below are the literal sample utterances; everything in `{}` is a
slot.

The invocation name is **`my jukebox`** (renamed from "navi sonic" on
2026-10-29, which English ASR persistently heard as "never sonic").

### Two-step is far more reliable than one-shot

One-shot ("Alexa, ask my jukebox to play songs by Rammstein") competes with
Alexa's built-in music and often loses — Amazon Music answers instead, with
"I can't find songs by …" (note: AskNavidrome never says that; its misses all
end in "in the collection", which is how you tell who replied).

Inside an open session there is no competition:

```
"Alexa, open my jukebox"      -> "Ready!"
"play songs by Rammstein"
```

### By artist — `play songs by {artist}` / `play music by {artist}`

There is **no** bare "play {artist}". Working examples:

- *play songs by Rammstein*
- *play music by Dragonland*
- *play songs by Accept*
- *play music by The Rasmus*

### A named song — `play {song} by {artist}`

- *play Du Hast by Rammstein*
- *play Amerika by Rammstein*
- *play Breaker by Accept*
- *play Astronomy by Dragonland*

Variants: `play the song {song} by the band {artist}`, `… by the artist {artist}`.

### An album — `play the album {album}` / `play the album {album} by {artist}`

- *play the album Mutter*
- *play the album Rosenrot by Rammstein*
- *play the album Dead Letters by The Rasmus*
- *play the album Holy War by Dragonland*
- *play the album Death Row by Accept*

### By genre — `play {genre} songs` / `play {genre} music`

Tagged genres in this library: Heavy Metal, Power Metal, Industrial Metal,
Gothic Rock, Metal, Industrial, Pop, Rap, Dance, Hip-Hop.

- *play heavy metal music*
- *play power metal songs*

### No slots at all

- *play random music* · *play a mix of songs*
- *play my favourite songs* · *play starred tracks*
- *shuffle* · *randomise the queue*
- *what's playing* · *who sings this* · *which album is this song from*
- *like this song* · *star this song* · *unstar this song*

### What will not work here

- **Playlists.** `play the {playlist} playlist` is supported by the skill, but
  this library's playlists are imported m3u stubs named `list`, `album`,
  `play` and similar, nearly all with 0 songs. Useless until real playlists exist.
- **Cyrillic artists** (БИ-2, Дискотека Авария, Ляпис Трубецкой, Порнофильмы,
  Сурганова) on an English-locale device: English ASR will not produce those
  names. Many are also stored mojibaked (`ÄÈÑÊÎÒÅÊÀ ÀÂÀÐÈß`), so even typed
  matching fails. Fixing the tags is a prerequisite.
- **Albums tagged `[Unknown Album]`** — a large share of the library, including
  most Rammstein singles. Album commands only work for the properly tagged ones
  listed above.

## Making it less painful

- **The invocation name was already renamed** to `my jukebox` (2026-10-29).
  "navi sonic" shares its phonetic shape with "never sonic", and "navi" is not
  an English word so ASR had no prior for it. "jukebox" is phonetically
  distinct, collides with no built-in command, and is also a German loanword —
  which matters on a bilingual account. Changing it again is one build:
  Build → Invocations → Skill Invocation Name, then Build Model. Avoid names
  containing "music", which overlaps Alexa's built-in music commands.
- **Prefer the two-step** open-then-command form over one-shot.
- **Fix the tags** (album names, Cyrillic encoding) — more of the grammar
  becomes usable as metadata improves, with no skill changes at all.
