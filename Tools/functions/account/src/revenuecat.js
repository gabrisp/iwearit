/**
 * **El saldo vive en RevenueCat.** Las compras lo llenan solas —cada producto
 * trae sus monedas configuradas en el panel— y aquí solo se lee y se ajusta con
 * la API v2 y la clave secreta, que no sale del servidor.
 *
 * El cliente de RevenueCat es el mismo id que el usuario de Appwrite: ver
 * `StableIdentity` en la app.
 */
const API = 'https://api.revenuecat.com/v2';

export function isConfigured() {
  return Boolean(process.env.REVENUECAT_SECRET_KEY && process.env.REVENUECAT_PROJECT_ID);
}

function customerPath(customerID) {
  return `${API}/projects/${process.env.REVENUECAT_PROJECT_ID}/customers/${encodeURIComponent(customerID)}`;
}

function headers(idempotencyKey) {
  const result = {
    Authorization: `Bearer ${process.env.REVENUECAT_SECRET_KEY}`,
    'Content-Type': 'application/json',
  };
  if (idempotencyKey) result['Idempotency-Key'] = idempotencyKey;
  return result;
}

/** El saldo de cada moneda: `{ MEJ: 3, PRU: 1 }`. */
export async function balances(customerID) {
  const response = await fetch(`${customerPath(customerID)}/virtual_currencies`, { headers: headers() });
  if (!response.ok) throw new Error(`RevenueCat ${response.status}: ${(await response.text()).slice(0, 200)}`);
  const json = await response.json();
  const result = {};
  for (const item of json.items || []) result[item.currency_code] = item.balance;
  return result;
}

/**
 * Suma o resta. **Atómico**: si no alcanza, RevenueCat contesta 422 y no toca
 * nada —por eso reservar es restar directamente—. Con clave de idempotencia:
 * repetir la misma operación (un reintento de red) no cobra dos veces.
 *
 * @returns `{ ok: true }`, `{ ok: false, insufficient: true }` o
 *   `{ ok: false, missing: true }` si el cliente todavía no existe en RC.
 */
export async function adjust(customerID, adjustments, idempotencyKey) {
  const response = await fetch(`${customerPath(customerID)}/virtual_currencies/transactions`, {
    method: 'POST',
    headers: headers(idempotencyKey),
    body: JSON.stringify({ adjustments }),
  });
  if (response.ok) return { ok: true };
  if (response.status === 422) return { ok: false, insufficient: true };
  if (response.status === 404) return { ok: false, missing: true };
  throw new Error(`RevenueCat ${response.status}: ${(await response.text()).slice(0, 200)}`);
}
