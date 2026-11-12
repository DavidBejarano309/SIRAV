import { useState } from "react";
import { api } from "../api";
import {
  AddButton,
  Badge,
  ErrorBox,
  Field,
  Form,
  Loading,
  Modal,
  PageHead,
  Table,
  useResource,
} from "../components";

export default function Users({ revision, changed }) {
  const resource = useResource("/users", revision);
  const [selected, setSelected] = useState(null);
  return (
    <>
      <PageHead
        title="Usuarios y perfiles"
        description="Cuentas, roles y activación. Desactivar conserva el historial y revoca las sesiones."
        action={
          <AddButton onClick={() => setSelected({})}>Nuevo usuario</AddButton>
        }
      />
      <section className="panel">
        {resource.loading ? (
          <Loading />
        ) : resource.error ? (
          <ErrorBox>{resource.error}</ErrorBox>
        ) : (
          <Table
            rows={resource.data}
            onRow={setSelected}
            columns={[
              {
                key: "nombre",
                label: "Nombre",
                render: (r) => `${r.nombre} ${r.apellido}`,
              },
              { key: "email", label: "Correo" },
              { key: "roles", label: "Roles" },
              {
                key: "activo",
                label: "Estado",
                render: (r) => (
                  <Badge value={r.activo ? "ACTIVO" : "INACTIVO"} />
                ),
              },
            ]}
          />
        )}
      </section>
      {selected && (
        <Editor
          record={selected}
          onClose={() => setSelected(null)}
          onDone={() => {
            setSelected(null);
            changed("Usuario guardado");
          }}
        />
      )}
    </>
  );
}
function Editor({ record: r, onClose, onDone }) {
  const existing = Boolean(r.id_usuario);
  const [roles, setRoles] = useState(r.roles?.split(",") || ["OPERADOR"]);
  const [active, setActive] = useState(r.activo ?? true);
  return (
    <Modal
      title={existing ? "Permisos del usuario" : "Nuevo usuario"}
      subtitle={r.email}
      onClose={onClose}
    >
      <Form
        onCancel={onClose}
        onDone={onDone}
        onSubmit={(d) =>
          api(existing ? `/users/${r.id_usuario}` : "/users", {
            method: existing ? "PUT" : "POST",
            body: existing ? { activo: active, roles } : { ...d, roles },
          })
        }
      >
        {!existing && (
          <div className="form-grid">
            <Field label="Nombre" name="nombre" required maxLength={100} />
            <Field label="Apellido" name="apellido" required maxLength={100} />
            <Field
              label="Correo"
              name="email"
              type="email"
              required
              maxLength={150}
            />
            <Field
              label="Contraseña inicial"
              name="password"
              type="password"
              required
              minLength={10}
              maxLength={72}
              autoComplete="new-password"
            />
          </div>
        )}
        <fieldset>
          <legend>Roles (selecciona al menos uno)</legend>
          {["ADMIN", "OPERADOR", "CLIENTE"].map((role) => (
            <label key={role} className="checkbox-label">
              <input
                type="checkbox"
                checked={roles.includes(role)}
                onChange={(e) =>
                  setRoles(
                    e.target.checked
                      ? [...roles, role]
                      : roles.filter((v) => v !== role),
                  )
                }
              />
              {role}
            </label>
          ))}
        </fieldset>
        {!existing && roles.includes("CLIENTE") && (
          <div className="form-grid">
            <Field label="Documento" name="documento" required maxLength={30} />
            <Field label="Licencia" name="licencia" required maxLength={40} />
          </div>
        )}
        {existing && (
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={active}
              onChange={(e) => setActive(e.target.checked)}
            />
            Cuenta activa
          </label>
        )}
      </Form>
    </Modal>
  );
}
