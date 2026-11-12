import { useState } from "react";
import { api, date, money } from "../api";
import {
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
import InspectionFields, {
  emptyInspection,
  EvidenceList,
} from "../InspectionFields";
export default function Operations({
  staff,
  revision,
  changed,
  rentals = false,
}) {
  const resource = useResource(
    rentals ? "/rentals" : "/reservations",
    revision,
  );
  const [selected, setSelected] = useState(null);
  const [action, setAction] = useState(null);
  return (
    <>
      <PageHead
        title={rentals ? "Alquileres" : "Reservas"}
        description={
          rentals
            ? "Entrega, devolución e inspecciones del vehículo."
            : "Solicita en el catálogo. Para cambiar fechas, cancela y crea una nueva reserva."
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
                key: "id_reserva",
                label: "Reserva",
                render: (r) => "#" + r.id_reserva,
              },
              { key: "cliente", label: "Cliente" },
              {
                key: "vehiculo",
                label: "Vehículo",
                render: (r) => (
                  <div>
                    {r.marca} {r.modelo}
                    <small>{r.placa}</small>
                  </div>
                ),
              },
              {
                key: "fechas",
                label: "Fechas",
                render: (r) => (
                  <div>
                    {date(r.fecha_inicio)}
                    <small>hasta {date(r.fecha_fin)}</small>
                  </div>
                ),
              },
              {
                key: "costo_base",
                label: "Base",
                render: (r) => money(r.costo_base),
              },
              {
                key: "estado",
                label: "Estado",
                render: (r) => <Badge value={r.estado} />,
              },
            ]}
          />
        )}
      </section>
      {selected && (
        <Detail
          reservation={selected}
          staff={staff}
          onClose={() => setSelected(null)}
          onAction={(type) => {
            setAction({ type, reservation: selected });
            setSelected(null);
          }}
        />
      )}
      {action && (
        <ActionModal
          {...action}
          onClose={() => setAction(null)}
          onDone={() => {
            setAction(null);
            changed("Operación registrada correctamente");
          }}
        />
      )}
    </>
  );
}
function Detail({ reservation: r, staff, onClose, onAction }) {
  const history = useResource(`/reservations/${r.id_reserva}/history`);
  return (
    <Modal
      title={`Reserva #${r.id_reserva}`}
      subtitle={`${r.marca} ${r.modelo} · ${r.placa}`}
      onClose={onClose}
    >
      <div className="detail-summary">
        <Badge value={r.estado} />
        <strong>{money(r.costo_base)}</strong>
      </div>
      <p>
        {r.cliente} · {date(r.fecha_inicio)} → {date(r.fecha_fin)}
      </p>
      <h3>Historial</h3>
      {history.error ? (
        <ErrorBox>{history.error}</ErrorBox>
      ) : (
        <Table
          rows={history.data}
          columns={[
            {
              key: "estado_nuevo",
              label: "Estado",
              render: (h) => <Badge value={h.estado_nuevo} />,
            },
            { key: "actor", label: "Usuario" },
            {
              key: "fecha_evento",
              label: "Fecha",
              render: (h) => date(h.fecha_evento),
            },
            { key: "observacion", label: "Motivo" },
          ]}
        />
      )}
      {r.id_alquiler && <RentalDetails id={r.id_alquiler} />}
      <div className="form-footer">
        {["SOLICITADA", "CONFIRMADA"].includes(r.estado) && (
          <button className="button danger" onClick={() => onAction("cancel")}>
            Cancelar reserva
          </button>
        )}
        {staff && r.estado === "SOLICITADA" && (
          <button
            className="button primary"
            onClick={() => onAction("confirm")}
          >
            Confirmar
          </button>
        )}
        {staff && r.estado === "CONFIRMADA" && (
          <button className="button primary" onClick={() => onAction("start")}>
            Registrar entrega
          </button>
        )}
        {staff && r.estado === "ACTIVA" && (
          <button className="button primary" onClick={() => onAction("close")}>
            Registrar devolución
          </button>
        )}
      </div>
    </Modal>
  );
}
export function RentalDetails({ id }) {
  const inspections = useResource(`/rentals/${id}/inspections`);
  const payments = useResource(`/rentals/${id}/payments`);
  const status = useResource(`/rentals/${id}/inspection-status`);
  return (
    <>
      <h3>Inspecciones</h3>
      {status.error && <ErrorBox>{status.error}</ErrorBox>}
      {status.data?.estado === "INCONSISTENTE" && (
        <ErrorBox>
          Faltan inspecciones: {status.data.faltantes.join(", ")}. Requiere
          revisión del operador.
        </ErrorBox>
      )}
      {status.data?.estado === "PENDIENTE" && (
        <p className="muted">
          Inspecciones pendientes de sincronización:{" "}
          {status.data.pendientes.join(", ")}.
        </p>
      )}
      {!!status.data?.anuladas.length && (
        <p className="muted">
          Inspecciones anuladas: {status.data.anuladas.join(", ")}.
        </p>
      )}
      {inspections.error ? (
        <ErrorBox>{inspections.error}</ErrorBox>
      ) : (
        <Table
          rows={inspections.data}
          empty="No hay inspecciones disponibles. Consulta el estado indicado arriba."
          columns={[
            { key: "tipo", label: "Tipo" },
            {
              key: "anulada",
              label: "Registro",
              render: (r) => (r.anulada ? "Anulada" : "Vigente"),
            },
            { key: "kilometraje", label: "Km" },
            { key: "combustible", label: "Combustible (%)" },
            { key: "observaciones", label: "Observaciones" },
            {
              key: "evidencias",
              label: "Evidencias",
              render: (r) => <EvidenceList references={r.evidencias} />,
            },
          ]}
        />
      )}
      <h3>Pago simulado</h3>
      {payments.error ? (
        <ErrorBox>{payments.error}</ErrorBox>
      ) : (
        <>
          <Table
            rows={payments.data?.pagos}
            columns={[
              { key: "monto", label: "Monto", render: (p) => money(p.monto) },
              { key: "tipo", label: "Tipo" },
              { key: "estado", label: "Estado" },
            ]}
          />
          {!!payments.data?.cargos.length && (
            <Table
              rows={payments.data.cargos}
              columns={[
                { key: "concepto", label: "Cargo" },
                { key: "monto", label: "Monto", render: (c) => money(c.monto) },
              ]}
            />
          )}
        </>
      )}
    </>
  );
}
function ActionModal({ type, reservation: r, onClose, onDone }) {
  const [inspection, setInspection] = useState(emptyInspection);
  const [uploading, setUploading] = useState(false);
  const handover = type === "start" || type === "close";
  const title = {
    confirm: "Confirmar reserva",
    cancel: "Cancelar reserva",
    start: "Entrega del vehículo",
    close: "Devolución del vehículo",
  }[type];
  async function submit(data) {
    const path =
      type === "close"
        ? `/rentals/${r.id_alquiler}/close`
        : `/reservations/${r.id_reserva}/${type}`;
    let body = type === "cancel" ? { motivo: data.motivo } : undefined;
    if (handover)
      body = {
        kilometraje: Number(data.kilometraje),
        combustible: Number(data.combustible),
        inspeccion: {
          ...inspection,
          evidencias: inspection.evidencias
            .map((v) => v.trim())
            .filter(Boolean),
        },
      };
    return api(path, { method: "POST", body });
  }
  const km = r.km_salida ?? r.kilometraje_actual ?? 0;
  return (
    <Modal
      title={title}
      subtitle={`${r.placa} · Reserva #${r.id_reserva}`}
      onClose={onClose}
    >
      <Form
        disabled={uploading}
        onSubmit={submit}
        onDone={onDone}
        onCancel={onClose}
        submit={type === "close" ? "Cerrar y generar pago simulado" : title}
      >
        {type === "confirm" && (
          <p>
            La reserva quedará confirmada y lista para entregar durante el
            período reservado.
          </p>
        )}
        {type === "cancel" && (
          <Field
            label="Motivo"
            name="motivo"
            type="textarea"
            minLength={5}
            maxLength={1000}
            required
          />
        )}
        {handover && (
          <>
            <div className="form-grid">
              <Field
                label="Kilometraje actual"
                name="kilometraje"
                type="number"
                min={km}
                defaultValue={km}
                required
              />
              <Field
                label="Combustible (%)"
                name="combustible"
                type="number"
                min={0}
                max={100}
                step="0.01"
                defaultValue={100}
                required
              />
            </div>
            <InspectionFields
              value={inspection}
              onChange={setInspection}
              uploadPath={`/reservations/${r.id_reserva}/evidence`}
              onBusyChange={setUploading}
            />
            {type === "close" && (
              <p className="quote">
                Base: {money(r.costo_base)}. El sistema calcula el cargo por
                retraso y genera un pago simulado.
              </p>
            )}
          </>
        )}
      </Form>
    </Modal>
  );
}
