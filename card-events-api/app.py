import hmac
import hashlib
import json
import logging
import os
import re
import secrets
import unicodedata
from datetime import date, datetime, timezone
from decimal import Decimal
from difflib import SequenceMatcher
from typing import Any, Literal
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from uuid import UUID

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator
import plaid
from plaid.api import plaid_api
from plaid.model.country_code import CountryCode
from plaid.model.item_get_request import ItemGetRequest
from plaid.model.item_public_token_exchange_request import (
    ItemPublicTokenExchangeRequest,
)
from plaid.model.link_token_create_request import LinkTokenCreateRequest
from plaid.model.link_token_create_request_user import LinkTokenCreateRequestUser
from plaid.model.liabilities_get_request import LiabilitiesGetRequest
from plaid.model.products import Products
from plaid.model.accounts_get_request import AccountsGetRequest
from plaid.model.institutions_get_by_id_request import InstitutionsGetByIdRequest
from plaid.model.transactions_sync_request import TransactionsSyncRequest
from plaid.model.transactions_sync_request_options import TransactionsSyncRequestOptions


app = FastAPI()
logger = logging.getLogger(__name__)
LOGIN_PAGE = os.path.join(os.path.dirname(__file__), "login.html")


class CardEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_id: str | None = Field(default=None, min_length=1, max_length=200)
    occurred_at: datetime
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    currency: str = Field(min_length=3, max_length=3)
    merchant: str = Field(min_length=1, max_length=200)
    card_label: str = Field(min_length=1, max_length=100)
    payment_label: str = Field(default="uncategorized", min_length=1, max_length=100)


class DeviceTokenCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    device_label: str = Field(min_length=1, max_length=100)
    person_id: UUID | None = None
    platform: Literal["ios_shortcut", "android_google_pay"] = "ios_shortcut"


class HouseholdPersonCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str = Field(min_length=1, max_length=100)


class TransactionAssignment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    person_id: UUID | None


class DeviceTokenPersonUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    person_id: UUID


class CycleStartDateUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cycle_start_date: date


class CreditCardDisplayNameUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(max_length=100)

    @field_validator("display_name")
    @classmethod
    def normalize_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            raise ValueError("Card name cannot be empty; use null to clear it")
        return normalized


class PlaidPublicTokenExchange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    public_token: str = Field(min_length=1, max_length=2048)
    institution_id: str | None = Field(default=None, max_length=100)
    institution_name: str | None = Field(default=None, max_length=200)
    platform: Literal["android", "ios", "web"] = "web"


PLAID_CREDIT_CARD_NAME_MAPPINGS = {
    "ultimaterewards": "Chase Freedom Unlimited",
}


class PlaidTransaction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    transaction_id: str = Field(min_length=1, max_length=200)
    account_id: str | None = None
    amount: Decimal
    iso_currency_code: str | None = Field(default=None, max_length=3)
    date: str | None = None
    authorized_date: str | None = None
    datetime: str | None = None
    authorized_datetime: str | None = None
    name: str | None = None
    original_description: str | None = None
    merchant_name: str | None = None
    merchant_entity_id: str | None = None
    website: str | None = None
    merchant_category_code: str | None = None
    payment_channel: str | None = None
    location_address: str | None = None
    location_city: str | None = None
    location_region: str | None = None
    location_postal_code: str | None = None
    location_country: str | None = None
    location_lat: Decimal | None = None
    location_lon: Decimal | None = None
    location_store_number: str | None = None
    personal_finance_category_primary: str | None = None
    personal_finance_category_detailed: str | None = None
    personal_finance_category_confidence: str | None = None
    transaction_type: str | None = None
    transaction_code: str | None = None
    pending: bool = False
    pending_transaction_id: str | None = None
    counterparties: list[dict[str, Any]] | None = None
    payment_meta: dict[str, Any] | None = None


class PlaidSyncPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    added: list[PlaidTransaction] = Field(default_factory=list, max_length=500)
    modified: list[PlaidTransaction] = Field(default_factory=list, max_length=500)
    removed: list[str] = Field(default_factory=list, max_length=500)


class CardEventReconciliation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_id: str = Field(min_length=1, max_length=200)
    candidate_transaction_id: str | None = None
    status: Literal["HIGH", "MEDIUM", "AMBIGUOUS", "REVIEW", "UNMATCHED", "PENDING"]
    event_amount: Decimal = Field(gt=0)
    plaid_amount: Decimal | None = None
    amount_difference: Decimal | None = None
    details: dict[str, Any] = Field(default_factory=dict)


