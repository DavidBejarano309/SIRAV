import { useState } from "react";
import { today, addDays } from "../api";
import {
  ErrorBox,
  Field,
  Loading,
  PageHead,
  Table,
  useResource,
} from "../components";
const reports = {
  occupancy: "Ocupación mensual",
  revenue: "Ingresos por categoría",
  ranking: "Vehículos más alquilados",
  clients: "Actividad de clientes",
  late: "Devoluciones tardías",
  availability: "Disponibilidad",
};
export default function Reports({ revision }) {
  const [type, setType] = useState("occupancy");
  const [from, setFrom] = useState(today().slice(0, 7) + "-01");
  const [to, setTo] = useState(addDays(today(), 1));
  const sql = useResource(`/reports/${type}?from=${from}&to=${to}`, revision);
  const mongo = useResource("/inspections/analytics", revision);
  const columns = (sql.data?.length ? Object.keys(sql.data[0]) : []).map(
    (key) => ({ key, label: key.replaceAll("_", " ") }),
  );
  return (
    <>
      <PageHead
        title="Reportes"
        description="Consultas SQL y agregaciones de las inspecciones."
      />
      <div className="filter-bar">
        <Field
          label="Reporte"
          value={type}
          onChange={(e) => setType(e.target.value)}
          options={Object.entries(reports).map(([value, label]) => ({
            value,
            label,
          }))}
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
      </div>
      <section className="panel">
        <h2>{reports[type]}</h2>
        {sql.loading ? (
          <Loading />
        ) : sql.error ? (
          <ErrorBox>{sql.error}</ErrorBox>
        ) : (
          <Table rows={sql.data} columns={columns} />
        )}
      </section>
      {mongo.loading ? (
        <Loading />
      ) : mongo.error ? (
        <ErrorBox>{mongo.error}</ErrorBox>
      ) : (
        <>
          <section className="panel">
            <h2>Promedios por categoría</h2>
            <Table
              rows={mongo.data.porCategoria}
              columns={[
                { key: "_id", label: "Categoría" },
                { key: "inspecciones", label: "Inspecciones" },
                {
                  key: "kilometrajePromedio",
                  label: "Km promedio",
                  render: (r) => Math.round(r.kilometrajePromedio),
                },
                {
                  key: "combustiblePromedio",
                  label: "Combustible (%)",
                  render: (r) => Math.round(r.combustiblePromedio),
                },
              ]}
            />
          </section>
          <section className="panel">
            <h2>Zonas con daños por mes</h2>
            <Table
              rows={mongo.data.zonasPorMes}
              columns={[
                { key: "mes", label: "Mes", render: (r) => r._id.mes },
                { key: "zona", label: "Zona", render: (r) => r._id.zona },
                { key: "incidencias", label: "Incidencias" },
              ]}
            />
          </section>
          <section className="panel">
            <h2>Incidencias por vehículo</h2>
            <Table
              rows={mongo.data.incidenciasPorVehiculo}
              columns={[
                { key: "_id", label: "Vehículo" },
                { key: "incidencias", label: "Incidencias" },
              ]}
            />
          </section>
          {mongo.data.pendientesSincronizacion > 0 && (
            <p className="muted">
              {mongo.data.pendientesSincronizacion} eventos pendientes de
              sincronización.
            </p>
          )}
        </>
      )}
    </>
  );
}
