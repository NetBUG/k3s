"""Runtime patches for the stock ghcr.io/rosskouk/asknavidrome image.

Python imports `sitecustomize` at interpreter startup from anything on
sys.path, and PYTHONPATH is on sys.path first, so this runs before app.py and
patches the shipped image without rebuilding it. Mounted from the ConfigMap
generated out of this directory; see ../kustomization.yaml.

Changing this file needs a pod restart — the interpreter imports it once:
    kubectl -n asknavidrome rollout restart deploy/asknavidrome
"""

import sys


def _patch_request_verifier():
    """Alexa signs HTTPS requests; Lambda invocations carry no Signature or
    SignatureCertChainUrl headers, so RequestVerifier would reject every
    forwarded request with 400. TimestampVerifier (replay protection) and the
    NAVI_SKILL_ID check still run.
    """
    from ask_sdk_webservice_support import verifier

    verifier.RequestVerifier.verify = lambda *args, **kwargs: None
    return 'RequestVerifier.verify neutralised for Lambda delivery'


# Alexa can match an intent while leaving one of its slots unfilled —
# "play songs by X" routes to NaviSonicPlaySongByArtist with `song` empty.
# get_slot_value_v2 then returns None and upstream dereferences it in a debug
# f-string before any search runs, so the handler dies with AttributeError and
# the user hears a generic error. Upstream guards no slot anywhere.
_MISSING_SLOT = "'NoneType' object has no attribute 'value'"

_ADVICE = (
    "Sorry, I missed part of that. Try saying: play music by, and then the "
    "artist. Or: play the album, and then the album name."
)


def _guard(handler):
    """Turn the unfilled-slot crash into speech the user can act on."""
    original = handler.handle

    def handle(handler_input):
        try:
            return original(handler_input)
        except AttributeError as exc:
            if _MISSING_SLOT not in str(exc):
                raise
            print(
                f'[sitecustomize] unfilled slot in {type(handler).__name__}; '
                f'answering with guidance',
                file=sys.stderr,
            )
            builder = handler_input.response_builder
            return builder.speak(_ADVICE).ask(_ADVICE).response

    handler.handle = handle
    return handler


def _patch_slot_guard():
    """Wrap every handler as it is registered.

    Hooking registration rather than the builder's internals keeps this
    independent of where ask-sdk stores handlers, and sitecustomize runs before
    app.py registers anything.
    """
    from ask_sdk_core.skill_builder import SkillBuilder

    original = SkillBuilder.add_request_handler

    def add_request_handler(self, request_handler):
        return original(self, _guard(request_handler))

    SkillBuilder.add_request_handler = add_request_handler
    return 'request handlers wrapped with an unfilled-slot guard'


for _patch in (_patch_request_verifier, _patch_slot_guard):
    try:
        print(f'[sitecustomize] {_patch()}', file=sys.stderr)
    except Exception as _exc:
        print(f'[sitecustomize] {_patch.__name__} FAILED: {_exc!r}', file=sys.stderr)
