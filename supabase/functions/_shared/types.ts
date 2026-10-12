export interface CardEvent {
  event_id?: string;
  occurred_at: string;
  amount: number;
  currency: string;
  merchant: string;
  card_label: string;
  payment_label?: string;
}

export interface DeviceTokenCreate {
  device_label: string;
  person_id?: string;
  platform?: "ios_shortcut" | "android_google_pay";
}

export interface HouseholdPersonCreate {
  display_name: string;
}

export interface TransactionAssignment {
  person_id?: string;
}

export interface DeviceTokenPersonUpdate {
  person_id: string;
}

export interface CycleStartDateUpdate {
  cycle_start_date: string;
}

export interface CreditCardDisplayNameUpdate {
  display_name?: string | null;
}

export interface PlaidPublicTokenExchange {
  public_token: string;
  institution_id?: string;
  institution_name?: string;
  platform?: "android" | "ios" | "web";
}

export interface PlaidTransaction {
  transaction_id: string;
  account_id?: string;
  amount: number;
  iso_currency_code?: string;
  date?: string;
  authorized_date?: string;
  datetime?: string;
  authorized_datetime?: string;
  name?: string;
  original_description?: string;
  merchant_name?: string;
  merchant_entity_id?: string;
  website?: string;
  merchant_category_code?: string;
  payment_channel?: string;
  location_address?: string;
  location_city?: string;
  location_region?: string;
  location_postal_code?: string;
  location_country?: string;
  location_lat?: number;
  location_lon?: number;
  location_store_number?: string;
  personal_finance_category_primary?: string;
  personal_finance_category_detailed?: string;
  personal_finance_category_confidence?: string;
  transaction_type?: string;
  transaction_code?: string;
  pending?: boolean;
  pending_transaction_id?: string;
  counterparties?: Record<string, unknown>[];
  payment_meta?: Record<string, unknown>;
}

export interface PlaidSyncPayload {
  added?: PlaidTransaction[];
  modified?: PlaidTransaction[];
  removed?: string[];
}

export interface CardEventReconciliation {
  event_id: string;
  candidate_transaction_id?: string;
  status: "HIGH" | "MEDIUM" | "AMBIGUOUS" | "REVIEW" | "UNMATCHED" | "PENDING";
  event_amount: number;
  plaid_amount?: number;
  amount_difference?: number;
  details?: Record<string, unknown>;
}

export interface AuthResult {
  userId: string | null;
  authSource: string;
}
