import { useState } from "react";
import { api, date, money, today, addDays } from "../api";
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

const config = {
  clients: {
    title: "Clientes",
    endpoint: "/clients",
    columns: [
      {
        key: "nombre",
        label: "Nombre",
        render: (r) => r.nombres + " " + r.apellidos,
      },
      { key: "documento", label: "Documento" },
      { key: "telefono", label: "Teléfono" },
      { key: "email", label: "Correo" },
      { key: "licencia_conduccion", label: "Licencia" },
    ],
  },
  maintenance: {
    title: "Mantenimiento",
    endpoint: "/maintenance",
    columns: [
      { key: "placa", label: "Vehículo" },
      {
        key: "fecha_inicio",
        label: "Inicio",
        render: (r) => date(r.fecha_inicio),
      },
      { key: "fecha_fin", label: "Fin", render: (r) => date(r.fecha_fin) },
      { key: "descripcion", label: "Descripción" },
      {
        key: "estado",
        label: "Estado",
        render: (r) => <Badge value={r.estado} />,
      },
    ],
  },
  rates: {
    title: "Tarifas y categorías",
    endpoint: "/rates",
    columns: [
      { key: "categoria", label: "Categoría" },
      {
        key: "valor_diario",
        label: "Valor diario",
        render: (r) => money(r.valor_diario),
      },
      {
        key: "vigente_desde",
        label: "Desde",
        render: (r) => date(r.vigente_desde),
      },
      {
        key: "vigente_hasta",
        label: "Hasta",
        render: (r) => date(r.vigente_hasta),
      },
    ],
  },
};
export default function Management({ section, admin, revision, changed }) {
  const current = config[section];
  const resource = useResource(current.endpoint, revision),
    categories = useResource("/categories", revision);
  const [modal, setModal] = useState(null);
  const done = () => {
    setModal(null);
    changed("Datos guardados correctamente");
  };
  return (
    <>
      <PageHead
        title={current.title}
        description={
          section === "clients"
            ? "La identidad de clientes con cuenta se obtiene desde su usuario."
            : "Datos necesarios para la operación."
        }
        action={
          <AddButton onClick={() => setModal({})}>
            {section === "clients"
              ? "Nuevo cliente"
              : section === "maintenance"
                ? "Programar mantenimiento"
                : "Nueva tarifa"}
          </AddButton>
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
            columns={current.columns}
            onRow={section === "clients" ? undefined : (r) => setModal(r)}
          />
        )}
      </section>
      {section === "rates" && (
        <section className="panel">
          <div className="page-head">
            <h2>Categorías</h2>
            {admin && (
              <button
                className="button secondary"
                onClick={() => setModal({ category: true })}
              >
                Crear categoría
              </button>
            )}
          </div>
          <Table
            rows={categories.data}
            columns={[
              { key: "nombre", label: "Nombre" },
              { key: "descripcion", label: "Descripción" },
            ]}
          />
        </section>
      )}
      {modal && (
        <Editor
          section={section}
          record={modal}
          categories={categories.data || []}
          onClose={() => setModal(null)}
          onDone={done}
        />
      )}
    </>
  );
}
function Editor({ section, record: r, categories, onClose, onDone }) {
  const vehicles = useResource("/vehicles");
  const existing = Boolean(r.id_mantenimiento || r.id_tarifa);
  const title = r.category
    ? "Nueva categoría"
    : section === "clients"
      ? "Nuevo cliente"
      : section === "maintenance"
        ? existing
          ? "Finalizar mantenimiento"
          : "Programar mantenimiento"
        : existing
          ? "Cerrar vigencia"
          : "Nueva tarifa";
  async function submit(d) {
    if (r.category) return api("/categories", { method: "POST", body: d });
    if (section === "clients")
      return api("/clients", { method: "POST", body: d });
    if (section === "maintenance")
      return api(
        existing ? `/maintenance/${r.id_mantenimiento}` : "/maintenance",
        {
          method: existing ? "PATCH" : "POST",
          body: existing ? d : { ...d, idVehiculo: Number(d.idVehiculo) },
        },
      );
    return api(existing ? `/rates/${r.id_tarifa}/end` : "/rates", {
      method: existing ? "PUT" : "POST",
      body: existing
        ? d
        : {
            ...d,
            idCategoria: Number(d.idCategoria),
            valorDiario: Number(d.valorDiario),
            vigenteHasta: d.vigenteHasta || null,
          },
    });
  }
  let fields;
  if (r.category)
    fields = (
      <>
        <Field label="Nombre" name="nombre" required maxLength={70} />
        <Field
          label="Descripción"
          name="descripcion"
          type="textarea"
          maxLength={4000}
        />
      </>
    );
  else if (section === "clients")
    fields = (
      <div className="form-grid">
        <Field label="Nombres" name="nombres" required maxLength={100} />
        <Field label="Apellidos" name="apellidos" required maxLength={100} />
        <Field label="Documento" name="documento" required maxLength={30} />
        <Field label="Teléfono" name="telefono" maxLength={25} />
        <Field label="Correo" name="email" type="email" maxLength={150} />
        <Field
          label="Licencia"
          name="licenciaConduccion"
          required
          maxLength={40}
        />
      </div>
    );
  else if (section === "maintenance")
    fields = existing ? (
      <Field
        label="Nuevo estado"
        name="estado"
        options={[
          { value: "COMPLETADO", label: "Completado" },
          { value: "CANCELADO", label: "Cancelado" },
        ]}
      />
    ) : (
      <>
        <Field
          label="Vehículo"
          name="idVehiculo"
          required
          options={(vehicles.data || []).map((v) => ({
            value: v.id_vehiculo,
            label: v.placa + " · " + v.modelo,
          }))}
        />
        <div className="form-grid">
          <Field
            label="Inicio"
            name="fechaInicio"
            type="date"
            required
            defaultValue={today()}
          />
          <Field
            label="Fin"
            name="fechaFin"
            type="date"
            required
            defaultValue={addDays(today(), 1)}
          />
        </div>
        <Field
          label="Descripción"
          name="descripcion"
          type="textarea"
          required
          maxLength={4000}
        />
      </>
    );
  else
    fields = existing ? (
      <>
        <p>
          {r.categoria} · {money(r.valor_diario)}
        </p>
        <Field
          label="Vigente hasta (exclusivo)"
          name="vigenteHasta"
          type="date"
          required
        />
      </>
    ) : (
      <>
        <p className="muted">
          Cierra la vigencia anterior antes de crear una tarifa que la
          reemplace.
        </p>
        <Field
          label="Categoría"
          name="idCategoria"
          required
          options={categories.map((c) => ({
            value: c.id_categoria,
            label: c.nombre,
          }))}
        />
        <Field
          label="Valor diario"
          name="valorDiario"
          type="number"
          min="0.01"
          step="0.01"
          required
        />
        <div className="form-grid">
          <Field
            label="Desde"
            name="vigenteDesde"
            type="date"
            required
            defaultValue={today()}
          />
          <Field label="Hasta (opcional)" name="vigenteHasta" type="date" />
        </div>
      </>
    );
  return (
    <Modal title={title} onClose={onClose}>
      <Form onSubmit={submit} onDone={onDone} onCancel={onClose}>
        {fields}
      </Form>
    </Modal>
  );
}
