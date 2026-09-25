import { adjust, isConfigured } from './revenuecat.js';

/**
 * **La cuenta de cada usuario, una y solo una.**
 *
 * Antes la app abría una sesión anónima y cada instalación —y a veces cada
 * arranque— era un usuario nuevo de Appwrite: imposible saber quién gasta qué
 * ni regalarle nada. Ahora el usuario tiene un id **estable** que decide la
 * app —el de su cuenta de iCloud, o uno guardado en el llavero que sobrevive a
 * reinstalar— y ese mismo id es su cliente de RevenueCat. Ver `StableIdentity`.
 *
 * Acciones:
 *
 * - `auth` (sin sesión): crea el usuario si no existe, le da el regalo de
 *   bienvenida una vez, y devuelve un token de un solo uso con el que la app
 *   abre **su** sesión.
 * - `pending` (con sesión): los regalos por reclamar de quien llama.
 * - `claim` (con sesión): reclama uno — lo suma en RevenueCat y lo marca.
 * - Y como disparador: cuando se crea un regalo en el panel, avisa por push al
 *   usuario (silencioso siempre; con alerta si tiene los avisos activados).
 */

const DATABASE = 'snazzy';
const GRANTS = 'grants';
/** Lo que se regala al llegar: una mejora. */
const WELCOME = { MEJ: 1 };
/** `ck` + 32 hex (iCloud) o `kc` + 32 hex (llavero). Nada que se adivine. */
const USER_ID = /^(ck|kc)[0-9a-f]{32}$/;

export default async ({ req, res, log, error }) => {
  const api = appwrite(req.headers['x-appwrite-key']);

  // **Disparado por un regalo nuevo en el panel.**
  if (req.headers['x-appwrite-trigger'] === 'event') {
    const grant = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body;
    try {
      await notifyGrant(api, grant, log);
    } catch (err) {
      error(`aviso del regalo ${grant?.$id}: ${err}`);
    }
    return res.json({ ok: true });
  }

  let body = {};
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  } catch {
    return res.json({ error: 'bad_request' }, 400);
  }
  const caller = req.headers['x-appwrite-user-id'];

  try {
    switch (body.action) {
      case 'auth':
        return res.json(await authenticate(api, body.userId, log, error));
      case 'pending':
        if (!caller) return res.json({ error: 'no_session' }, 401);
        return res.json({ grants: await pendingGrants(api, caller) });
      case 'claim':
        if (!caller) return res.json({ error: 'no_session' }, 401);
        return res.json(await claim(api, caller, body.grantId, log));
      default:
        return res.json({ error: 'unknown_action' }, 400);
    }
  } catch (err) {
    if (err.status && err.expose) return res.json({ error: err.message }, err.status);
    error(`${body.action}: ${err}`);
    return res.json({ error: 'server_error' }, 500);
  }
};

// MARK: Identidad

async function authenticate(api, userId, log, error) {
  if (typeof userId !== 'string' || !USER_ID.test(userId)) throw failure(400, 'bad_user_id');

  let user = await api('GET', `/users/${userId}`, null, { allow404: true });
  if (!user) {
    user = await api('POST', '/users', { userId, name: userId.slice(0, 10) });
    log(`usuario nuevo ${userId.slice(0, 10)}…`);
  }

  // **La bienvenida, una vez.** Con clave de idempotencia en RevenueCat y la
  // marca en las preferencias: ni un reintento ni un segundo dispositivo la
  // cobran dos veces. Si el cliente aún no existe en RevenueCat —la app lo
  // crea al identificarse— se queda para la próxima vez.
  const prefs = user.prefs || {};
  if (!prefs.welcomed && isConfigured()) {
    try {
      const result = await adjust(userId, WELCOME, `welcome-${userId}`);
      if (result.ok) {
        await api('PATCH', `/users/${userId}/prefs`, { prefs: { ...prefs, welcomed: true } });
        log(`bienvenida para ${userId.slice(0, 10)}…`);
      }
    } catch (err) {
      error(`bienvenida: ${err}`);
    }
  }

  // Un token de un minuto y un solo uso: con él la app abre la sesión de
  // **este** usuario. Ver `account/sessions/token`.
  const token = await api('POST', `/users/${userId}/tokens`, { length: 48, expire: 60 });
  return { userId, secret: token.secret };
}

