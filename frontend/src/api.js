let token = null;
export const setToken = (value) => {
  token = value;
};
export async function api(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    ...options,
    headers: {
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  if (!response.ok) {
    const problem = await response.json().catch(() => ({}));
    if (response.status === 401 && !path.startsWith("/auth/login"))
      window.dispatchEvent(new Event("sirav-session-expired"));
    throw new Error(
      problem.detail ||
        (response.status === 403
          ? "No tienes permiso para esta acción."
          : `No se pudo completar la operación (${response.status}).`),
    );
  }
  if (response.status === 204) return null;
  return response.json();
}
export const money = (value) =>
  new Intl.NumberFormat("es-CO", {
    style: "currency",
    currency: "COP",
    maximumFractionDigits: 0,
  }).format(Number(value || 0));
export const date = (value) =>
  value
    ? new Date(
        String(value).length === 10 ? value + "T12:00:00" : value,
      ).toLocaleDateString("es-CO", {
        day: "2-digit",
        month: "short",
        year: "numeric",
      })
    : "—";
export const today = () =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
export function addDays(value, days) {
  const d = new Date(value + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
