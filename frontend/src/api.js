let token = null;
export const setToken = (value) => {
  token = value;
};
async function request(path, options = {}) {
  const multipart = options.body instanceof FormData;
  const response = await fetch(`/api${path}`, {
    ...options,
    headers: {
      ...(options.body && !multipart
        ? { "Content-Type": "application/json" }
        : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
    body: multipart
      ? options.body
      : options.body
        ? JSON.stringify(options.body)
        : undefined,
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
  return response;
}
export async function api(path, options = {}) {
  const response = await request(path, options);
  return response.status === 204 ? null : response.json();
}
export async function uploadEvidence(path, file) {
  const body = new FormData();
  body.append("file", file);
  return api(path, { method: "POST", body });
}
export async function openEvidence(reference) {
  if (
    !/^\/api\/reservations\/\d+\/evidence\/[a-f0-9-]+\.(png|jpg)$/.test(
      reference,
    )
  )
    throw new Error(
      "Esta referencia anterior no contiene un archivo disponible. Sustitúyela por una imagen.",
    );
  const response = await request(reference.slice(4));
  const url = URL.createObjectURL(await response.blob());
  const link = document.createElement("a");
  link.href = url;
  link.download = reference.split("/").pop();
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}
export const money = (value) =>
  new Intl.NumberFormat("es-CO", {
    style: "currency",
    currency: "COP",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
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
