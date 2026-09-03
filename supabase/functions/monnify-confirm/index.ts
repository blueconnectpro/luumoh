import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  fetchWithTimeout,
  getMonnifyConfig,
  monnifyAccessToken,
} from '../_shared/monnify.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(corsHeaders);
  headers.set('Content-Type', 'application/json');

  if (init.headers) {
    new Headers(init.headers).forEach((value, key) => {
      headers.set(key, value);
    });
  }

  return new Response(JSON.stringify(body), {
    ...init,
    headers,
  });
}

function recordValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function normalizedPaymentOutcome(status: string | null): string | null {
  switch ((status ?? '').toUpperCase()) {
    case 'PAID':
    case 'OVERPAID':
    case 'SUCCESS':
    case 'SUCCESSFUL':
      return 'paid';
    case 'FAILED':
    case 'FAILURE':
      return 'failed';
    case 'EXPIRED':
    case 'CANCELLED':
    case 'CANCELED':
      return 'expired';
    case 'REFUNDED':
    case 'REVERSED':
      return 'refunded';
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const authHeader = req.headers.get('Authorization') ?? '';
    const accessToken = authHeader.replace('Bearer ', '');
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: userResult, error: userError } = await supabase.auth.getUser(
      accessToken,
    );
    if (userError || !userResult.user) {
      return jsonResponse({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = recordValue(await req.json());
    const orderId = stringValue(body.orderId);
    let paymentReference = stringValue(body.paymentReference);

    if (!orderId && !paymentReference) {
      return jsonResponse(
        { error: 'orderId or paymentReference is required' },
        { status: 400 },
      );
    }

    let paymentQuery = supabase
      .from('payments')
      .select('id, order_id, payment_reference, status, amount, orders!inner(customer_id)')
      .limit(1);

    if (paymentReference) {
      paymentQuery = paymentQuery.eq('payment_reference', paymentReference);
    } else {
      paymentQuery = paymentQuery.eq('order_id', orderId);
    }

    const { data: paymentRows, error: paymentError } = await paymentQuery;
    const payment = (paymentRows?.[0] ?? null) as Record<string, unknown> | null;

    if (paymentError || !payment) {
      return jsonResponse(
        { error: paymentError?.message ?? 'Payment record not found' },
        { status: 404 },
      );
    }

    const order = recordValue(payment.orders);
    if (order.customer_id !== userResult.user.id) {
      return jsonResponse({ error: 'Forbidden' }, { status: 403 });
    }

    paymentReference = stringValue(payment.payment_reference);
    if (!paymentReference) {
      return jsonResponse(
        { error: 'Payment record has no payment reference' },
        { status: 500 },
      );
    }

    if (payment.status === 'paid') {
      return jsonResponse({
        ok: true,
        paymentReference,
        paymentStatus: 'paid',
        alreadyProcessed: true,
      });
    }

    const config = getMonnifyConfig();
    const token = await monnifyAccessToken(config);
    const queryUrl = new URL(
      '/api/v2/merchant/transactions/query',
      config.baseUrl,
    );
    queryUrl.searchParams.set('paymentReference', paymentReference);

    const verifyResponse = await fetchWithTimeout(queryUrl.toString(), {
      headers: { Authorization: `Bearer ${token}` },
    });
    const verification = await verifyResponse.json();

    if (!verifyResponse.ok) {
      return jsonResponse(
        { error: 'Verification failed', details: verification },
        { status: 502 },
      );
    }

    const responseBody = recordValue(recordValue(verification).responseBody);
    const providerStatus =
      stringValue(responseBody.paymentStatus) ??
      stringValue(responseBody.status) ??
      stringValue(responseBody.transactionStatus);
    const normalizedStatus = normalizedPaymentOutcome(providerStatus);
    const transactionReference = stringValue(responseBody.transactionReference);
    const amountPaid = Number(responseBody.amountPaid ?? responseBody.amount ?? 0);

    await supabase.from('payment_webhook_events').insert({
      provider: 'monnify',
      payment_reference: paymentReference,
      provider_transaction_reference: transactionReference,
      event_type: 'app_confirm',
      payment_status: providerStatus,
      signature_valid: true,
      verification_status: verifyResponse.status,
      processing_status: normalizedStatus ? 'processed' : 'ignored',
      processing_error: normalizedStatus
        ? null
        : `Unhandled payment status: ${providerStatus}`,
      raw_payload: { source: 'customer_app_confirm' },
      verification_payload: verification,
    });

    if (normalizedStatus === 'paid') {
      const { error } = await supabase.rpc('finalize_paid_order', {
        p_payment_reference: paymentReference,
        p_provider_transaction_reference: transactionReference,
        p_amount: amountPaid,
        p_raw_response: verification,
      });

      if (error) {
        return jsonResponse({ error: error.message }, { status: 500 });
      }

      return jsonResponse({
        ok: true,
        paymentReference,
        paymentStatus: 'paid',
      });
    }

    if (normalizedStatus) {
      const { error } = await supabase.rpc('record_payment_outcome', {
        p_payment_reference: paymentReference,
        p_provider_transaction_reference: transactionReference,
        p_status: normalizedStatus,
        p_raw_response: verification,
      });

      if (error) {
        return jsonResponse({ error: error.message }, { status: 500 });
      }

      return jsonResponse({
        ok: true,
        paymentReference,
        paymentStatus: normalizedStatus,
      });
    }

    return jsonResponse({
      ok: true,
      paymentReference,
      paymentStatus: 'pending',
      providerStatus,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
