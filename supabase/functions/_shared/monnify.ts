export type MonnifyConfig = {
  baseUrl: string;
  apiKey: string;
  secretKey: string;
  contractCode: string;
  redirectUrl: string;
  appReturnUrl: string;
};

export function getMonnifyConfig(): MonnifyConfig {
  const baseUrl = (
    Deno.env.get('MONNIFY_BASE_URL') ?? 'https://sandbox.monnify.com'
  ).trim().replace(/\/+$/, '');
  const apiKey = (Deno.env.get('MONNIFY_API_KEY') ?? '').trim();
  const secretKey = (Deno.env.get('MONNIFY_SECRET_KEY') ?? '').trim();
  const contractCode = (Deno.env.get('MONNIFY_CONTRACT_CODE') ?? '').trim();
  const redirectUrl = (Deno.env.get('MONNIFY_REDIRECT_URL') ?? '').trim();
  const appReturnUrl = (
    Deno.env.get('MONNIFY_APP_RETURN_URL') ?? 'luumoh://payment-return'
  ).trim();

  if (!apiKey || !secretKey || !contractCode || !redirectUrl) {
    throw new Error('Missing Monnify environment variables');
  }

  return { baseUrl, apiKey, secretKey, contractCode, redirectUrl, appReturnUrl };
}

export function monnifyCheckoutReturnUrl(
  configuredRedirectUrl: string,
  supabaseUrl: string,
): string {
  try {
    const url = new URL(configuredRedirectUrl);
    if (url.protocol === 'http:' || url.protocol === 'https:') {
      return url.toString();
    }
  } catch (_) {
    // Fall back to the hosted return function below.
  }

  if (!supabaseUrl) {
    throw new Error('SUPABASE_URL is required for Monnify checkout return URL');
  }

  return `${supabaseUrl.replace(/\/$/, '')}/functions/v1/monnify-return`;
}

export async function monnifyAccessToken(config: MonnifyConfig): Promise<string> {
  const credentials = btoa(`${config.apiKey}:${config.secretKey}`);
  const response = await fetchWithTimeout(`${config.baseUrl}/api/v1/auth/login`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${credentials}`,
    },
  });

  if (!response.ok) {
    throw new Error(
      `Monnify auth failed: ${response.status} ${await response.text()}`,
    );
  }

  const payload = await response.json();
  const token = payload?.responseBody?.accessToken;
  if (!token) {
    throw new Error('Monnify auth response did not include accessToken');
  }

  return token;
}

export async function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit = {},
  timeoutMs = 20000,
): Promise<Response> {
  const signal = init.signal ?? AbortSignal.timeout(timeoutMs);
  try {
    return await fetch(input, { ...init, signal });
  } catch (error) {
    if (
      error instanceof DOMException &&
      (error.name === 'TimeoutError' || error.name === 'AbortError')
    ) {
      throw new Error('Monnify request timed out. Please verify the payment again.');
    }
    throw error;
  }
}

export async function sha512Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-512', data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
