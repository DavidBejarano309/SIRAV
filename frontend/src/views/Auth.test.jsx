import { afterEach, describe, it, expect, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import Auth from "./Auth";
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});
describe("Ingreso de usuarios", () => {
  it("muestra un rechazo de credenciales sin abrir una sesión", async () => {
    const onLogin = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        json: async () => ({ detail: "Correo o contraseña incorrectos" }),
      }),
    );
    render(<Auth onLogin={onLogin} />);
    fireEvent.change(screen.getByLabelText("Correo electrónico"), {
      target: { value: "cliente@sirav.local" },
    });
    fireEvent.change(screen.getByLabelText("Contraseña"), {
      target: { value: "incorrecta" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar a SIRAV" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Correo o contraseña incorrectos",
    );
    expect(onLogin).not.toHaveBeenCalled();
  });
  it("entrega el usuario autenticado a la aplicación", async () => {
    const user = { nombre: "Ana", roles: ["CLIENTE"] },
      onLogin = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        headers: new Headers({ "content-type": "application/json" }),
        json: async () => ({ token: "jwt", user }),
      }),
    );
    render(<Auth onLogin={onLogin} />);
    fireEvent.change(screen.getByLabelText("Correo electrónico"), {
      target: { value: "ana@example.com" },
    });
    fireEvent.change(screen.getByLabelText("Contraseña"), {
      target: { value: "segura2026!" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar a SIRAV" }));
    await waitFor(() => expect(onLogin).toHaveBeenCalledWith(user));
  });
  it("solicita licencia y documento en el registro", () => {
    render(<Auth onLogin={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Crear una cuenta" }));
    expect(screen.getByLabelText("Documento")).toBeRequired();
    expect(screen.getByLabelText("Licencia de conducción")).toBeRequired();
  });
});