def sync_plaid_transaction_page(
    user_id: str,
    added: list,
    modified: list,
    removed: list,
) -> tuple[int, int, int]:
    records = []
    for transaction in [*added, *modified]:
        location = getattr(transaction, "location", None)
        category = getattr(transaction, "personal_finance_category", None)
        counterparties = getattr(transaction, "counterparties", None)
        payment_meta = getattr(transaction, "payment_meta", None)

        def as_iso_string(value):
            return str(value) if value is not None else None

        records.append(
            PlaidTransaction(
                transaction_id=transaction.transaction_id,
                account_id=transaction.account_id,
                amount=transaction.amount,
                iso_currency_code=transaction.iso_currency_code,
                date=as_iso_string(transaction.date),
                authorized_date=as_iso_string(transaction.authorized_date),
                datetime=as_iso_string(transaction.datetime),
                authorized_datetime=as_iso_string(
                    transaction.authorized_datetime
                ),
                name=transaction.name,
                original_description=getattr(
                    transaction,
                    "original_description",
                    None,
                ),
                merchant_name=transaction.merchant_name,
                merchant_entity_id=transaction.merchant_entity_id,
                website=transaction.website,
                merchant_category_code=transaction.merchant_category_code,
                payment_channel=transaction.payment_channel,
                location_address=getattr(location, "address", None),
                location_city=getattr(location, "city", None),
                location_region=getattr(location, "region", None),
                location_postal_code=getattr(location, "postal_code", None),
                location_country=getattr(location, "country", None),
                location_lat=getattr(location, "lat", None),
                location_lon=getattr(location, "lon", None),
                location_store_number=getattr(location, "store_number", None),
                personal_finance_category_primary=getattr(
                    category,
                    "primary",
                    None,
                ),
                personal_finance_category_detailed=getattr(
                    category,
                    "detailed",
                    None,
                ),
                personal_finance_category_confidence=getattr(
                    category,
                    "confidence_level",
                    None,
                ),
                transaction_type=transaction.transaction_type,
                transaction_code=transaction.transaction_code,
                pending=bool(transaction.pending),
                pending_transaction_id=transaction.pending_transaction_id,
                counterparties=[
                    entry.to_dict() if hasattr(entry, "to_dict") else entry
                    for entry in counterparties
                ] if counterparties else None,
                payment_meta=(
                    payment_meta.to_dict()
                    if payment_meta and hasattr(payment_meta, "to_dict")
                    else payment_meta
                ),
            ).model_dump(mode="json")
        )

    supabase_request(
        "POST",
        "plaid_transactions?on_conflict=transaction_id",
        [
            {
                **transaction,
                "user_id": user_id,
                "is_removed": False,
                "synced_at": datetime.now(timezone.utc).isoformat(),
            }
            for transaction in records
        ],
        prefer="resolution=merge-duplicates,return=representation",
    ) if records else []

    removed_count = 0
    for transaction in removed:
        transaction_id = (
            transaction
            if isinstance(transaction, str)
            else transaction.transaction_id
        )
        query = urlencode(
            {
                "transaction_id": f"eq.{transaction_id}",
                "user_id": f"eq.{user_id}",
                "select": "transaction_id",
            }
        )
        updated = supabase_request(
            "PATCH",
            f"plaid_transactions?{query}",
            {
                "is_removed": True,
                "synced_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        removed_count += len(updated)

    return len(added), len(modified), removed_count


def fetch_user_rows(
    table: str,
    user_id: str,
    *,
    active_only: bool = False,
    order_by: str = "transaction_id.asc",
    extra_filters: dict[str, str] | None = None,
) -> list:
    rows = []
    offset = 0
    while True:
        filters = {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": order_by,
            "limit": "500",
            "offset": str(offset),
        }
        if extra_filters:
            filters.update(extra_filters)
        if active_only:
            filters["is_removed"] = "eq.false"
        page = supabase_request(
            "GET",
            f"{table}?{urlencode(filters)}",
        )
        rows.extend(page)
        if len(page) < 500:
            return rows
        offset += len(page)


def ensure_default_person(user_id: str) -> dict:
    existing = supabase_request(
        "GET",
        "household_people?"
        + urlencode({
            "select": "*",
            "user_id": f"eq.{user_id}",
            "is_default": "eq.true",
            "limit": "1",
        }),
    )
    if existing:
        return existing[0]

    profiles = supabase_request(
        "GET",
        "profiles?"
        + urlencode({
            "select": "display_name",
            "id": f"eq.{user_id}",
            "limit": "1",
        }),
    )
    display_name = (
        profiles[0].get("display_name")
        if profiles and profiles[0].get("display_name")
        else "Primary member"
    )
    supabase_request(
        "POST",
        "household_people",
        {
            "user_id": user_id,
            "display_name": display_name,
            "is_default": True,
        },
        prefer="resolution=ignore-duplicates,return=representation",
    )
    existing = supabase_request(
        "GET",
        "household_people?"
        + urlencode({
            "select": "*",
            "user_id": f"eq.{user_id}",
            "is_default": "eq.true",
            "limit": "1",
        }),
    )
    if not existing:
        raise HTTPException(
            status_code=503,
            detail="Could not initialize the household's primary member",
        )
    return existing[0]


def get_household_person(user_id: str, person_id: str) -> dict | None:
    rows = supabase_request(
        "GET",
        "household_people?"
        + urlencode({
            "select": "*",
            "user_id": f"eq.{user_id}",
            "person_id": f"eq.{person_id}",
            "limit": "1",
        }),
    )
    return rows[0] if rows else None


def save_plaid_credit_accounts(
    accounts: list,
    user_id: str,
    item_id: str,
    institution_name: str | None,
) -> int:
    existing_accounts = supabase_request(
        "GET",
        "plaid_credit_accounts?"
        + urlencode({
            "select": "account_id,display_name",
            "user_id": f"eq.{user_id}",
        }),
    )
    existing_display_names = {
        row["account_id"]: row.get("display_name")
        for row in existing_accounts
    }
    account_rows = []
    for account in accounts:
        account_type = getattr(account.type, "value", account.type)
        if account_type != "credit":
            continue
        official_name = getattr(account, "official_name", None)
        name = account.name
        display_name = existing_display_names.get(account.account_id)
        if not display_name:
            display_name = mapped_plaid_credit_card_name(
                official_name,
                name,
            )
        balances = getattr(account, "balances", None)
        account_rows.append({
            "account_id": account.account_id,
            "item_id": item_id,
            "user_id": user_id,
            "name": name,
            "official_name": official_name,
            "display_name": display_name,
            "mask": account.mask,
            "account_type": account_type,
            "subtype": str(
                getattr(account.subtype, "value", account.subtype)
            )
            if account.subtype
            else None,
            "iso_currency_code": (
                balances.iso_currency_code if balances else None
            ),
            "institution_name": institution_name,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })
    for start in range(0, len(account_rows), 500):
        supabase_request(
            "POST",
            "plaid_credit_accounts?on_conflict=account_id",
            account_rows[start : start + 500],
            prefer="resolution=merge-duplicates,return=representation",
        )
    return len(account_rows)


def sync_plaid_credit_accounts(
    client,
    access_token: str,
    user_id: str,
    item_id: str,
    institution_name: str | None,
) -> int:
    response = client.accounts_get(
        AccountsGetRequest(access_token=access_token)
    )
    return save_plaid_credit_accounts(
        response.accounts,
        user_id,
        item_id,
        institution_name,
    )


def sync_plaid_liabilities(
    client,
    access_token: str,
    user_id: str,
    item_id: str | None = None,
    institution_name: str | None = None,
) -> dict:
    try:
        response = client.liabilities_get(
            LiabilitiesGetRequest(access_token=access_token)
        )
    except plaid.ApiException as error:
        try:
            error_body = json.loads(error.body or "{}")
        except (TypeError, json.JSONDecodeError):
            error_body = {}
        code = error_body.get("error_code", "LIABILITIES_UNAVAILABLE")
        logger.warning("Plaid liabilities unavailable: code=%s", code)
        result = {
            "status": "unavailable",
            "reason": code,
            "accounts": 0,
            "statements": 0,
        }
        supabase_request(
            "POST",
            "plaid_liability_sync_state?on_conflict=user_id",
            {
                "user_id": user_id,
                "status": result["status"],
                "account_count": result["accounts"],
                "statement_count": result["statements"],
                "reason": code,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            prefer="resolution=merge-duplicates,return=representation",
        )
        return result

    account_rows = [
        {
            "account_id": account.account_id,
            "iso_currency_code": (
                account.balances.iso_currency_code if account.balances else None
            ),
        }
        for account in response.accounts
        if getattr(account.type, "value", account.type) == "credit"
    ]
    if item_id:
        save_plaid_credit_accounts(
            response.accounts,
            user_id,
            item_id,
            institution_name,
        )

    accounts_by_id = {
        account["account_id"]: account for account in account_rows
    }
    now = datetime.now(timezone.utc).isoformat()
    snapshots = []
    credit_liabilities = response.liabilities.credit or []
    for liability in credit_liabilities:
        account_id = liability.account_id
        account = accounts_by_id.get(account_id)
        issue_date = liability.last_statement_issue_date
        if not account or not issue_date:
            continue
        snapshots.append({
            "user_id": user_id,
            "account_id": account_id,
            "statement_issue_date": issue_date.isoformat(),
            "statement_balance": liability.last_statement_balance,
            "minimum_payment_amount": liability.minimum_payment_amount,
            "next_payment_due_date": (
                liability.next_payment_due_date.isoformat()
                if liability.next_payment_due_date
                else None
            ),
            "iso_currency_code": account["iso_currency_code"],
            "fetched_at": now,
        })
    if snapshots:
        supabase_request(
            "POST",
            "plaid_liability_snapshots?"
            "on_conflict=user_id,account_id,statement_issue_date",
            snapshots,
            prefer="resolution=merge-duplicates,return=representation",
        )
    result = {
        "status": "synced",
        "accounts": len(account_rows),
        "statements": len(snapshots),
    }
    supabase_request(
        "POST",
        "plaid_liability_sync_state?on_conflict=user_id",
        {
            "user_id": user_id,
            "status": result["status"],
            "reason": None,
            "account_count": result["accounts"],
            "statement_count": result["statements"],
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    return result


def refresh_wallet_assignments(user_id: str) -> int:
    events = fetch_user_rows(
        "card_events",
        user_id,
        order_by="event_id.asc",
    )
    reconciliations = fetch_user_rows(
        "card_event_reconciliations",
        user_id,
        order_by="event_id.asc",
    )
    assignments = fetch_user_rows(
        "transaction_assignments",
        user_id,
        order_by="transaction_id.asc",
    )
    event_by_id = {event["event_id"]: event for event in events}
    current_by_tx = {
        row["transaction_id"]: row for row in assignments
    }
    candidates_by_tx = {}
    for result in reconciliations:
        event = event_by_id.get(result["event_id"])
        transaction_id = result.get("candidate_transaction_id")
        if (
            not event
            or not event.get("person_id")
            or not transaction_id
            or result.get("status") not in {"HIGH", "MEDIUM"}
        ):
            continue
        candidates_by_tx.setdefault(transaction_id, []).append(
            (event, result)
        )

    updates = []
    ambiguous_reconciliations = []
    desired_transaction_ids = set()
    now = datetime.now(timezone.utc).isoformat()
    for transaction_id, matches in candidates_by_tx.items():
        current = current_by_tx.get(transaction_id)
        if current and current["assignment_source"] == "manual":
            continue
        if len(matches) != 1:
            if current and current["assignment_source"] == "wallet_event":
                supabase_request(
                    "DELETE",
                    "transaction_assignments?"
                    + urlencode({
                        "transaction_id": f"eq.{transaction_id}",
                        "user_id": f"eq.{user_id}",
                    }),
                )
            for event, reconciliation in matches:
                ambiguous_reconciliations.append({
                    **reconciliation,
                    "status": "AMBIGUOUS",
                    "details": {
                        **(reconciliation.get("details") or {}),
                        "assignment_issue": (
                            "Multiple Wallet events match this Plaid transaction."
                        ),
                    },
                    "updated_at": now,
                })
            continue
        member_ids = {event["person_id"] for event, _ in matches}
        if len(member_ids) != 1:
            continue
        event, _ = matches[0]
        desired_transaction_ids.add(transaction_id)
        updates.append({
            "transaction_id": transaction_id,
            "user_id": user_id,
            "person_id": event["person_id"],
            "assignment_source": "wallet_event",
            "event_id": event["event_id"],
            "updated_at": now,
        })
    for transaction_id, current in current_by_tx.items():
        if (
            current["assignment_source"] == "wallet_event"
            and transaction_id not in desired_transaction_ids
        ):
            supabase_request(
                "DELETE",
                "transaction_assignments?"
                + urlencode({
                    "transaction_id": f"eq.{transaction_id}",
                    "user_id": f"eq.{user_id}",
                }),
            )
    if ambiguous_reconciliations:
        supabase_request(
            "POST",
            "card_event_reconciliations?on_conflict=event_id",
            ambiguous_reconciliations,
            prefer="resolution=merge-duplicates,return=representation",
        )
    for start in range(0, len(updates), 500):
        supabase_request(
            "POST",
            "transaction_assignments?on_conflict=transaction_id",
            updates[start : start + 500],
            prefer="resolution=merge-duplicates,return=representation",
        )
    return len(updates)


def statement_issue_date(value: str | date | None) -> date | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def calculate_statement_summaries(user_id: str) -> int:
    primary = ensure_default_person(user_id)
    people = fetch_user_rows(
        "household_people",
        user_id,
        order_by="created_at.asc,person_id.asc",
    )
    accounts = fetch_user_rows(
        "plaid_credit_accounts",
        user_id,
        order_by="account_id.asc",
    )
    snapshots = fetch_user_rows(
        "plaid_liability_snapshots",
        user_id,
        order_by="account_id.asc,statement_issue_date.asc",
    )
    cycle_start_overrides = fetch_user_rows(
        "card_cycle_start_overrides",
        user_id,
        order_by="account_id.asc,statement_issue_date.asc",
    )
    transactions = fetch_user_rows(
        "plaid_transactions",
        user_id,
        active_only=True,
        order_by="date.asc,transaction_id.asc",
    )
    assignments = fetch_user_rows(
        "transaction_assignments",
        user_id,
        order_by="transaction_id.asc",
    )
    events = fetch_user_rows(
        "card_events",
        user_id,
        order_by="occurred_at.asc,event_id.asc",
    )
    reconciliations = fetch_user_rows(
        "card_event_reconciliations",
        user_id,
        order_by="event_id.asc",
    )

    people_by_id = {person["person_id"]: person for person in people}
    assignment_by_tx = {
        assignment["transaction_id"]: assignment
        for assignment in assignments
    }
    events_by_id = {event["event_id"]: event for event in events}
    reconciliation_by_event = {
        row["event_id"]: row for row in reconciliations
    }
    snapshots_by_account = {}
    for snapshot in snapshots:
        snapshots_by_account.setdefault(snapshot["account_id"], []).append(
            snapshot
        )
    overrides_by_cycle = {
        (
            row["account_id"],
            str(row["statement_issue_date"])[:10],
        ): row
        for row in cycle_start_overrides
    }
    transactions_by_account = {}
    for transaction in transactions:
        if transaction.get("account_id"):
            transactions_by_account.setdefault(
                transaction["account_id"], []
            ).append(transaction)

    summary_rows = []
    now = datetime.now(timezone.utc).isoformat()
    for account in accounts:
        account_id = account["account_id"]
        account_snapshots = snapshots_by_account.get(account_id, [])
        if not account_snapshots:
            continue
        latest = account_snapshots[-1]
        current_issue_date = statement_issue_date(
            latest["statement_issue_date"]
        )
        prior = (
            account_snapshots[-2]
            if len(account_snapshots) > 1
            else None
        )
        prior_issue_date = (
            statement_issue_date(prior["statement_issue_date"])
            if prior
            else None
        )
        cycle_start_source = "plaid"
        manual_override = overrides_by_cycle.get(
            (account_id, str(latest["statement_issue_date"])[:10])
        )
        if not prior_issue_date and manual_override:
            prior_issue_date = statement_issue_date(
                manual_override["cycle_start_date"]
            )
            cycle_start_source = "user_entered"
        base = {
            "user_id": user_id,
            "account_id": account_id,
            "statement_issue_date": latest["statement_issue_date"],
            "cycle_start_date": (
                prior_issue_date.isoformat() if prior_issue_date else None
            ),
            "cycle_end_date": current_issue_date.isoformat(),
            "primary_person_id": primary["person_id"],
            "statement_balance": latest["statement_balance"],
            "updated_at": now,
        }
        if not prior_issue_date:
            summary_rows.append({
                **base,
                "status": "NEEDS_PRIOR_STATEMENT",
                "amount_owed": None,
                "primary_transaction_count": 0,
                "excluded_transaction_count": 0,
                "excluded_amount": Decimal("0"),
                "review_event_count": 0,
                "details": {
                    "reason": (
                        "Enter the prior statement close date to define the "
                        "complete cycle."
                    )
                },
            })
            continue

        primary_total = Decimal("0")
        excluded_total = Decimal("0")
        primary_count = 0
        excluded_count = 0
        review_transaction_ids = set()
        for event_id, reconciliation in reconciliation_by_event.items():
            if reconciliation.get("status") not in {
                "AMBIGUOUS",
                "REVIEW",
                "PENDING",
            }:
                continue
            event = events_by_id.get(event_id)
            if not event or event.get("person_id") is None:
                continue
            event_date = statement_issue_date(event.get("occurred_at"))
            if (
                event_date
                and prior_issue_date < event_date <= current_issue_date
            ):
                candidate_id = reconciliation.get(
                    "candidate_transaction_id"
                )
                if candidate_id:
                    review_transaction_ids.add(candidate_id)

        review_event_ids = set()
        for event_id, event in events_by_id.items():
            event_date = statement_issue_date(event.get("occurred_at"))
            if (
                event.get("person_id")
                and event_date
                and prior_issue_date < event_date <= current_issue_date
            ):
                reconciliation = reconciliation_by_event.get(event_id)
                if not reconciliation or reconciliation.get("status") not in {
                    "HIGH",
                    "MEDIUM",
                }:
                    review_event_ids.add(event_id)

        excluded_non_charge_count = 0
        for transaction in transactions_by_account.get(account_id, []):
            tx_date = statement_issue_date(transaction.get("date"))
            if (
                not tx_date
                or not (prior_issue_date < tx_date <= current_issue_date)
                or transaction.get("pending")
            ):
                continue
            amount = Decimal(str(transaction["amount"]))
            if (
                str(transaction.get("transaction_code") or "").lower()
                == "payment"
                or amount <= 0
            ):
                excluded_non_charge_count += 1
                continue
            explicit = assignment_by_tx.get(transaction["transaction_id"])
            if (
                transaction["transaction_id"] in review_transaction_ids
                and not (
                    explicit
                    and explicit["assignment_source"] == "manual"
                )
            ):
                continue
            assigned_person_id = (
                explicit["person_id"]
                if explicit
                else primary["person_id"]
            )
            if assigned_person_id == primary["person_id"]:
                primary_total += amount
                primary_count += 1
            elif assigned_person_id in people_by_id:
                excluded_total += amount
                excluded_count += 1
        review_count = len(review_event_ids) + len(review_transaction_ids)
        summary_rows.append({
            **base,
            "status": "REVIEW" if review_count else "READY",
            "amount_owed": max(Decimal("0"), primary_total),
            "primary_transaction_count": primary_count,
            "excluded_transaction_count": excluded_count,
            "excluded_amount": excluded_total,
            "review_event_count": review_count,
            "details": {
                "unresolved_event_count": len(review_event_ids),
                "candidate_transaction_review_count": len(
                    review_transaction_ids
                ),
                "excluded_non_charge_count": excluded_non_charge_count,
                "amounts_include_positive_posted_charges_only": True,
                "cycle_start_source": cycle_start_source,
                "primary_charge_total": primary_total,
            },
        })

    for start in range(0, len(summary_rows), 500):
        supabase_request(
            "POST",
            "card_statement_summaries?"
            "on_conflict=user_id,account_id,statement_issue_date",
            summary_rows[start : start + 500],
            prefer="resolution=merge-duplicates,return=representation",
        )
    return len(summary_rows)


GENERIC_CARD_NAMES = {
    "credit card",
    "credit",
    "card",
    "existing linked institution",
    "linked institution",
    "unknown",
}


def is_generic_card_name(val: str | None) -> bool:
    if not val or not isinstance(val, str):
        return True
    return val.strip().lower() in GENERIC_CARD_NAMES


def credit_card_display_name(account: dict[str, Any]) -> str:
    # 1. Custom or mapped display_name override
    display_name = account.get("display_name")
    if isinstance(display_name, str) and display_name.strip():
        return display_name.strip()

    # 2. Institution name backup (e.g. "AAA Visa Signature Credit Card", "Chase")
    institution_name = account.get("institution_name")
    if isinstance(institution_name, str) and not is_generic_card_name(institution_name):
        return institution_name.strip()

    # 3. Fallback with mask
    mask = account.get("mask")
    if isinstance(mask, str) and mask.strip():
        return f"Credit card ••{mask.strip()}"
    return "Credit card"


def mapped_plaid_credit_card_name(
    official_name: str | None,
    name: str | None,
) -> str | None:
    for source_name in (official_name, name):
        if not source_name:
            continue
        key = re.sub(r"[^a-z0-9]", "", source_name.casefold())
        mapped_name = PLAID_CREDIT_CARD_NAME_MAPPINGS.get(key)
        if mapped_name:
            return mapped_name
    return None


def normalize_merchant(value: str | None) -> str:
    if not value:
        return ""
    value = unicodedata.normalize("NFKD", str(value))
    value = value.encode("ascii", "ignore").decode("ascii").lower()
    value = re.sub(r"^(sq|dd|tst|pos|paypal|venmo)\s*\*?\s*", "", value)
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", value)).strip()


def merchant_match_score(event: dict, transaction: dict) -> float:
    event_names = {
        normalize_merchant(event.get("merchant")),
        normalize_merchant(event.get("merchant_name")),
    } - {""}
    transaction_names = {
        normalize_merchant(transaction.get(field))
        for field in ("merchant_name", "name", "original_description")
    } - {""}
    best = 0.0
    for event_name in event_names:
        for transaction_name in transaction_names:
            if event_name == transaction_name:
                return 1.0
            if event_name in transaction_name or transaction_name in event_name:
                best = max(best, 0.9)
            event_words = set(event_name.split())
            transaction_words = set(transaction_name.split())
            if event_words and transaction_words:
                overlap = len(event_words & transaction_words) / len(
                    event_words | transaction_words
                )
                best = max(best, overlap)
                if event_words.issubset(transaction_words):
                    best = max(best, 0.9)
            best = max(
                best,
                SequenceMatcher(None, event_name, transaction_name).ratio(),
            )
    return best


def event_calendar_date(event: dict):
    value = event.get("occurred_at")
    if not value:
        return None
    try:
        return datetime.fromisoformat(
            str(value).replace("Z", "+00:00")
        ).date()
    except ValueError:
        return None


def transaction_calendar_date(transaction: dict):
    for field in ("datetime", "authorized_datetime", "date", "authorized_date"):
        value = transaction.get(field)
        if not value:
            continue
        try:
            return datetime.fromisoformat(
                str(value).replace("Z", "+00:00")
            ).date()
        except ValueError:
            continue
    return None


def reconciliation_candidates(event: dict, transactions: list) -> list:
    candidates = []
    event_date = event_calendar_date(event)
    posted_pending_ids = {
        transaction.get("pending_transaction_id")
        for transaction in transactions
        if not transaction.get("pending")
        and transaction.get("pending_transaction_id")
    }
    for transaction in transactions:
        if (
            transaction.get("pending")
            and transaction.get("transaction_id") in posted_pending_ids
        ):
            continue
        event_currency = event.get("currency")
        transaction_currency = transaction.get("iso_currency_code")
        if (
            event_currency
            and transaction_currency
            and event_currency.upper() != transaction_currency.upper()
        ):
            continue

        try:
            amount_difference = abs(
                Decimal(str(event["amount"]))
                - Decimal(str(transaction["amount"]))
            )
        except (KeyError, ValueError, ArithmeticError):
            continue

        merchant_similarity = merchant_match_score(event, transaction)
        transaction_date = transaction_calendar_date(transaction)
        date_difference = (
            abs((event_date - transaction_date).days)
            if event_date and transaction_date
            else None
        )
        if date_difference is not None and date_difference > 3:
            continue
        if amount_difference > Decimal("0.01") and (
            merchant_similarity < 0.60 or date_difference is None
        ):
            continue

        score = 40 if amount_difference <= Decimal("0.01") else 0
        score += (
            40 if merchant_similarity >= 0.95
            else 30 if merchant_similarity >= 0.80
            else 20 if merchant_similarity >= 0.60
            else 10 if merchant_similarity >= 0.40
            else 0
        )
        score += (
            15 if date_difference == 0
            else 10 if date_difference == 1
            else 5 if date_difference == 2
            else 0
        )
        candidates.append({
            "transaction": transaction,
            "score": score,
            "merchant_similarity": merchant_similarity,
            "date_difference_days": date_difference,
            "amount_difference": amount_difference,
        })

    return sorted(
        candidates,
        key=lambda candidate: (
            not candidate["transaction"].get("pending", False),
            candidate["score"],
            candidate["merchant_similarity"],
            -(
                candidate["date_difference_days"]
                if candidate["date_difference_days"] is not None
                else 999
            ),
        ),
        reverse=True,
    )[:5]


def reconcile_user_card_events(user_id: str) -> int:
    events = fetch_user_rows(
        "card_events",
        user_id,
        order_by="event_id.asc",
    )
    transactions = fetch_user_rows(
        "plaid_transactions",
        user_id,
        active_only=True,
        order_by="transaction_id.asc",
    )
    reconciliations = []
    for event in events:
        candidates = reconciliation_candidates(event, transactions)
        best = candidates[0] if candidates else None
        if best is None:
            status = "UNMATCHED"
        elif best["amount_difference"] > Decimal("0.01"):
            status = "REVIEW"
        elif best["transaction"].get("pending"):
            status = "PENDING"
        elif best["score"] >= 90 and best["merchant_similarity"] >= 0.80:
            status = (
                "HIGH"
                if len(candidates) == 1
                or best["score"] - candidates[1]["score"] >= 15
                else "AMBIGUOUS"
            )
        elif best["score"] >= 70 and best["merchant_similarity"] >= 0.60:
            status = (
                "MEDIUM"
                if len(candidates) == 1
                or best["score"] - candidates[1]["score"] >= 20
                else "AMBIGUOUS"
            )
        else:
            status = "REVIEW"

        transaction = best["transaction"] if best else {}
        reconciliations.append({
            "event_id": event["event_id"],
            "user_id": user_id,
            "candidate_transaction_id": transaction.get("transaction_id"),
            "status": status,
            "event_amount": event["amount"],
            "plaid_amount": transaction.get("amount"),
            "amount_difference": (
                best["amount_difference"] if best else None
            ),
            "details": {
                "reasons": (
                    [
                        "exact amount"
                        if best["amount_difference"] <= Decimal("0.01")
                        else "Plaid posted amount differs; review required",
                        f"merchant similarity {best['merchant_similarity']:.3f}",
                    ]
                    if best
                    else ["no compatible Plaid transaction found"]
                ),
                "candidate_count": len(candidates),
            },
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })

    for start in range(0, len(reconciliations), 500):
        supabase_request(
            "POST",
            "card_event_reconciliations?on_conflict=event_id",
            reconciliations[start : start + 500],
            prefer="resolution=merge-duplicates,return=representation",
        )
    return len(reconciliations)


def run_plaid_sync():
    required = (
        "PLAID_USER_ID",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise HTTPException(
            status_code=503,
            detail="Plaid scheduled sync is missing required configuration",
        )

    user_id = str(UUID(os.environ["PLAID_USER_ID"]))
    return sync_plaid_items_for_user(user_id)


def resolve_institution_name(
    client: plaid_api.PlaidApi, institution_id: str | None
) -> str | None:
    if not institution_id:
        return None
    try:
        response = client.institutions_get_by_id(
            InstitutionsGetByIdRequest(
                institution_id=institution_id,
                country_codes=[CountryCode("US")],
            )
        )
        if response.institution and response.institution.name:
            return response.institution.name
    except Exception:
        logger.warning(
            "Could not resolve institution name for %s", institution_id
        )
    return None


def sync_plaid_items_for_user(
    user_id: str,
) -> dict[str, Any]:
    client = create_plaid_client()
    items = fetch_user_rows(
        "plaid_items",
        user_id,
        order_by="created_at.asc,item_id.asc",
    )
    items = [item for item in items if item.get("status") == "connected"]
    legacy_access_token = os.environ.get("PLAID_ACCESS_TOKEN")
    legacy_user_id = os.environ.get("PLAID_USER_ID")
    if (
        legacy_access_token
        and legacy_user_id
        and str(UUID(legacy_user_id)) == user_id
        and not any(
        item.get("access_token") == legacy_access_token for item in items
        )
    ):
        try:
            legacy_item = client.item_get(
                ItemGetRequest(access_token=legacy_access_token)
            ).item
        except plaid.ApiException as error:
            logger.exception("Could not migrate the existing Plaid connection")
            raise HTTPException(
                status_code=502,
                detail="Could not migrate the existing Plaid connection",
            ) from error
        item_id = legacy_item.item_id
        existing = next(
            (item for item in items if item["item_id"] == item_id),
            None,
        )
        if existing is None:
            inst_name = (
                resolve_institution_name(client, legacy_item.institution_id)
                or "Chase"
            )
            migrated = supabase_request(
                "POST",
                "plaid_items?on_conflict=item_id",
                {
                    "item_id": item_id,
                    "user_id": user_id,
                    "access_token": legacy_access_token,
                    "institution_id": legacy_item.institution_id,
                    "institution_name": inst_name,
                    "status": "connected",
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                prefer="resolution=merge-duplicates,return=representation",
            )
            if not migrated:
                raise HTTPException(
                    status_code=502,
                    detail="Could not save the existing Plaid connection",
                )
            items.append(migrated[0])
    if not items:
        raise HTTPException(
            status_code=503,
            detail="No Plaid connections are available to sync",
        )

    added_count = 0
    modified_count = 0
    removed_count = 0
    liability_account_count = 0
    liability_statement_count = 0
    liability_failures = 0
    for item in items:
        inst_name = item.get("institution_name")
        if (
            not inst_name
            or is_generic_card_name(inst_name)
        ) and item.get("institution_id"):
            resolved = resolve_institution_name(client, item["institution_id"])
            if resolved:
                item["institution_name"] = resolved
                supabase_request(
                    "PATCH",
                    f"plaid_items?item_id=eq.{item['item_id']}",
                    {"institution_name": resolved},
                )
                supabase_request(
                    "PATCH",
                    f"plaid_credit_accounts?item_id=eq.{item['item_id']}&institution_name=in.(Existing linked institution,Linked institution)",
                    {"institution_name": resolved},
                )
        cursor = item.get("transactions_cursor")
        while True:
            request_options = TransactionsSyncRequestOptions(
                include_original_description=True
            )
            request_values: dict[str, Any] = {
                "access_token": item["access_token"],
                "options": request_options,
            }
            if cursor:
                request_values["cursor"] = cursor
            response = client.transactions_sync(
                TransactionsSyncRequest(**request_values)
            )
            saved_added, saved_modified, saved_removed = (
                sync_plaid_transaction_page(
                    user_id,
                    response.added,
                    response.modified,
                    response.removed,
                )
            )
            added_count += saved_added
            modified_count += saved_modified
            removed_count += saved_removed
            cursor = response.next_cursor
            if not response.has_more:
                break
        cursor_query = urlencode({
            "item_id": f"eq.{item['item_id']}",
            "user_id": f"eq.{user_id}",
        })
        supabase_request(
            "PATCH",
            f"plaid_items?{cursor_query}",
            {
                "transactions_cursor": cursor,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        sync_plaid_credit_accounts(
            client,
            item["access_token"],
            user_id,
            item["item_id"],
            item.get("institution_name"),
        )
        liabilities = sync_plaid_liabilities(
            client,
            item["access_token"],
            user_id,
            item["item_id"],
            item.get("institution_name"),
        )
        liability_account_count += liabilities["accounts"]
        liability_statement_count += liabilities["statements"]
        if liabilities["status"] != "synced":
            liability_failures += 1

    liability_status = (
        "synced"
        if liability_statement_count or not liability_failures
        else "unavailable"
    )
    supabase_request(
        "POST",
        "plaid_liability_sync_state?on_conflict=user_id",
        {
            "user_id": user_id,
            "status": liability_status,
            "reason": (
                "LIABILITIES_UNAVAILABLE"
                if liability_status == "unavailable"
                else None
            ),
            "account_count": liability_account_count,
            "statement_count": liability_statement_count,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    reconciled_count = reconcile_user_card_events(user_id)
    assigned_count = refresh_wallet_assignments(user_id)
    summary_count = calculate_statement_summaries(user_id)
    return {
        "ok": True,
        "items_synced": len(items),
        "added": added_count,
        "modified": modified_count,
        "removed": removed_count,
        "reconciled": reconciled_count,
        "wallet_assigned": assigned_count,
        "liabilities": {
            "status": liability_status,
            "accounts": liability_account_count,
            "statements": liability_statement_count,
        },
        "statement_summaries": summary_count,
        "user_id": user_id,
    }


def get_bearer_token(authorization: str | None) -> str:
    scheme, separator, supplied = (authorization or "").partition(" ")
    if not separator or scheme.lower() != "bearer" or not supplied:
        raise HTTPException(status_code=401, detail="Bearer token required")
    return supplied


def verify_supabase_user(token: str) -> str:
    project_url = os.environ.get("SUPABASE_URL")
    publishable_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY")
    if not project_url or not publishable_key:
        raise HTTPException(
            status_code=503,
            detail="Supabase Auth verification is not configured",
        )

    request = Request(
        f"{project_url.rstrip('/')}/auth/v1/user",
        headers={
            "apikey": publishable_key,
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urlopen(request, timeout=10) as response:
            user = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        if error.code in {401, 403}:
            raise HTTPException(
                status_code=401,
                detail="Invalid or expired Supabase session",
            ) from error
        logger.exception("Supabase Auth user verification failed")
        raise HTTPException(
            status_code=502,
            detail="Could not verify Supabase user",
        ) from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        logger.exception("Supabase Auth user verification failed")
        raise HTTPException(
            status_code=502,
            detail="Could not verify Supabase user",
        ) from error

    user_id = user.get("id")
    try:
        verified_user_id = str(UUID(user_id))
    except (ValueError, TypeError, AttributeError):
        raise HTTPException(
            status_code=502,
            detail="Supabase Auth returned an invalid user",
        )
    return verified_user_id


def authenticate_request(authorization: str | None) -> tuple[str | None, str]:
    token = get_bearer_token(authorization)
    test_token = os.environ.get("CARD_EVENTS_API_TOKEN")
    if test_token and hmac.compare_digest(token, test_token):
        return None, "test_api_token"

    try:
        return verify_supabase_user(token), "supabase_auth"
    except HTTPException as error:
        if error.status_code != 401:
            raise

    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    query = urlencode({
        "select": "user_id",
        "token_hash": f"eq.{token_hash}",
        "revoked_at": "is.null",
        "limit": "1",
    })
    rows = supabase_request("GET", f"device_tokens?{query}")
    if rows:
        return rows[0]["user_id"], "device_token"

    raise HTTPException(
        status_code=401,
        detail="Invalid, expired, or revoked bearer token",
    )


def supabase_request(
    method: str,
    query: str,
    body: dict | list | None = None,
    prefer: str | None = None,
) -> list:
    project_url = os.environ.get("SUPABASE_URL")
    secret_key = os.environ.get("SUPABASE_SECRET_KEY")
    if not project_url or not secret_key:
        raise HTTPException(
            status_code=503,
            detail="Database connection is not configured",
        )

    headers = {
        "apikey": secret_key,
        "Authorization": f"Bearer {secret_key}",
        "Content-Type": "application/json",
    }
    if method == "POST":
        headers["Prefer"] = "resolution=ignore-duplicates,return=representation"
    elif method == "PATCH":
        headers["Prefer"] = "return=representation"
    elif method == "DELETE":
        headers["Prefer"] = "return=representation"
    if prefer:
        headers["Prefer"] = prefer

    request = Request(
        f"{project_url.rstrip('/')}/rest/v1/{query}",
        data=json.dumps(body, default=str).encode("utf-8") if body else None,
        headers=headers,
        method=method,
    )

    try:
        with urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        resource = query.partition("?")[0].rsplit("/", 1)[-1]
        try:
            error_payload = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            error_payload = {}
        logger.error(
            "Supabase request rejected: method=%s resource=%s status=%s code=%s message=%s hint=%s",
            method,
            resource,
            error.code,
            error_payload.get("code"),
            error_payload.get("message"),
            error_payload.get("hint"),
        )
        raise HTTPException(
            status_code=502,
            detail="Could not save or read the card event",
        ) from error
    except (URLError, TimeoutError) as error:
        logger.exception("Supabase card event request failed")
        raise HTTPException(
            status_code=502,
            detail="Could not save or read the card event",
        ) from error


@app.get("/")
def health():
    return {"ok": True, "service": "card-events-api"}


@app.get("/api/cron/plaid-sync")
def scheduled_plaid_sync(
    authorization: str | None = Header(default=None),
):
    cron_secret = os.environ.get("CRON_SECRET")
    if not cron_secret:
        raise HTTPException(
            status_code=503,
            detail="Scheduled sync is not configured",
        )
    try:
        supplied = get_bearer_token(authorization)
    except HTTPException as error:
        raise HTTPException(status_code=401, detail="Unauthorized cron request") from error
    if not hmac.compare_digest(supplied, cron_secret):
        raise HTTPException(status_code=401, detail="Unauthorized cron request")

    try:
        return run_plaid_sync()
    except HTTPException:
        raise
    except Exception as error:
        logger.exception("Scheduled Plaid transaction sync failed")
        raise HTTPException(
            status_code=502,
            detail="Scheduled Plaid transaction sync failed; see function logs",
        ) from error


@app.post("/api/cron/plaid-sync")
def trigger_plaid_sync(
    authorization: str | None = Header(default=None),
):
    return scheduled_plaid_sync(authorization)


@app.post("/api/plaid-transactions/sync-now")
def manual_plaid_sync(
    authorization: str | None = Header(default=None),
):
    try:
        user_id, _ = authenticate_request(authorization)
    except HTTPException as error:
        raise HTTPException(status_code=401, detail="Unauthorized") from error
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )

    configured_user_id = os.environ.get("PLAID_USER_ID")
    if not configured_user_id or str(UUID(configured_user_id)) != user_id:
        raise HTTPException(
            status_code=403,
            detail="This account is not configured for Plaid sync",
        )

    try:
        return run_plaid_sync()
    except HTTPException:
        raise
    except Exception as error:
        logger.exception("Manual Plaid transaction sync failed")
        raise HTTPException(
            status_code=502,
            detail="Manual Plaid transaction sync failed; see function logs",
        ) from error


def create_plaid_client():
    environment = os.environ.get("PLAID_ENV", "production").lower()
    plaid_hosts = {
        "production": plaid.Environment.Production,
        "sandbox": plaid.Environment.Sandbox,
    }
    if environment not in plaid_hosts:
        raise HTTPException(
            status_code=503,
            detail="PLAID_ENV must be production or sandbox",
        )
    required = ("PLAID_CLIENT_ID", "PLAID_SECRET")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise HTTPException(
            status_code=503,
            detail="Plaid API credentials are not configured",
        )
    configuration = plaid.Configuration(
        host=plaid_hosts[environment],
        api_key={
            "clientId": os.environ["PLAID_CLIENT_ID"],
            "secret": os.environ["PLAID_SECRET"],
        },
    )
    return plaid_api.PlaidApi(plaid.ApiClient(configuration))


@app.post("/api/plaid/items/link-token")
def create_plaid_item_link_token(
    platform: Literal["android", "ios", "web"] = "web",
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A Supabase session is required to link a bank",
        )
    request_options: dict[str, Any] = {
        "user": LinkTokenCreateRequestUser(client_user_id=user_id),
        "client_name": "Card Household",
        "country_codes": [CountryCode("US")],
        "language": "en",
        "products": [Products("transactions")],
        "optional_products": [Products("liabilities")],
    }
    if platform == "android":
        request_options["android_package_name"] = (
            "com.plaidtest.card_household_app"
        )
    elif platform == "ios" and os.environ.get("PLAID_REDIRECT_URI"):
        request_options["redirect_uri"] = os.environ["PLAID_REDIRECT_URI"]
    elif os.environ.get("PLAID_REDIRECT_URI"):
        request_options["redirect_uri"] = os.environ["PLAID_REDIRECT_URI"]
    try:
        response = create_plaid_client().link_token_create(
            LinkTokenCreateRequest(**request_options)
        )
    except plaid.ApiException as error:
        logger.exception("Could not create Plaid Link session")
        raise HTTPException(
            status_code=502,
            detail="Could not start Plaid Link; see function logs",
        ) from error
    return {"link_token": response.link_token}


@app.post("/api/plaid/items/exchange")
def exchange_plaid_public_token(
    payload: PlaidPublicTokenExchange,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A Supabase session is required to link a bank",
        )
    try:
        client = create_plaid_client()
        exchange = client.item_public_token_exchange(
            ItemPublicTokenExchangeRequest(public_token=payload.public_token)
        )
        item_response = client.item_get(
            ItemGetRequest(access_token=exchange.access_token)
        )
    except plaid.ApiException as error:
        logger.exception("Could not exchange Plaid public token")
        raise HTTPException(
            status_code=502,
            detail="Could not save the Plaid connection; see function logs",
        ) from error

    item_id = item_response.item.item_id
    institution_id = payload.institution_id or item_response.item.institution_id
    institution_name = payload.institution_name or "Linked institution"
    saved = supabase_request(
        "POST",
        "plaid_items?on_conflict=item_id",
        {
            "item_id": item_id,
            "user_id": user_id,
            "access_token": exchange.access_token,
            "institution_id": institution_id,
            "institution_name": institution_name,
            "status": "connected",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    if not saved:
        raise HTTPException(
            status_code=502,
            detail="Plaid linked successfully, but its secure connection "
            "could not be saved",
        )
    sync_result = sync_plaid_items_for_user(user_id)
    return {
        "item_id": item_id,
        "institution_name": institution_name,
        **sync_result,
    }


@app.get("/api/plaid/items")
def list_plaid_items(
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    items = fetch_user_rows(
        "plaid_items",
        user_id,
        order_by="created_at.asc,item_id.asc",
    )
    return {
        "items": [
            {
                "item_id": item["item_id"],
                "institution_id": item.get("institution_id"),
                "institution_name": item.get("institution_name"),
                "status": item["status"],
                "created_at": item["created_at"],
            }
            for item in items
            if item.get("status") != "disconnected"
        ]
    }


@app.post("/api/plaid/items/sync")
def sync_linked_plaid_items(
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    return sync_plaid_items_for_user(user_id)


@app.post("/api/plaid/liabilities/link-token")
def create_liabilities_consent_link_token(
    authorization: str | None = Header(default=None),
):
    try:
        user_id, _ = authenticate_request(authorization)
    except HTTPException as error:
        raise HTTPException(status_code=401, detail="Unauthorized") from error
    configured_user_id = os.environ.get("PLAID_USER_ID")
    access_token = os.environ.get("PLAID_ACCESS_TOKEN")
    if (
        user_id is None
        or not configured_user_id
        or str(UUID(configured_user_id)) != user_id
    ):
        raise HTTPException(
            status_code=403,
            detail="This account is not configured for Plaid",
        )
    if not access_token:
        raise HTTPException(
            status_code=503,
            detail="Plaid connection is not configured",
        )
    environment = os.environ.get("PLAID_ENV", "production").lower()
    plaid_hosts = {
        "production": plaid.Environment.Production,
        "sandbox": plaid.Environment.Sandbox,
    }
    if environment not in plaid_hosts:
        raise HTTPException(
            status_code=503,
            detail="PLAID_ENV must be production or sandbox",
        )
    configuration = plaid.Configuration(
        host=plaid_hosts[environment],
        api_key={
            "clientId": os.environ["PLAID_CLIENT_ID"],
            "secret": os.environ["PLAID_SECRET"],
        },
    )
    client = plaid_api.PlaidApi(plaid.ApiClient(configuration))
    try:
        link_response = client.link_token_create(
            LinkTokenCreateRequest(
                user=LinkTokenCreateRequestUser(client_user_id=user_id),
                client_name="Credit Cards",
                country_codes=[CountryCode("US")],
                language="en",
                access_token=access_token,
                additional_consented_products=[
                    Products("liabilities"),
                ],
            )
        )
    except plaid.ApiException as error:
        logger.exception("Could not create Plaid Liabilities consent session")
        raise HTTPException(
            status_code=502,
            detail="Could not start Plaid statement-data consent; see function logs",
        ) from error
    return {"link_token": link_response.link_token}


@app.get("/api/household/people")
def list_household_people(
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    ensure_default_person(user_id)
    people = fetch_user_rows(
        "household_people",
        user_id,
        order_by="created_at.asc,person_id.asc",
    )
    return {"people": people}


@app.post("/api/household/people")
def create_household_person(
    payload: HouseholdPersonCreate,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    ensure_default_person(user_id)
    people = supabase_request(
        "POST",
        "household_people",
        {
            "user_id": user_id,
            "display_name": payload.display_name.strip(),
            "is_default": False,
        },
    )
    return {"person": people[0]}


@app.patch("/api/device-tokens/{token_id}/person")
def assign_device_token_person(
    token_id: UUID,
    assignment: DeviceTokenPersonUpdate,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(status_code=403, detail="A signed-in user is required")
    person_id = str(assignment.person_id)
    if not get_household_person(user_id, person_id):
        raise HTTPException(status_code=404, detail="Household member not found")
    rows = supabase_request(
        "PATCH",
        "device_tokens?"
        + urlencode({
            "id": f"eq.{token_id}",
            "user_id": f"eq.{user_id}",
            "revoked_at": "is.null",
        }),
        {"person_id": person_id},
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Active device key not found")
    supabase_request(
        "PATCH",
        "card_events?"
        + urlencode({
            "device_token_id": f"eq.{token_id}",
            "user_id": f"eq.{user_id}",
        }),
        {"person_id": person_id},
    )
    refresh_wallet_assignments(user_id)
    calculate_statement_summaries(user_id)
    return {"ok": True, "device_id": str(token_id), "person_id": person_id}


@app.get("/api/owed/statement-cycles")
def list_statement_cycles(
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    ensure_default_person(user_id)
    summaries = fetch_user_rows(
        "card_statement_summaries",
        user_id,
        order_by="statement_issue_date.desc,account_id.asc",
    )
    accounts = fetch_user_rows(
        "plaid_credit_accounts",
        user_id,
        order_by="account_id.asc",
    )
    people = fetch_user_rows(
        "household_people",
        user_id,
        order_by="created_at.asc,person_id.asc",
    )
    liability_states = supabase_request(
        "GET",
        "plaid_liability_sync_state?"
        + urlencode({
            "select": "status,reason,account_count,statement_count,updated_at",
            "user_id": f"eq.{user_id}",
            "limit": "1",
        }),
    )
    account_names = {
        row["account_id"]: credit_card_display_name(row)
        for row in accounts
    }
    latest_by_account = {}
    for summary in summaries:
        latest_by_account.setdefault(summary["account_id"], summary)
    ready_rows = [
        row
        for row in latest_by_account.values()
        if row["status"] in {"READY", "REVIEW"}
        and row["amount_owed"] is not None
    ]
    liability_state = liability_states[0] if liability_states else None
    account_currency = {
        row["account_id"]: row.get("iso_currency_code") or "UNKNOWN"
        for row in accounts
    }
    totals_by_currency = {}
    for row in ready_rows:
        currency = account_currency.get(row["account_id"], "UNKNOWN")
        totals_by_currency[currency] = (
            totals_by_currency.get(currency, Decimal("0"))
            + Decimal(str(row["amount_owed"]))
        )
    total = (
        next(iter(totals_by_currency.values()))
        if len(totals_by_currency) == 1
        else None
    )
    liability_data_current = (
        liability_state is not None
        and liability_state["status"] == "synced"
        and int(liability_state["statement_count"]) > 0
    )
    all_accounts_ready = (
        bool(latest_by_account)
        and len(latest_by_account) == len(accounts)
        and len(ready_rows) == len(latest_by_account)
        and liability_data_current
    )
    if not all_accounts_ready or len(totals_by_currency) != 1:
        total = None
    return {
        "primary_person": next(
            (person for person in people if person["is_default"]),
            None,
        ),
        "accounts": [
            {
                **row,
                "account_name": account_names.get(row["account_id"], "Card"),
                "currency": account_currency.get(row["account_id"], "UNKNOWN"),
            }
            for row in summaries
        ],
        "credit_accounts": [
            {
                **row,
                "account_name": credit_card_display_name(row),
                "plaid_name": row.get("name"),
            }
            for row in accounts
        ],
        "current_total_owed": total,
        "totals_by_currency": totals_by_currency,
        "liabilities": liability_state,
        "total_status": (
            "REVIEW"
            if any(row["status"] == "REVIEW" for row in ready_rows)
            else "WAITING_FOR_STATEMENTS"
            if not all_accounts_ready
            else "MULTI_CURRENCY"
            if len(totals_by_currency) > 1
            else "READY"
            if ready_rows
            else "WAITING_FOR_STATEMENTS"
        ),
    }


@app.patch("/api/plaid-credit-accounts/{account_id}/display-name")
def update_credit_card_display_name(
    account_id: str,
    update: CreditCardDisplayNameUpdate,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    account_query = urlencode({
        "select": "account_id",
        "account_id": f"eq.{account_id}",
        "user_id": f"eq.{user_id}",
        "limit": "1",
    })
    if not supabase_request("GET", f"plaid_credit_accounts?{account_query}"):
        raise HTTPException(status_code=404, detail="Credit card not found")

    update_query = urlencode({
        "account_id": f"eq.{account_id}",
        "user_id": f"eq.{user_id}",
    })
    updated_accounts = supabase_request(
        "PATCH",
        f"plaid_credit_accounts?{update_query}",
        {"display_name": update.display_name},
    )
    if not updated_accounts:
        raise HTTPException(
            status_code=502,
            detail="Could not save the credit card name",
        )
    return {
        "account_id": account_id,
        "display_name": update.display_name,
        "account_name": credit_card_display_name(updated_accounts[0]),
    }


@app.put("/api/plaid-credit-accounts/{account_id}/cycle-start")
def set_statement_cycle_start(
    account_id: str,
    update: CycleStartDateUpdate,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    accounts = supabase_request(
        "GET",
        "plaid_credit_accounts?"
        + urlencode({
            "select": "account_id",
            "account_id": f"eq.{account_id}",
            "user_id": f"eq.{user_id}",
            "limit": "1",
        }),
    )
    if not accounts:
        raise HTTPException(status_code=404, detail="Credit card not found")

    statements = supabase_request(
        "GET",
        "plaid_liability_snapshots?"
        + urlencode({
            "select": "statement_issue_date",
            "account_id": f"eq.{account_id}",
            "user_id": f"eq.{user_id}",
            "order": "statement_issue_date.desc",
            "limit": "1",
        }),
    )
    if not statements:
        raise HTTPException(
            status_code=409,
            detail="Sync statement data before setting the prior statement date",
        )
    current_issue_date = statement_issue_date(
        statements[0]["statement_issue_date"]
    )
    if (
        current_issue_date is None
        or update.cycle_start_date >= current_issue_date
    ):
        raise HTTPException(
            status_code=422,
            detail="Prior statement date must be earlier than the current statement date",
        )

    supabase_request(
        "POST",
        "card_cycle_start_overrides?"
        "on_conflict=user_id,account_id,statement_issue_date",
        {
            "user_id": user_id,
            "account_id": account_id,
            "statement_issue_date": current_issue_date.isoformat(),
            "cycle_start_date": update.cycle_start_date.isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    calculate_statement_summaries(user_id)
    return {
        "ok": True,
        "account_id": account_id,
        "statement_issue_date": current_issue_date.isoformat(),
        "cycle_start_date": update.cycle_start_date.isoformat(),
        "cycle_start_source": "user_entered",
    }


@app.post("/api/plaid-transactions/{transaction_id}/assignment")
def assign_plaid_transaction(
    transaction_id: str,
    assignment: TransactionAssignment,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    primary = ensure_default_person(user_id)
    person_id = str(assignment.person_id) if assignment.person_id else None
    if person_id:
        person = get_household_person(user_id, person_id)
        if not person:
            raise HTTPException(status_code=404, detail="Household member not found")

    transaction_rows = supabase_request(
        "GET",
        "plaid_transactions?"
        + urlencode({
            "select": "transaction_id",
            "transaction_id": f"eq.{transaction_id}",
            "user_id": f"eq.{user_id}",
            "is_removed": "eq.false",
            "limit": "1",
        }),
    )
    if not transaction_rows:
        raise HTTPException(status_code=404, detail="Transaction not found")

    if person_id is None:
        supabase_request(
            "DELETE",
            "transaction_assignments?"
            + urlencode({
                "transaction_id": f"eq.{transaction_id}",
                "user_id": f"eq.{user_id}",
            }),
        )
        calculate_statement_summaries(user_id)
        return {
            "ok": True,
            "transaction_id": transaction_id,
            "person_id": primary["person_id"],
            "assignment_source": "default",
        }

    rows = supabase_request(
        "POST",
        "transaction_assignments?on_conflict=transaction_id",
        {
            "transaction_id": transaction_id,
            "user_id": user_id,
            "person_id": person_id,
            "assignment_source": "manual",
            "event_id": None,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        prefer="resolution=merge-duplicates,return=representation",
    )
    calculate_statement_summaries(user_id)
    return {"ok": True, "assignment": rows[0]}


@app.get("/login")
def login_page():
    return FileResponse(LOGIN_PAGE, media_type="text/html")


@app.get("/api/public-config")
def public_config():
    project_url = os.environ.get("SUPABASE_URL")
    publishable_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY")
    if not project_url or not publishable_key:
        raise HTTPException(
            status_code=503,
            detail="Supabase public client configuration is not configured",
        )
    return {
        "supabase_url": project_url,
        "supabase_publishable_key": publishable_key,
    }


@app.post("/api/card-events")
def create_card_event(
    event: CardEvent,
    authorization: str | None = Header(default=None),
):
    user_id, auth_source = authenticate_request(authorization)
    if event.occurred_at.tzinfo is None:
        raise HTTPException(
            status_code=422,
            detail="occurred_at must include a timezone",
        )

    person_id = None
    device_token_id = None
    event_source = (
        "api_test"
        if auth_source == "test_api_token"
        else (
            "authenticated_api"
            if auth_source != "device_token"
            else "ios_shortcut"
        )
    )
    if user_id and auth_source == "device_token":
        token = get_bearer_token(authorization)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        token_rows = supabase_request(
            "GET",
            "device_tokens?"
            + urlencode({
                "select": "id,person_id,platform",
                "token_hash": f"eq.{token_hash}",
                "user_id": f"eq.{user_id}",
                "revoked_at": "is.null",
                "limit": "1",
            }),
        )
        if token_rows:
            person_id = token_rows[0].get("person_id")
            device_token_id = token_rows[0].get("id")
            event_source = token_rows[0].get("platform") or "ios_shortcut"
    elif user_id:
        person_id = ensure_default_person(user_id)["person_id"]

    rows = supabase_request(
        "POST",
        "card_events?on_conflict=event_id",
        {
            **event.model_dump(mode="json", exclude_none=True),
            "occurred_at": event.occurred_at.astimezone(timezone.utc).isoformat(),
            "user_id": user_id,
            "person_id": person_id,
            "device_token_id": device_token_id,
            "source": event_source,
        },
    )
    return {
        "ok": True,
        "saved": bool(rows),
        "event_id": rows[0]["event_id"] if rows else event.event_id,
        "user_id": user_id,
        "person_id": person_id,
    }


@app.post("/api/plaid-transactions/sync")
def sync_plaid_transactions(
    payload: PlaidSyncPayload,
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )

    rows = [
        {
            **transaction.model_dump(mode="json", exclude_none=True),
            "user_id": user_id,
            "is_removed": False,
            "synced_at": datetime.now(timezone.utc).isoformat(),
        }
        for transaction in [*payload.added, *payload.modified]
    ]
    saved = supabase_request(
        "POST",
        "plaid_transactions?on_conflict=transaction_id",
        rows,
        prefer="resolution=merge-duplicates,return=representation",
    ) if rows else []

    removed = 0
    for transaction_id in payload.removed:
        query = urlencode(
            {
                "transaction_id": f"eq.{transaction_id}",
                "user_id": f"eq.{user_id}",
                "select": "transaction_id",
            }
        )
        rows = supabase_request(
            "PATCH",
            f"plaid_transactions?{query}",
            {
                "is_removed": True,
                "synced_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        removed += len(rows)

    return {
        "ok": True,
        "saved": len(saved),
        "removed": removed,
        "user_id": user_id,
    }


@app.get("/api/plaid-transactions")
def list_plaid_transactions(
    authorization: str | None = Header(default=None),
    limit: int = Query(default=500, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    credit_accounts = fetch_user_rows(
        "plaid_credit_accounts",
        user_id,
        order_by="account_id.asc",
    )
    credit_account_ids = [
        account["account_id"]
        for account in credit_accounts
        if account.get("account_id")
    ]
    if not credit_account_ids:
        return {"transactions": []}

    query = urlencode(
        {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "is_removed": "eq.false",
            "account_id": "in.(" + ",".join(credit_account_ids) + ")",
            "order": "date.desc,transaction_id.asc",
            "limit": str(limit),
            "offset": str(offset),
        }
    )
    transactions = supabase_request("GET", f"plaid_transactions?{query}")
    credit_account_by_id = {
        account["account_id"]: account for account in credit_accounts
    }
    assignments = fetch_user_rows(
        "transaction_assignments",
        user_id,
        order_by="transaction_id.asc",
    )
    assignment_by_id = {
        row["transaction_id"]: row for row in assignments
    }
    primary = ensure_default_person(user_id)
    return {
        "transactions": [
            {
                **transaction,
                "account_name": credit_card_display_name(
                    credit_account_by_id[transaction["account_id"]]
                ),
                "display_name": credit_account_by_id[
                    transaction["account_id"]
                ].get("display_name"),
                "plaid_name": credit_account_by_id[
                    transaction["account_id"]
                ].get("name"),
                "official_name": credit_account_by_id[
                    transaction["account_id"]
                ].get("official_name"),
                "account_mask": credit_account_by_id[
                    transaction["account_id"]
                ].get("mask"),
                "assigned_person_id": (
                    assignment_by_id[transaction["transaction_id"]]["person_id"]
                    if transaction["transaction_id"] in assignment_by_id
                    else primary["person_id"]
                ),
                "assignment_source": (
                    assignment_by_id[transaction["transaction_id"]][
                        "assignment_source"
                    ]
                    if transaction["transaction_id"] in assignment_by_id
                    else "default"
                ),
            }
            for transaction in transactions
            if transaction.get("account_id") in credit_account_by_id
        ]
    }


@app.post("/api/card-event-reconciliations/sync")
def sync_card_event_reconciliations(
    reconciliations: list[CardEventReconciliation],
    authorization: str | None = Header(default=None),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )

    for reconciliation in reconciliations:
        event_query = urlencode(
            {
                "select": "event_id",
                "event_id": f"eq.{reconciliation.event_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            }
        )
        if not supabase_request(
            "GET",
            f"card_events?{event_query}",
        ):
            raise HTTPException(
                status_code=403,
                detail="A reconciliation references an event not owned by this user",
            )
        if reconciliation.candidate_transaction_id:
            transaction_query = urlencode(
                {
                    "select": "transaction_id",
                    "transaction_id": f"eq.{reconciliation.candidate_transaction_id}",
                    "user_id": f"eq.{user_id}",
                    "limit": "1",
                }
            )
            if not supabase_request(
                "GET",
                f"plaid_transactions?{transaction_query}",
            ):
                raise HTTPException(
                    status_code=403,
                    detail="A reconciliation references a transaction not owned by this user",
                )

    rows = [
        {
            **reconciliation.model_dump(mode="json"),
            "user_id": user_id,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        for reconciliation in reconciliations
    ]
    saved = supabase_request(
        "POST",
        "card_event_reconciliations?on_conflict=event_id",
        rows,
        prefer="resolution=merge-duplicates,return=representation",
    ) if rows else []
    return {"ok": True, "saved": len(saved), "user_id": user_id}


@app.get("/api/card-event-reconciliations")
def list_card_event_reconciliations(
    authorization: str | None = Header(default=None),
    limit: int = Query(default=500, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
):
    user_id, _ = authenticate_request(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="A user-linked device key or Supabase session is required",
        )
    query = urlencode(
        {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": "updated_at.desc,event_id.asc",
            "limit": str(limit),
            "offset": str(offset),
        }
    )
    return {
        "reconciliations": supabase_request(
            "GET",
            f"card_event_reconciliations?{query}",
        )
    }


@app.post("/api/device-tokens")
def create_device_token(
    payload: DeviceTokenCreate,
    authorization: str | None = Header(default=None),
):
    bearer_token = get_bearer_token(authorization)
    user_id = verify_supabase_user(bearer_token)
    person_id = (
        str(payload.person_id)
        if payload.person_id
        else ensure_default_person(user_id)["person_id"]
    )
    if not get_household_person(user_id, person_id):
        raise HTTPException(status_code=404, detail="Household member not found")
    device_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(device_token.encode("utf-8")).hexdigest()

    rows = supabase_request(
        "POST",
        "device_tokens",
        {
            "user_id": user_id,
            "person_id": person_id,
            "device_label": payload.device_label,
            "platform": payload.platform,
            "token_hash": token_hash,
        },
    )
    return {
        "device_token": device_token,
        "id": rows[0]["id"],
        "device_label": payload.device_label,
        "person_id": person_id,
        "warning": "Copy this token now; it cannot be retrieved later.",
    }


@app.get("/api/device-tokens")
def list_device_tokens(authorization: str | None = Header(default=None)):
    user_id = verify_supabase_user(get_bearer_token(authorization))
    query = urlencode({
        "select": "id,device_label,person_id,created_at,last_used_at,revoked_at",
        "user_id": f"eq.{user_id}",
        "order": "created_at.desc",
    })
    return {"devices": supabase_request("GET", f"device_tokens?{query}")}


@app.delete("/api/device-tokens/{token_id}")
def revoke_device_token(
    token_id: UUID,
    authorization: str | None = Header(default=None),
):
    user_id = verify_supabase_user(get_bearer_token(authorization))
    query = urlencode({
        "id": f"eq.{token_id}",
        "user_id": f"eq.{user_id}",
        "revoked_at": "is.null",
    })
    rows = supabase_request(
        "PATCH",
        f"device_tokens?{query}",
        {"revoked_at": datetime.now(timezone.utc).isoformat()},
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Active device key not found")
    return {"ok": True, "revoked": True, "id": str(token_id)}


@app.get("/api/card-events")
def list_card_events(
    authorization: str | None = Header(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
):
    user_id, _ = authenticate_request(authorization)
    query = urlencode(
        {
            "select": "event_id,user_id,person_id,occurred_at,amount,currency,merchant,card_label,payment_label,source,received_at",
            "user_id": f"eq.{user_id}" if user_id else "is.null",
            "order": "received_at.desc,event_id.asc",
            "limit": str(limit),
            "offset": str(offset),
        }
    )
    return {"events": supabase_request("GET", f"card_events?{query}")}
