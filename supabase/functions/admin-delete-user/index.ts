import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const fullAdminRoles = new Set(['admin', 'super_admin']);

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
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, { status: 405 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const authHeader = req.headers.get('Authorization') ?? '';
    const accessToken = authHeader.replace('Bearer ', '');

    if (!supabaseUrl || !serviceRoleKey || !accessToken) {
      return jsonResponse({ error: 'Unauthorized' }, { status: 401 });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data: userResult, error: userError } = await supabase.auth.getUser(
      accessToken,
    );
    const caller = userResult.user;
    if (userError || !caller) {
      return jsonResponse({ error: 'Unauthorized' }, { status: 401 });
    }

    const { data: callerProfileData, error: callerProfileError } =
      await supabase
        .from('profiles')
        .select('role')
        .eq('id', caller.id)
        .single();
    const callerRole = recordValue(callerProfileData).role;

    if (
      callerProfileError ||
      typeof callerRole !== 'string' ||
      !fullAdminRoles.has(callerRole)
    ) {
      return jsonResponse({ error: 'Admin access required' }, { status: 403 });
    }

    const body = recordValue(await req.json());
    const userId = stringValue(body.userId);
    if (!userId) {
      return jsonResponse({ error: 'User ID is required' }, { status: 400 });
    }

    if (userId === caller.id) {
      return jsonResponse(
        { error: 'You cannot delete your own account' },
        { status: 400 },
      );
    }

    const { data: targetProfileData, error: targetProfileError } =
      await supabase
        .from('profiles')
        .select('role, full_name')
        .eq('id', userId)
        .maybeSingle();

    if (targetProfileError) {
      return jsonResponse({ error: targetProfileError.message }, { status: 500 });
    }

    const targetProfile = recordValue(targetProfileData);
    const targetRole = targetProfile.role;
    if (typeof targetRole !== 'string') {
      return jsonResponse({ error: 'User profile was not found' }, { status: 404 });
    }

    if (targetRole === 'super_admin' && callerRole !== 'super_admin') {
      return jsonResponse(
        { error: 'Only a super admin can delete a super admin' },
        { status: 403 },
      );
    }

    const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
    if (deleteError) {
      return jsonResponse({ error: deleteError.message }, { status: 500 });
    }

    return jsonResponse({
      userId,
      deleted: true,
      fullName: targetProfile.full_name ?? null,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