// MARK: Regalos

async function pendingGrants(api, userId) {
  const queries = [
    JSON.stringify({ method: 'equal', attribute: 'userId', values: [userId] }),
    JSON.stringify({ method: 'equal', attribute: 'status', values: ['pending'] }),
    JSON.stringify({ method: 'orderDesc', attribute: '$createdAt' }),
  ];
  const query = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
  const list = await api('GET', `/databases/${DATABASE}/collections/${GRANTS}/documents?${query}`);
  return (list.documents || []).map(publicGrant);
}

async function claim(api, userId, grantId, log) {
  if (typeof grantId !== 'string' || !grantId) throw failure(400, 'bad_grant');
  const grant = await api('GET', `/databases/${DATABASE}/collections/${GRANTS}/documents/${grantId}`, null, { allow404: true });
  // De otro, o no existe: lo mismo. No se dice cuál de las dos.
  if (!grant || grant.userId !== userId) throw failure(404, 'not_found');
  if (grant.status === 'claimed') return { claimed: true, grant: publicGrant(grant) };

  if (!isConfigured()) throw failure(503, 'store_not_configured');
  // Idempotente por regalo: dos toques seguidos en "Reclamar" suman una vez.
  const result = await adjust(userId, { [grant.currency]: grant.amount }, `grant-${grant.$id}`);
  if (!result.ok) throw failure(409, result.missing ? 'customer_missing' : 'store_refused');

  const updated = await api('PATCH', `/databases/${DATABASE}/collections/${GRANTS}/documents/${grant.$id}`, {
    data: { status: 'claimed', claimedAt: new Date().toISOString() },
  });
  log(`regalo ${grant.$id} reclamado · ${grant.amount} ${grant.currency}`);
  return { claimed: true, grant: publicGrant(updated) };
}

/**
 * Avisa del regalo. **Silencioso siempre** —`contentAvailable`, que llega
 * aunque el usuario no haya dado permiso de avisos y despierta la app para
 * que enseñe el suyo—, y con título y texto, que el sistema enseña solo si sí
 * lo dio.
 */
async function notifyGrant(api, grant, log) {
  if (!grant?.userId || grant.status === 'claimed') return;
  const amount = grant.amount;
  const title = grant.currency === 'PRU' ? 'Tienes pruebas de regalo' : 'Tienes mejoras de regalo';
  const text = grant.message || `${amount} para ti. Entra a reclamarlas.`;
  await api('POST', '/messaging/messages/push', {
    messageId: `grant${grant.$id}`.slice(0, 36),
    title,
    body: text,
    users: [grant.userId],
    data: { type: 'grant', grantId: grant.$id },
    contentAvailable: true,
    sound: 'default',
  });
  log(`aviso de regalo ${grant.$id} enviado`);
}

function publicGrant(grant) {
  return {
    id: grant.$id,
    currency: grant.currency,
    amount: grant.amount,
    message: grant.message || null,
    status: grant.status,
    createdAt: grant.$createdAt,
  };
}

// MARK: Appwrite

/**
 * Una llamada a la API de Appwrite con la clave dinámica de la ejecución.
 * El endpoint público y no el inyectado: ver `deploy_function.py`.
 */
function appwrite(key) {
  const endpoint = process.env.PUBLIC_API_ENDPOINT || process.env.APPWRITE_FUNCTION_API_ENDPOINT;
  return async (method, path, body, { allow404 = false } = {}) => {
    const response = await fetch(`${endpoint}${path}`, {
      method,
      headers: {
        'X-Appwrite-Project': process.env.APPWRITE_FUNCTION_PROJECT_ID,
        'X-Appwrite-Key': key,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (allow404 && response.status === 404) return null;
    const text = await response.text();
    if (!response.ok) throw new Error(`${method} ${path.split('?')[0]} → ${response.status}: ${text.slice(0, 200)}`);
    return text ? JSON.parse(text) : {};
  };
}

function failure(status, message) {
  const err = new Error(message);
  err.status = status;
  err.expose = true;
  return err;
}
