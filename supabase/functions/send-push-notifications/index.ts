import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-push-secret',
};

type DeliveryRow = {
  delivery_id: string;
  notification_id: string;
  user_id: string;
  device_id: string;
  provider: string;
  device_token: string;
  payload: Record<string, unknown>;
  attempts: number;
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

function numberValue(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function booleanValue(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function stringValue(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function fcmData(data: Record<string, unknown>): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    result[key] = typeof value === 'string' ? value : JSON.stringify(value);
  }
  return result;
}

function jwtRole(token: string): string | null {
  try {
    const parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    let payloadPart = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    while (payloadPart.length % 4 !== 0) {
      payloadPart += '=';
    }
    const payload = JSON.parse(atob(payloadPart));
    return typeof payload.role === 'string' ? payload.role : null;
  } catch (_) {
    return null;
  }
}

async function markDelivery(
  supabase: ReturnType<typeof createClient>,
  deliveryId: string,
  status: 'sent' | 'failed' | 'skipped' | 'pending',
  lastError: string | null,
  response: Record<string, unknown>,
) {
  const { error } = await supabase.rpc('mark_notification_delivery_result', {
    p_delivery_id: deliveryId,
    p_status: status,
    p_last_error: lastError,
    p_response: response,
  });

  if (error) {
    throw new Error(error.message);
  }
}

async function sendFcm(
  delivery: DeliveryRow,
): Promise<{ status: 'sent' | 'failed'; error: string | null; response: Record<string, unknown> }> {
  const serverKey = Deno.env.get('FCM_SERVER_KEY') ?? '';
  if (!serverKey) {
    return {
      status: 'failed',
      error: 'FCM_SERVER_KEY is not configured',
      response: { configured: false },
    };
  }

  const payload = recordValue(delivery.payload);
  const data = recordValue(payload.data);
  const response = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${serverKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: delivery.device_token,
      notification: {
        title: stringValue(payload.title),
        body: stringValue(payload.body),
      },
      data: {
        notification_id: stringValue(payload.notification_id),
        type: stringValue(payload.type),
        ...fcmData(data),
      },
    }),
  });

  const responseBody = recordValue(await response.json().catch(() => ({})));
  if (!response.ok) {
    return {
      status: 'failed',
      error: `FCM request failed with ${response.status}`,
      response: responseBody,
    };
  }

  return { status: 'sent', error: null, response: responseBody };
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, { status: 405 });
    }

    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const dispatchSecret = Deno.env.get('PUSH_DISPATCH_SECRET') ?? '';
    const authorization = req.headers.get('Authorization') ?? '';
    const apiKey = req.headers.get('apikey') ?? '';
    const requestSecret = req.headers.get('x-push-secret') ?? '';
    const bearerToken = authorization.replace('Bearer ', '');

    if (!serviceRoleKey) {
      return jsonResponse({ error: 'SUPABASE_SERVICE_ROLE_KEY is missing' }, { status: 500 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
      {
        global: {
          headers: { Authorization: `Bearer ${serviceRoleKey}` },
        },
      },
    );

    const hasServiceCredential =
      bearerToken === serviceRoleKey ||
      apiKey === serviceRoleKey ||
      jwtRole(bearerToken) === 'service_role' ||
      jwtRole(apiKey) === 'service_role';
    const hasDispatchSecret = Boolean(dispatchSecret) &&
      requestSecret === dispatchSecret;
    let isAuthorized = hasServiceCredential || hasDispatchSecret;

    if (!isAuthorized && bearerToken) {
      const { data: userResult } = await supabase.auth.getUser(bearerToken);
      const userId = userResult.user?.id;
      if (userId) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
        isAuthorized = recordValue(profile).role === 'admin';
      }
    }

    if (!isAuthorized) {
      return jsonResponse({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = recordValue(await req.json().catch(() => ({})));
    const limit = Math.max(1, Math.min(numberValue(body.limit, 25), 100));
    const retryFailed = booleanValue(body.retryFailed, false);
    const cleanupRetentionDays = numberValue(body.cleanupRetentionDays, 0);

    let retried = 0;
    let cleaned = 0;

    if (retryFailed) {
      const { data: retryCount, error: retryError } = await supabase.rpc(
        'retry_failed_notification_deliveries',
        { p_limit: limit, p_max_attempts: 5 },
      );

      if (retryError) {
        return jsonResponse({ error: retryError.message }, { status: 500 });
      }

      retried = typeof retryCount === 'number' ? retryCount : 0;
    }

    if (cleanupRetentionDays > 0) {
      const { data: cleanupCount, error: cleanupError } = await supabase.rpc(
        'cleanup_old_notification_deliveries',
        { p_retention_days: cleanupRetentionDays },
      );

      if (cleanupError) {
        return jsonResponse({ error: cleanupError.message }, { status: 500 });
      }

      cleaned = typeof cleanupCount === 'number' ? cleanupCount : 0;
    }

    const { data, error } = await supabase.rpc(
      'claim_pending_notification_deliveries',
      { p_limit: limit },
    );

    if (error) {
      return jsonResponse({ error: error.message }, { status: 500 });
    }

    const deliveries = (data ?? []) as DeliveryRow[];
    const results = [];

    for (const delivery of deliveries) {
      try {
        if (delivery.provider === 'test') {
          await markDelivery(supabase, delivery.delivery_id, 'sent', null, {
            provider: 'test',
            device_token: delivery.device_token,
          });
          results.push({ id: delivery.delivery_id, provider: 'test', status: 'sent' });
          continue;
        }

        if (delivery.provider === 'fcm') {
          const result = await sendFcm(delivery);
          await markDelivery(
            supabase,
            delivery.delivery_id,
            result.status,
            result.error,
            result.response,
          );
          results.push({
            id: delivery.delivery_id,
            provider: delivery.provider,
            status: result.status,
          });
          continue;
        }

        const message = `${delivery.provider} push dispatch is not configured yet`;
        await markDelivery(supabase, delivery.delivery_id, 'failed', message, {
          provider: delivery.provider,
          configured: false,
        });
        results.push({
          id: delivery.delivery_id,
          provider: delivery.provider,
          status: 'failed',
          error: message,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await markDelivery(supabase, delivery.delivery_id, 'failed', message, {
          provider: delivery.provider,
        });
        results.push({
          id: delivery.delivery_id,
          provider: delivery.provider,
          status: 'failed',
          error: message,
        });
      }
    }

    return jsonResponse({
      claimed: deliveries.length,
      sent: results.filter((result) => result.status === 'sent').length,
      failed: results.filter((result) => result.status === 'failed').length,
      retried,
      cleaned,
      results,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
