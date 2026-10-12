import json
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from dotenv import load_dotenv


DEFAULT_API_URL = "https://YOUR-PROJECT.supabase.co/functions/v1/api"
PAGE_SIZE = 500


def api_url(path):
    load_dotenv()
    base_url = os.environ.get("CARD_EVENTS_API_URL", DEFAULT_API_URL).rstrip("/")
    for suffix in (
        "/api/card-events",
        "/api/plaid-transactions",
        "/api/card-event-reconciliations",
    ):
        if base_url.endswith(suffix):
            base_url = base_url[: -len(suffix)]
            break
    return f"{base_url}{path}"


def bearer_token():
    load_dotenv()
    token = os.environ.get("CARD_EVENTS_BEARER_TOKEN")
    if not token:
        raise RuntimeError(
            "Set CARD_EVENTS_BEARER_TOKEN in the ignored .env file to a "
            "user-linked Supabase session or registered device key."
        )
    return token


def api_request(path, payload=None, query=None):
    url = api_url(path)
    if query:
        url = f"{url}?{urlencode(query)}"
    body = None if payload is None else json.dumps(
        payload,
        default=str,
    ).encode("utf-8")
    request = Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {bearer_token()}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="GET" if payload is None else "POST",
    )

    try:
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        raise RuntimeError(
            f"Cloud API returned HTTP {error.code} for {path}."
        ) from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"Could not complete cloud API request to {path}."
        ) from error


def fetch_all(path, collection):
    results = []
    offset = 0
    while True:
        response = api_request(
            path,
            query={"limit": PAGE_SIZE, "offset": offset},
        )
        rows = response.get(collection) if isinstance(response, dict) else None
        if not isinstance(rows, list):
            raise RuntimeError(
                f"Cloud API response from {path} has no {collection} list."
            )
        results.extend(rows)
        if len(rows) < PAGE_SIZE:
            return results
        offset += len(rows)


def sync_plaid_transactions(added, modified, removed):
    total_saved = 0
    total_removed = 0
    batches = [
        (added, [], []),
        ([], modified, []),
        ([], [], removed),
    ]
    for new_rows, changed_rows, removed_ids in batches:
        size = max(len(new_rows), len(changed_rows), len(removed_ids))
        for start in range(0, size, PAGE_SIZE):
            payload = {
                "added": new_rows[start : start + PAGE_SIZE],
                "modified": changed_rows[start : start + PAGE_SIZE],
                "removed": removed_ids[start : start + PAGE_SIZE],
            }
            result = api_request("/api/plaid-transactions/sync", payload)
            total_saved += result["saved"]
            total_removed += result["removed"]
    return total_saved, total_removed


def save_reconciliations(reconciliations):
    for start in range(0, len(reconciliations), PAGE_SIZE):
        response = api_request(
            "/api/card-event-reconciliations/sync",
            reconciliations[start : start + PAGE_SIZE],
        )
        if response.get("saved") != len(reconciliations[start : start + PAGE_SIZE]):
            raise RuntimeError("Cloud API did not save all reconciliation results.")
