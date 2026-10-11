import json
import os
import secrets
from datetime import datetime, timezone
from getpass import getpass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_API_URL = (
    "https://creditcards-beige.vercel.app/api/card-events"
)
ENV_FILE = Path(__file__).with_name(".env.local")


def load_local_env() -> dict[str, str]:
    values = {}
    if not ENV_FILE.exists():
        return values

    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        name, value = line.split("=", 1)
        values[name] = value.strip().strip('"').strip("'")

    return values


def main() -> None:
    local_env = load_local_env()
    api_url = os.environ.get(
        "CARD_EVENTS_API_URL",
        local_env.get("CARD_EVENTS_API_URL") or DEFAULT_API_URL,
    )
    token = os.environ.get(
        "CARD_EVENTS_API_TOKEN",
        local_env.get("CARD_EVENTS_API_TOKEN", ""),
    )

    if not token or "SENSITIVE" in token.upper():
        token = getpass("Enter CARD_EVENTS_API_TOKEN (input hidden): ")
    if not token:
        raise RuntimeError("CARD_EVENTS_API_TOKEN is required.")

    event_id = f"python-test-{secrets.token_hex(8)}"
    event = {
        "event_id": event_id,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "amount": 12.34,
        "currency": "USD",
        "merchant": "Python API Test",
        "card_label": "partner-test",
        "payment_label": "testing",
    }
    request = Request(
        api_url,
        data=json.dumps(event).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(request, timeout=20) as response:
            content_type = response.headers.get("Content-Type", "")
            final_url = response.geturl()
            response_body = response.read().decode("utf-8")
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:500]
        raise RuntimeError(
            f"API returned HTTP {error.code}: {detail}"
        ) from error
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"Could not reach the API: {error}") from error

    if "vercel.com/login" in final_url:
        raise RuntimeError(
            "Vercel redirected to its login page. Disable deployment "
            "protection for this test deployment, then try again."
        )
    if "application/json" not in content_type.lower():
        raise RuntimeError(
            "Expected a JSON API response but received "
            f"{content_type or 'an unknown content type'}."
        )

    try:
        result = json.loads(response_body)
    except json.JSONDecodeError as error:
        raise RuntimeError("API returned invalid JSON.") from error

    if not result.get("ok") or not result.get("saved"):
        raise RuntimeError(f"API did not confirm saving the event: {result}")

    print(f"API accepted and saved event: {event_id}")
    print("Check Supabase Table Editor > card_events for the row.")


if __name__ == "__main__":
    main()
