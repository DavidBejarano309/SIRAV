import { test, expect } from "@playwright/test";

test("reserva, confirmación, entrega y devolución desde los formularios", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByLabel("Correo electrónico").fill("admin@sirav.local");
  await page
    .getByLabel("Contraseña", { exact: true })
    .fill(process.env.DEMO_PASSWORD || "SiravDemo2026!");
  await page.getByRole("button", { name: "Ingresar a SIRAV" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Nuestra flota" }),
  ).toBeVisible();
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Nuestra flota", exact: true })
    .click();
  await page.getByRole("button", { name: "Reservar Renault Duster" }).click();
  await page
    .getByRole("combobox", { name: "Cliente", exact: true })
    .selectOption({ label: "Cliente Demo · DEMO-001" });
  await expect(
    page.getByText("Disponible para estas fechas.", { exact: false }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Solicitar reserva", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Reservas", exact: true })
    .click();
  const row = () =>
    page.getByRole("row").filter({ hasText: "Renault Duster" }).first();
  await row().getByRole("button", { name: "Ver detalle" }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "Confirmar", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "Confirmar reserva", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(row()).toContainText("confirmada");
  await row().getByRole("button", { name: "Ver detalle" }).click();
  await page
    .getByRole("button", { name: "Registrar entrega", exact: true })
    .click();
  await page.getByLabel("Kilometraje actual").fill("900000");
  await page.getByLabel("Adjuntar evidencia", { exact: false }).setInputFiles({
    name: "foto.png",
    mimeType: "image/png",
    buffer: Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=",
      "base64",
    ),
  });
  await expect(
    page.getByRole("button", { name: "Descargar evidencia 1" }),
  ).toBeVisible();
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Descargar evidencia 1" }).click();
  expect((await download).suggestedFilename()).toMatch(/\.png$/);
  await page
    .getByLabel("Observaciones de la inspección")
    .fill("Entrega verificada desde el navegador");
  await page
    .getByRole("button", { name: "Entrega del vehículo", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(row()).toContainText("activa");
  await row().getByRole("button", { name: "Ver detalle" }).click();
  await page
    .getByRole("button", { name: "Registrar devolución", exact: true })
    .click();
  await page.getByLabel("Kilometraje actual").fill("900000");
  await page
    .getByLabel("Observaciones de la inspección")
    .fill("Devolución verificada desde el navegador");
  await page
    .getByRole("button", {
      name: "Cerrar y generar pago simulado",
      exact: true,
    })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(row()).toContainText("cerrada");
});
