import { getMonnifyConfig } from '../_shared/monnify.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function appReturnUrl(baseUrl: string, requestUrl: URL): string {
  const url = new URL(baseUrl);
  for (const [key, value] of requestUrl.searchParams.entries()) {
    url.searchParams.set(key, value);
  }
  url.searchParams.set('source', 'monnify');
  return url.toString();
}

Deno.serve((req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const requestUrl = new URL(req.url);
  const config = getMonnifyConfig();
  const deepLink = appReturnUrl(config.appReturnUrl, requestUrl);
  const escapedDeepLink = escapeHtml(deepLink);

  return new Response(
    `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Luumoh payment return</title>
    <style>
      body { font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f6f8f5; color: #172019; }
      main { width: min(520px, calc(100vw - 32px)); }
      h1 { font-size: 1.6rem; margin-bottom: .5rem; }
      a { color: #146c43; font-weight: 700; }
      .hint { color: #4f5f55; line-height: 1.5; }
    </style>
  </head>
  <body>
    <main>
      <h1>Returning to Luumoh</h1>
      <p class="hint">Your payment result is being sent back to the app. If it does not open automatically, use the link below.</p>
      <p><a href="${escapedDeepLink}">Open Luumoh tracking</a></p>
    </main>
    <script>
      window.location.href = ${JSON.stringify(deepLink)};
    </script>
  </body>
</html>`,
    {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/html; charset=utf-8',
      },
    },
  );
});
