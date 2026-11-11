import { useState } from "react";
import { api, setToken } from "../api";
import { Field, Form } from "../components";
export default function Auth({ onLogin }) {
  const [register, setRegister] = useState(false);
  const [notice, setNotice] = useState("");
  async function submit(data) {
    if (register) {
      await api("/auth/register", { method: "POST", body: data });
      setRegister(false);
      setNotice("Cuenta creada. Inicia sesión.");
      return;
    }
    const result = await api("/auth/login", { method: "POST", body: data });
    setToken(result.token);
    onLogin(result.user);
  }
  return (
    <main className="auth">
      <section className="panel auth-box">
        <div className="brand">SIRAV</div>
        <h1>
          {register ? "Crear cuenta de cliente" : "Qué bueno verte de nuevo"}
        </h1>
        <p>Reservas y alquiler de vehículos</p>
        {notice && (
          <p role="status" className="success">
            {notice}
          </p>
        )}
        <Form
          key={register ? "register" : "login"}
          onSubmit={submit}
          submit={register ? "Crear cuenta" : "Ingresar a SIRAV"}
        >
          {register && (
            <div className="form-grid">
              <Field label="Nombre" name="nombre" required maxLength={100} />
              <Field
                label="Apellido"
                name="apellido"
                required
                maxLength={100}
              />
              <Field
                label="Documento"
                name="documento"
                required
                maxLength={30}
              />
              <Field
                label="Licencia de conducción"
                name="licencia"
                required
                maxLength={40}
              />
              <Field label="Teléfono" name="telefono" maxLength={25} />
            </div>
          )}
          <Field
            label="Correo electrónico"
            name="email"
            type="email"
            autoComplete="email"
            required
            maxLength={150}
          />
          <Field
            label="Contraseña"
            name="password"
            type="password"
            autoComplete={register ? "new-password" : "current-password"}
            minLength={register ? 10 : 1}
            maxLength={72}
            required
          />
        </Form>
        <button
          className="link"
          onClick={() => {
            setRegister(!register);
            setNotice("");
          }}
        >
          {register ? "Volver al ingreso" : "Crear una cuenta"}
        </button>
        <p className="muted">
          Los pagos son simulados para demostración académica.
        </p>
      </section>
    </main>
  );
}
