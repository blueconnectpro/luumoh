import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const allowedRoles = new Set([
  'customer',
  'rider',
  'store_admin',
  'rider_admin',
  'admin',
  'super_admin',
]);
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
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

function boolValue(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
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

    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', caller.id)
      .single();
    const callerRole = recordValue(profileData).role;

    if (
      profileError ||
      typeof callerRole !== 'string' ||
      (!fullAdminRoles.has(callerRole) && callerRole !== 'rider_admin')
    ) {
      return jsonResponse({ error: 'Admin access required' }, { status: 403 });
    }

    const body = recordValue(await req.json());
    const email = stringValue(body.email)?.toLowerCase();
    const password = stringValue(body.password);
    const fullName = stringValue(body.fullName);
    const phone = stringValue(body.phone);
    const role = stringValue(body.role);
    const storeId = stringValue(body.storeId);
    const canManageInventory = boolValue(body.canManageInventory, true);
    const canManageOrders = boolValue(body.canManageOrders, true);

    if (!email || !email.includes('@')) {
      return jsonResponse({ error: 'A valid email is required' }, { status: 400 });
    }

    if (!password || password.length < 6) {
      return jsonResponse(
        { error: 'Password must be at least 6 characters' },
        { status: 400 },
      );
    }

    if (!role || !allowedRoles.has(role)) {
      return jsonResponse({ error: 'A valid role is required' }, { status: 400 });
    }

    if (callerRole === 'rider_admin' && role !== 'rider') {
      return jsonResponse(
        { error: 'Rider admins can only create rider accounts' },
        { status: 403 },
      );
    }

    if (!fullName) {
      return jsonResponse({ error: 'Full name is required' }, { status: 400 });
    }

    if (role === 'store_admin' && !storeId) {
      return jsonResponse(
        { error: 'Store admins must be assigned to a store' },
        { status: 400 },
      );
    }

    let userId: string | null = null;
    const { data: usersData, error: usersError } = await supabase.auth.admin
      .listUsers({ page: 1, perPage: 1000 });

    if (usersError) {
      return jsonResponse({ error: usersError.message }, { status: 500 });
    }

    const existingUser = usersData.users.find(
      (user) => user.email?.toLowerCase() === email,
    );

    if (existingUser) {
      if (callerRole === 'rider_admin') {
        const { data: existingProfile, error: existingProfileError } = await supabase
          .from('profiles')
          .select('role')
          .eq('id', existingUser.id)
          .maybeSingle();
        const existingRole = recordValue(existingProfile).role;
        if (
          existingProfileError ||
          (typeof existingRole === 'string' && existingRole !== 'rider')
        ) {
          return jsonResponse(
            { error: 'Rider admins can only update existing rider accounts' },
            { status: 403 },
          );
        }
      }

      userId = existingUser.id;
      const { error: updateError } = await supabase.auth.admin.updateUserById(
        userId,
        {
          email,
          password,
          email_confirm: true,
          user_metadata: { full_name: fullName, phone, role },
        },
      );

      if (updateError) {
        return jsonResponse({ error: updateError.message }, { status: 500 });
      }
    } else {
      const { data: createdData, error: createError } = await supabase.auth.admin
        .createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: { full_name: fullName, phone, role },
        });

      if (createError || !createdData.user) {
        return jsonResponse(
          { error: createError?.message ?? 'User was not created' },
          { status: 500 },
        );
      }

      userId = createdData.user.id;
    }

    const { error: profileUpsertError } = await supabase
      .from('profiles')
      .upsert(
        {
          id: userId,
          role,
          full_name: fullName,
          phone,
        },
        { onConflict: 'id' },
      );

    if (profileUpsertError) {
      return jsonResponse({ error: profileUpsertError.message }, { status: 500 });
    }

    if (role === 'store_admin' && storeId) {
      const { error: membershipError } = await supabase
        .from('store_members')
        .upsert(
          {
            store_id: storeId,
            user_id: userId,
            can_manage_inventory: canManageInventory,
            can_manage_orders: canManageOrders,
          },
          { onConflict: 'store_id,user_id' },
        );

      if (membershipError) {
        return jsonResponse({ error: membershipError.message }, { status: 500 });
      }
    }

    return jsonResponse({ userId, email, role });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
});
