import { test, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
const evidenceDirectory = process.env.SIRAV_EVIDENCE_DIR || "../docs/evidencias";
test.beforeAll(async () => { await mkdir(evidenceDirectory, { recursive: true }); });

test("administrador navega por todos los módulos conectados", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Qué bueno verte de nuevo" }),
  ).toBeVisible();
  await page.getByLabel("Correo electrónico").fill("admin@sirav.local");
  await page
    .getByLabel("Contraseña", { exact: true })
    .fill(process.env.DEMO_PASSWORD || "SiravDemo2026!");
  await page.getByRole("button", { name: "Ingresar a SIRAV" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Nuestra flota" }),
  ).toBeVisible();
  await page.screenshot({
    path: `${evidenceDirectory}/supuestos-inicio.png`,
    fullPage: true,
  });
  for (const [menu, title] of [
    ["Nuestra flota", "Nuestra flota"],
    ["Reservas", "Reservas"],
    ["Alquileres e inspecciones", "Alquileres"],
    ["Cobros simulados", "Cobros simulados"],
    ["Mantenimiento", "Mantenimiento"],
    ["Historial y reportes", "Reportes"],
    ["Usuarios y perfiles", "Usuarios y perfiles"],
  ]) {
    await page
      .getByRole("navigation")
      .getByRole("button", { name: menu, exact: true })
      .click();
    await expect(
      page.getByRole("heading", { level: 1, name: title, exact: true }),
    ).toBeVisible();
    await expect(page.getByText("Cargando información…")).toHaveCount(0);
    await expect(page.getByRole("alert")).toHaveCount(0);
    if (menu === "Nuestra flota")
      await page.screenshot({
        path: `${evidenceDirectory}/supuestos-flota.png`,
        fullPage: true,
      });
  }
  await page.getByRole("button", { name: "Mi perfil", exact: true }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Mi perfil" }),
  ).toBeVisible();
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Historial y reportes" })
    .click();
  await page.getByRole("button", { name: "Historial", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Historial", exact: true })
    .selectOption("events");
  await expect(page.getByText("Cargando información…")).toHaveCount(0);
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(
    page.getByRole("cell", { name: "LOGIN", exact: true }).first(),
  ).toBeVisible();
  expect(errors).toEqual([]);
  await page.screenshot({
    path: `${evidenceDirectory}/supuestos-historial.png`,
    fullPage: true,
    mask: [page.locator("tbody tr").filter({ hasText: /@(?!sirav\.local|example\.com)/ })],
  });
});

test("administrador crea una cuenta con roles múltiples y la desactiva", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByLabel("Correo electrónico").fill("admin@sirav.local");
  await page
    .getByLabel("Contraseña", { exact: true })
    .fill(process.env.DEMO_PASSWORD || "SiravDemo2026!");
  await page.getByRole("button", { name: "Ingresar a SIRAV" }).click();
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Usuarios y perfiles" })
    .click();
  await page
    .getByRole("button", { name: "Nuevo usuario", exact: true })
    .click();
  const modal = page.getByRole("dialog");
  const id = "web" + Date.now();
  const email = id + "@example.com";
  await modal.getByLabel("Nombre", { exact: true }).fill("Cuenta");
  await modal.getByLabel("Apellido", { exact: true }).fill("Navegador");
  await modal.getByLabel("Correo", { exact: true }).fill(email);
  await modal.getByLabel("Contraseña inicial").fill("PruebaSegura2026!");
  await modal.getByRole("checkbox", { name: "CLIENTE", exact: true }).check();
  await modal.getByLabel("Documento").fill(id);
  await modal.getByLabel("Licencia").fill("LIC-WEB");
  await modal.getByRole("button", { name: "Guardar", exact: true }).click();
  await expect(modal).toHaveCount(0);
  const row = page.getByRole("row").filter({ hasText: email });
  await expect(row).toContainText("CLIENTE,OPERADOR");
  await row.getByRole("button", { name: "Ver detalle" }).click();
  await page.getByRole("checkbox", { name: "Cuenta activa" }).uncheck();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "Guardar", exact: true })
    .click();
  await expect(modal).toHaveCount(0);
  await expect(row).toContainText("inactivo");
  await expect(page.getByRole("alert")).toHaveCount(0);
  await page.screenshot({
    path: `${evidenceDirectory}/supuestos-usuarios.png`,
    fullPage: true,
    mask: [page.locator("tbody tr").filter({ hasText: /@(?!sirav\.local|example\.com)/ })],
  });
});

test("cliente tiene acceso a sus reservas y diseño móvil sin desbordamiento", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByLabel("Correo electrónico").fill("cliente@sirav.local");
  await page
    .getByLabel("Contraseña", { exact: true })
    .fill(process.env.DEMO_PASSWORD || "SiravDemo2026!");
  await page.getByRole("button", { name: "Ingresar a SIRAV" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Nuestra flota" }),
  ).toBeVisible();
  await expect(
    page
      .getByRole("navigation")
      .getByRole("button", { name: "Usuarios y perfiles" }),
  ).toHaveCount(0);
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Nuestra flota", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Nuestra flota" }),
  ).toBeVisible();
  await expect(page.getByText("Cargando información…")).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBeTruthy();
  await page.screenshot({
    path: `${evidenceDirectory}/supuestos-movil.png`,
    fullPage: true,
  });
});
