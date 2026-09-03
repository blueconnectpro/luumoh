import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  fetchWithTimeout,
  getMonnifyConfig,
  monnifyAccessToken,
  sha512Hex,
} from '../_shared/monnify.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, monnify-signature',
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

function recordValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}

function safeJson(rawBody: string): Record<string, unknown> {
  try {
    return recordValue(JSON.parse(rawBody));
  } catch (_) {
    return { rawBody };
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

    const rawBody = await req.text();
    const config = getMonnifyConfig();
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );
    const signature = req.headers.get('monnify-signature') ?? '';
    const expectedSignature = await sha512Hex(`${config.secretKey}${rawBody}`);
    const rawPayload = safeJson(rawBody);

    if (signature.toLowerCase() !== expectedSignature.toLowerCase()) {
      await supabase.from('payment_webhook_events').insert({
        provider: 'monnify',
        signature_valid: false,
        processing_status: 'failed',
        processing_error: 'Invalid signature',
        raw_payload: rawPayload,
      });

      return jsonResponse(
        { error: 'Invalid signature' },
        { status: 401 },
      );
    }

    const payload = rawPayload;
    const eventData = (payload.eventData as Record<string, unknown> | undefined) ??
      payload;
    const eventType = stringValue(payload.eventType) ?? stringValue(payload.event);
    const paymentReference = stringValue(eventData.paymentReference);
    const transactionReference = stringValue(eventData.transactionReference);

    const { data: eventRow } = await supabase
      .from('payment_webhook_events')
      .insert({
        provider: 'monnify',
        payment_reference: paymentReference,
        provider_transaction_reference: transactionReference,
        event_type: eventType,
        payment_status: stringValue(eventData.paymentStatus),
        signature_valid: true,
        processing_status: 'received',
        raw_payload: payload,
      })
      .select('id')
      .single();
    const eventId = (eventRow as { id?: string } | null)?.id;

    async function updateEvent(values: Record<string, unknown>) {
      if (!eventId) {
        return;
      }
      await supabase
        .from('payment_webhook_events')
        .update(values)
        .eq('id', eventId);
    }

    if (!paymentReference) {
      await updateEvent({
        processing_status: 'ignored',
        processing_error: 'Missing paymentReference',
      });

      return jsonResponse(
        { ok: true, ignored: 'missing paymentReference' },
      );
    }

    const token = await monnifyAccessToken(config);
    const queryUrl = new URL(
      '/api/v2/merchant/transactions/query',
      config.baseUrl,
    );
    queryUrl.searchParams.set('paymentReference', paymentReference);

    const verifyResponse = await fetchWithTimeout(
      queryUrl.toString(),
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );

    const verification = await verifyResponse.json();
    if (!verifyResponse.ok) {
      await updateEvent({
        verification_status: verifyResponse.status,
        verification_payload: verification,
        processing_status: 'failed',
        processing_error: 'Verification failed',
      });

      return jsonResponse(
        { error: 'Verification failed', details: verification },
        { status: 502 },
      );
    }

    const verificationBody = verification as Record<string, unknown>;
    const responseBody =
      (verificationBody.responseBody as Record<string, unknown> | undefined) ??
        {};
    const paymentStatus = stringValue(responseBody.paymentStatus) ??
      stringValue(responseBody.status) ??
      stringValue(responseBody.transactionStatus) ??
      stringValue(eventData.paymentStatus) ??
      stringValue(eventData.status) ??
      stringValue(eventData.transactionStatus);
    const amountPaid = Number(
      responseBody.amountPaid ?? eventData.amountPaid ?? 0,
    );

    await updateEvent({
      verification_status: verifyResponse.status,
      verification_payload: verification,
      payment_status: paymentStatus,
      provider_transaction_reference: responseBody.transactionReference ??
        transactionReference ?? null,
    });

    const normalizedStatus = normalizedPaymentOutcome(paymentStatus);

    if (normalizedStatus !== 'paid') {
      if (!normalizedStatus) {
        await updateEvent({
          processing_status: 'ignored',
          processing_error: `Unhandled payment status: ${paymentStatus}`,
        });

        return jsonResponse(
          { ok: true, status: paymentStatus },
        );
      }

      const { error } = await supabase.rpc('record_payment_outcome', {
        p_payment_reference: paymentReference,
        p_provider_transaction_reference: responseBody.transactionReference ??
          transactionReference ?? null,
        p_status: normalizedStatus,
        p_raw_response: verification,
      });

      if (error) {
        await updateEvent({
          processing_status: 'failed',
          processing_error: error.message,
        });

        return jsonResponse(
          { error: error.message },
          { status: 500 },
        );
      }

      await updateEvent({
        processing_status: 'processed',
      });

      return jsonResponse({ ok: true, status: normalizedStatus });
    }

    const { error } = await supabase.rpc('finalize_paid_order', {
      p_payment_reference: paymentReference,
      p_provider_transaction_reference: responseBody.transactionReference ??
        transactionReference ?? null,
      p_amount: amountPaid,
      p_raw_response: verification,
    });

    if (error) {
      await updateEvent({
        processing_status: 'failed',
        processing_error: error.message,
      });

      return jsonResponse(
        { error: error.message },
        { status: 500 },
      );
    }

    await updateEvent({
      processing_status: 'processed',
    });

    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
