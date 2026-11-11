import { test, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";

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
  await mkdir("../docs/evidencias", { recursive: true });
  await page.screenshot({
    path: "../docs/evidencias/3fn-inicio.png",
    fullPage: true,
  });
  for (const [menu, title] of [
    ["Nuestra flota", "Nuestra flota"],
    ["Reservas y alquileres", "Reservas y alquileres"],
    ["Clientes", "Clientes"],
    ["Inspecciones", "Inspecciones"],
    ["Mantenimiento", "Mantenimiento"],
    ["Tarifas y categorías", "Tarifas y categorías"],
    ["Reportes", "Reportes"],
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
        path: "../docs/evidencias/3fn-flota.png",
        fullPage: true,
      });
  }
  expect(errors).toEqual([]);
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
      .getByRole("button", { name: "Usuarios y roles" }),
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
    path: "../docs/evidencias/3fn-movil.png",
    fullPage: true,
  });
});
