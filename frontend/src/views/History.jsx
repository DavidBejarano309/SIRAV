import { useState } from "react";
import { today, addDays, date } from "../api";
import {
  ErrorBox,
  Field,
  Loading,
  PageHead,
  Table,
  useResource,
} from "../components";
export default function History({ admin, revision }) {
  const [type, setType] = useState("reservations");
  const [from, setFrom] = useState(addDays(today(), -30));
  const [to, setTo] = useState(addDays(today(), 1));
  const [action, setAction] = useState("");
  const resource = useResource(
    `/audit/${type}?from=${from}&to=${to}&action=${encodeURIComponent(action)}`,
    revision,
  );
  return (
    <>
      <PageHead
        title="Historial"
        description="Eventos de reservas y bitácora de acceso y administración. Se muestran hasta 200 eventos recientes por consulta."
      />
      <div className="filter-bar">
        <Field
          label="Historial"
          value={type}
          onChange={(e) => setType(e.target.value)}
          options={[
            { value: "reservations", label: "Reservas" },
            ...(admin ? [{ value: "events", label: "Acceso y usuarios" }] : []),
          ]}
        />
        <Field
          label="Desde"
          type="date"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
        />
        <Field
          label="Hasta (exclusivo)"
          type="date"
          value={to}
          onChange={(e) => setTo(e.target.value)}
        />
        {type === "events" && (
          <Field
            label="Acción exacta (opcional)"
            value={action}
            onChange={(e) => setAction(e.target.value)}
          />
        )}
      </div>
      <section className="panel">
        {resource.loading ? (
          <Loading />
        ) : resource.error ? (
          <ErrorBox>{resource.error}</ErrorBox>
        ) : (
          <Table
            rows={resource.data}
            columns={
              type === "events"
                ? [
                    {
                      key: "fecha",
                      label: "Fecha",
                      render: (r) => date(r.fecha),
                    },
                    { key: "accion", label: "Acción" },
                    { key: "actor", label: "Usuario actor" },
                    { key: "usuarioId", label: "Usuario afectado" },
                    { key: "resultado", label: "Resultado" },
                  ]
                : [
                    { key: "id_reserva", label: "Reserva" },
                    { key: "actor", label: "Usuario" },
                    {
                      key: "fecha_evento",
                      label: "Fecha",
                      render: (r) => date(r.fecha_evento),
                    },
                    { key: "estado_anterior", label: "Estado anterior" },
                    { key: "estado_nuevo", label: "Estado nuevo" },
                    { key: "observacion", label: "Motivo" },
                  ]
            }
          />
        )}
      </section>
    </>
  );
}
