create table if not exists public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'monnify',
  payment_reference text,
  provider_transaction_reference text,
  event_type text,
  payment_status text,
  signature_valid boolean not null default false,
  verification_status integer,
  processing_status text not null default 'received'
    check (processing_status in ('received', 'ignored', 'processed', 'failed')),
  processing_error text,
  raw_payload jsonb not null default '{}'::jsonb,
  verification_payload jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payment_webhook_events_reference_idx
  on public.payment_webhook_events(payment_reference, created_at desc);

create index if not exists payment_webhook_events_status_idx
  on public.payment_webhook_events(processing_status, created_at desc);

alter table public.payment_webhook_events enable row level security;

drop policy if exists "payment webhook events admin read" on public.payment_webhook_events;
create policy "payment webhook events admin read" on public.payment_webhook_events
for select using (public.is_admin());

create or replace view public.payment_webhook_event_summaries
with (security_invoker = true)
as
select
  pwe.id,
  pwe.provider,
  pwe.payment_reference,
  pwe.provider_transaction_reference,
  pwe.event_type,
  pwe.payment_status,
  pwe.signature_valid,
  pwe.verification_status,
  pwe.processing_status,
  pwe.processing_error,
  pwe.created_at,
  p.id as payment_id,
  p.order_id,
  o.store_id,
  s.name as store_name
from public.payment_webhook_events pwe
left join public.payments p on p.payment_reference = pwe.payment_reference
left join public.orders o on o.id = p.order_id
left join public.stores s on s.id = o.store_id;

grant select on public.payment_webhook_events to authenticated;
grant select on public.payment_webhook_event_summaries to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.payment_webhook_events;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
