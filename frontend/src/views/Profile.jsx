import { api, setToken } from "../api";
import { Field, Form, PageHead } from "../components";
export default function Profile({ user, setUser, changed }) {
  return (
    <>
      <PageHead
        title="Mi perfil"
        description={`${user.email} · ${user.roles.join(", ")}`}
      />
      <section className="panel">
        <h2>Datos personales</h2>
        <Form
          onSubmit={async (d) =>
            setUser(await api("/auth/me", { method: "PUT", body: d }))
          }
          onDone={() => changed("Perfil actualizado")}
        >
          <div className="form-grid">
            <Field
              label="Nombre"
              name="nombre"
              defaultValue={user.nombre}
              required
              maxLength={100}
            />
            <Field
              label="Apellido"
              name="apellido"
              defaultValue={user.apellido}
              required
              maxLength={100}
            />
            {user.id_cliente && (
              <>
                <Field
                  label="Teléfono"
                  name="telefono"
                  defaultValue={user.telefono || ""}
                  maxLength={25}
                />
                <Field
                  label="Licencia"
                  name="licencia"
                  defaultValue={user.licencia_conduccion || ""}
                  maxLength={40}
                  required
                />
              </>
            )}
          </div>
        </Form>
      </section>
      <section className="panel">
        <h2>Cambiar contraseña</h2>
        <p>
          El cambio cierra las sesiones. Ingresa de nuevo con la nueva
          contraseña.
        </p>
        <Form
          submit="Cambiar contraseña"
          onSubmit={(d) => api("/auth/password", { method: "POST", body: d })}
          onDone={() => {
            setToken(null);
            setUser(null);
          }}
        >
          <div className="form-grid">
            <Field
              label="Contraseña actual"
              name="actual"
              type="password"
              required
              autoComplete="current-password"
            />
            <Field
              label="Nueva contraseña"
              name="nueva"
              type="password"
              required
              minLength={10}
              maxLength={72}
              autoComplete="new-password"
            />
          </div>
        </Form>
      </section>
    </>
  );
}
