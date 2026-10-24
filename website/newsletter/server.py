"""Loopback newsletter intake API. Run behind the existing nginx vhost."""
import asyncio
from contextlib import asynccontextmanager, suppress
import ipaddress
import json
import os
from pathlib import Path

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from store import InvalidInput, RateLimited, Store, normalize_email, signup_fields


def create_app(directory=None, origins=None, trust_proxy=False):
    store = Store(directory or os.environ.get("NEWSLETTER_STATE_DIR", str(Path.home() / "server/typing-pet-newsletter/state")))
    allowed = set(origins or os.environ.get("NEWSLETTER_ORIGINS", "https://typing-pet.miel.ing").split(","))

    def result(body, status=200, headers=None):
        return JSONResponse(body, status_code=status, headers={
            "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'", **(headers or {})})

    async def health(request):
        try:
            await run_in_threadpool(store.counts)
        except Exception:
            return result({"ok": False}, 503)
        return result({"ok": True})

    async def intake(request: Request):
        if request.headers.get("origin") not in allowed or request.headers.get("sec-fetch-site") == "cross-site":
            return result({"error": "origin"}, 403)
        if request.headers.get("content-type", "").split(";", 1)[0].strip().lower() != "application/json":
            return result({"error": "content_type"}, 415)
        raw = bytearray()
        try:
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > 4096:
                    return result({"error": "too_large"}, 413)
            data = json.loads(raw)
            if not isinstance(data, dict):
                raise InvalidInput("body")
            # A filled honeypot gets a generic success, but never enters the DB.
            if data.get("website"):
                return result({"ok": True}, 202)
            ip = request.client.host if request.client else "unknown"
            if trust_proxy and ipaddress.ip_address(ip).is_loopback:
                ip = str(ipaddress.ip_address(request.headers.get("x-real-ip", ip)))
            if request.url.path.endswith("/subscribe"):
                fields = signup_fields(data)
                await run_in_threadpool(store.subscribe, *fields, ip)
            else:
                email = normalize_email(data.get("email"))
                await run_in_threadpool(store.unsubscribe, email, ip)
        except (InvalidInput, ValueError, UnicodeError) as error:
            field = str(error) if isinstance(error, InvalidInput) else "body"
            return result({"error": "invalid", "field": field}, 400)
        except RateLimited:
            return result({"error": "rate_limited"}, 429, {"Retry-After": "3600"})
        except Exception:
            # Never echo exception strings, submitted fields, or database contents.
            return result({"error": "unavailable"}, 503)
        return result({"ok": True}, 202)

    @asynccontextmanager
    async def lifespan(app):
        async def cleanup():
            while True:
                try:
                    await run_in_threadpool(store.counts)
                except Exception:
                    # Health reports database failures; never log private records.
                    pass
                await asyncio.sleep(3600)
        task = asyncio.create_task(cleanup())
        try:
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    app = Starlette(lifespan=lifespan, routes=[Route("/api/newsletter/health", health, methods=["GET"]),
                            Route("/api/newsletter/subscribe", intake, methods=["POST"]),
                            Route("/api/newsletter/unsubscribe", intake, methods=["POST"])])
    app.state.store = store
    return app


def app_factory():
    return create_app(trust_proxy=os.environ.get("NEWSLETTER_TRUST_PROXY") == "1")
