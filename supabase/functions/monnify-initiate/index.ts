import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import {
  getMonnifyConfig,
  monnifyCheckoutReturnUrl,
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

type OrderRow = {
  id: string;
  customer_id: string;
  total_amount: number;
  status: string;
  payment_status: string;
};

type PaymentRow = {
  id: string;
};

type ReservationRow = {
  id: string;
  expires_at: string;
  active: boolean;
};

function recordValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function paymentReturnUrl(baseUrl: string, orderId: string, paymentReference: string): string {
  const url = new URL(baseUrl);
  url.searchParams.set('orderId', orderId);
  url.searchParams.set('paymentReference', paymentReference);
  url.searchParams.set('source', 'monnify');
  return url.toString();
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
      return jsonResponse(
        { error: 'Unauthorized' },
        { status: 401 },
      );
    }

    const requestBody = recordValue(await req.json());
    const orderId = stringValue(requestBody.orderId);
    if (!orderId) {
      return jsonResponse(
        { error: 'orderId is required' },
        { status: 400 },
      );
    }

    const { data: orderData, error: orderError } = await supabase
      .from('orders')
      .select('id, customer_id, total_amount, status, payment_status')
      .eq('id', orderId)
      .single();
    const order = orderData ? orderData as OrderRow : null;

    if (orderError || !order) {
      return jsonResponse(
        { error: 'Order not found' },
        { status: 404 },
      );
    }

    if (order.customer_id !== userResult.user.id) {
      return jsonResponse(
        { error: 'Forbidden' },
        { status: 403 },
      );
    }

    if (order.payment_status === 'paid') {
      return jsonResponse(
        { error: 'Order is already paid' },
        { status: 409 },
      );
    }

    if (order.status !== 'pending_payment' || order.payment_status !== 'pending') {
      return jsonResponse(
        { error: 'Order is no longer payable' },
        { status: 409 },
      );
    }

    const { data: reservationsData, error: reservationsError } = await supabase
      .from('inventory_reservations')
      .select('id, expires_at, active')
      .eq('order_id', order.id)
      .eq('active', true);
    const reservations = (reservationsData ?? []) as ReservationRow[];

    if (reservationsError) {
      return jsonResponse(
        { error: reservationsError.message },
        { status: 500 },
      );
    }

    const now = Date.now();
    const hasExpiredReservation = reservations.some(
      (reservation) => new Date(reservation.expires_at).getTime() <= now,
    );

    if (reservations.length === 0 || hasExpiredReservation) {
      await supabase
        .from('inventory_reservations')
        .update({ active: false })
        .eq('order_id', order.id)
        .eq('active', true);
      await supabase
        .from('payments')
        .update({ status: 'expired' })
        .eq('order_id', order.id)
        .eq('status', 'pending');
      await supabase
        .from('orders')
        .update({ status: 'cancelled', payment_status: 'expired' })
        .eq('id', order.id);

      return jsonResponse(
        { error: 'Order reservation has expired. Please place the order again.' },
        { status: 409 },
      );
    }

    const paymentReference = `luumoh-${order.id}`;
    const config = getMonnifyConfig();
    const checkoutReturnBaseUrl = monnifyCheckoutReturnUrl(
      config.redirectUrl,
      supabaseUrl,
    );
    const redirectUrl = paymentReturnUrl(
      checkoutReturnBaseUrl,
      order.id,
      paymentReference,
    );

    await supabase
      .from('inventory_reservations')
      .update({ expires_at: new Date(Date.now() + 45 * 60 * 1000).toISOString() })
      .eq('order_id', order.id)
      .eq('active', true);

    const customerName =
      stringValue(userResult.user.user_metadata?.full_name) ?? 'Luumoh Customer';
    const fallbackEmail =
      `customer+${userResult.user.id.replaceAll('-', '')}@luumoh.app`;
    const customerEmail = stringValue(userResult.user.email) ?? fallbackEmail;
    const paymentDescription = `Luumoh order ${order.id}`;

    const { data: paymentData, error: paymentError } = await supabase
      .from('payments')
      .upsert(
        {
          order_id: order.id,
          provider: 'monnify',
          payment_reference: paymentReference,
          amount: order.total_amount,
          status: 'pending',
          checkout_url: null,
          raw_response: {
            source: 'monnify_checkout_sdk',
            amount: order.total_amount,
            currencyCode: 'NGN',
            paymentReference,
            paymentDescription,
            redirectUrl,
          },
        },
        { onConflict: 'payment_reference' },
      )
      .select('id')
      .single();
    const payment = paymentData ? paymentData as PaymentRow : null;

    if (paymentError || !payment) {
      return jsonResponse(
        { error: paymentError?.message ?? 'Payment record was not created' },
        { status: 500 },
      );
    }

    return jsonResponse(
      {
        paymentId: payment.id,
        paymentReference,
        amount: order.total_amount,
        currencyCode: 'NGN',
        apiKey: config.apiKey,
        contractCode: config.contractCode,
        paymentDescription,
        customerName,
        customerEmail,
        redirectUrl,
      },
    );
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
