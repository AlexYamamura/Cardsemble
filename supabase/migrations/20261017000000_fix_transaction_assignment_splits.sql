-- 20261017000000_fix_transaction_assignment_splits.sql
-- Contract: amount IS NULL for a single/default assignment;
--           amount > 0 for each split share.
-- Apply before deploying the updated edge function.

alter table public.transaction_assignments
    add column if not exists amount numeric(12, 2);

alter table public.transaction_assignments
    drop constraint if exists transaction_assignments_amount_positive;
alter table public.transaction_assignments
    add constraint transaction_assignments_amount_positive
    check (amount is null or amount > 0);

do $$
declare
    pk_name text;
begin
    if exists (
        select 1
        from public.transaction_assignments
        group by transaction_id, person_id
        having count(*) > 1
    ) then
        raise exception
            'Duplicate (transaction_id, person_id) rows must be resolved before applying the split key';
    end if;

    select conname
      into pk_name
      from pg_constraint
     where conrelid = 'public.transaction_assignments'::regclass
       and contype = 'p';

    if pk_name is not null then
        execute format(
            'alter table public.transaction_assignments drop constraint %I',
            pk_name
        );
    end if;

    alter table public.transaction_assignments
        add constraint transaction_assignments_pkey
        primary key (transaction_id, person_id);
end
$$;

create index if not exists transaction_assignments_user_transaction_idx
    on public.transaction_assignments (user_id, transaction_id);

grant insert (
    transaction_id, user_id, person_id, amount,
    assignment_source, event_id, updated_at
) on table public.transaction_assignments to authenticated;