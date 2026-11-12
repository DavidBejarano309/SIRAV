import { useMemo, useState } from "react";
import { CarFront } from "lucide-react";
import { api, money, today, addDays } from "../api";
import { newIdempotencyKey } from "../uuid";
import {
  AddButton,
  Badge,
  Empty,
  ErrorBox,
  Field,
  Form,
  Loading,
  Modal,
  PageHead,
  useResource,
} from "../components";

export default function Catalog({ admin, staff, revision, changed }) {
  const [search, setSearch] = useState(""),
    [category, setCategory] = useState("");
  const [from, setFrom] = useState(today()),
    [to, setTo] = useState(addDays(today(), 2));
  const [available, setAvailable] = useState(false),
    [modal, setModal] = useState(null);
  const params = new URLSearchParams({
    search,
    from,
    to,
    available: String(available),
    ...(category ? { category } : {}),
  });
  const fleet = useResource("/vehicles?" + params, revision);
  const categories = useResource("/categories", revision);
  const close = () => setModal(null);
  const done = () => {
    setModal(null);
    changed("Datos guardados correctamente");
  };
  return (
    <>
      <PageHead
        title="Nuestra flota"
        description="Consulta vehículos, disponibilidad y tarifas."
        action={
          admin && (
            <AddButton onClick={() => setModal({ type: "vehicle" })}>
              Nuevo vehículo
            </AddButton>
          )
        }
      />
      <div className="filter-bar">
        <Field
          label="Buscar vehículo"
          placeholder="Marca, modelo o placa"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <Field
          label="Categoría"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          options={[
            { value: "", label: "Todas" },
            ...(categories.data || []).map((c) => ({
              value: c.id_categoria,
              label: c.nombre,
            })),
          ]}
        />
        <Field
          label="Recogida"
          type="date"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
        />
        <Field
          label="Devolución"
          type="date"
          value={to}
          min={addDays(from || today(), 1)}
          onChange={(e) => setTo(e.target.value)}
        />
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={available}
            onChange={(e) => setAvailable(e.target.checked)}
          />
          Solo disponibles
        </label>
      </div>
      {fleet.loading ? (
        <Loading />
      ) : fleet.error ? (
        <ErrorBox>{fleet.error}</ErrorBox>
      ) : !fleet.data.length ? (
        <Empty text="No hay vehículos para esos filtros." />
      ) : (
        <div className="vehicle-grid">
          {fleet.data.map((v) => (
            <article className="panel vehicle-card" key={v.id_vehiculo}>
              <div className="vehicle-top">
                <CarFront size={34} />
                <Badge value={v.disponible ? "DISPONIBLE" : "NO_DISPONIBLE"} />
              </div>
              <h2>
                {v.marca} {v.modelo}
              </h2>
              <p>
                {v.placa} · {v.categoria} · {v.anio}
              </p>
              <p>{Number(v.kilometraje_actual).toLocaleString("es-CO")} km</p>
              <strong>
                {v.valor_diario
                  ? money(v.valor_diario) + " / día"
                  : "Sin tarifa vigente"}
              </strong>
              <div className="card-actions">
                <button
                  className="button primary"
                  disabled={!v.disponible || !v.valor_diario}
                  aria-label={`Reservar ${v.marca} ${v.modelo}`}
                  onClick={() => setModal({ type: "reserve", vehicle: v })}
                >
                  Reservar
                </button>
                {admin && (
                  <button
                    className="button secondary"
                    onClick={() => setModal({ type: "vehicle", vehicle: v })}
                  >
                    Editar
                  </button>
                )}
              </div>
            </article>
          ))}
        </div>
      )}
      {modal?.type === "vehicle" && (
        <Vehicle
          vehicle={modal.vehicle}
          categories={categories.data || []}
          onClose={close}
          onDone={done}
        />
      )}
      {modal?.type === "reserve" && (
        <Reserve
          vehicle={modal.vehicle}
          staff={staff}
          initialFrom={from}
          initialTo={to}
          onClose={close}
          onDone={() => {
            close();
            changed("Reserva solicitada. Un operador podrá confirmarla.");
          }}
        />
      )}
    </>
  );
}
function Vehicle({ vehicle: v, categories, onClose, onDone }) {
  return (
    <Modal title={v ? "Editar vehículo" : "Nuevo vehículo"} onClose={onClose}>
      <Form
        onCancel={onClose}
        onDone={onDone}
        onSubmit={(d) =>
          api(v ? `/vehicles/${v.id_vehiculo}` : "/vehicles", {
            method: v ? "PUT" : "POST",
            body: {
              ...d,
              idCategoria: Number(d.idCategoria),
              anio: Number(d.anio),
              kilometrajeActual: Number(d.kilometrajeActual),
            },
          })
        }
      >
        <div className="form-grid">
          <Field
            label="Placa"
            name="placa"
            required
            maxLength={12}
            defaultValue={v?.placa}
          />
          <Field
            label="Categoría"
            name="idCategoria"
            required
            defaultValue={v?.id_categoria}
            options={categories.map((c) => ({
              value: c.id_categoria,
              label: c.nombre,
            }))}
          />
          <Field
            label="Marca"
            name="marca"
            required
            maxLength={70}
            defaultValue={v?.marca}
          />
          <Field
            label="Modelo"
            name="modelo"
            required
            maxLength={70}
            defaultValue={v?.modelo}
          />
          <Field
            label="Año"
            name="anio"
            type="number"
            min={1950}
            max={2100}
            required
            defaultValue={v?.anio || 2026}
          />
          <Field
            label="Color"
            name="color"
            maxLength={40}
            defaultValue={v?.color}
          />
          <Field
            label="Kilometraje"
            name="kilometrajeActual"
            type="number"
            required
            min={v?.kilometraje_actual || 0}
            defaultValue={v?.kilometraje_actual || 0}
          />
          <Field
            label="Estado"
            name="estadoOperativo"
            defaultValue={
              v?.estado_operativo === "INACTIVO" ? "INACTIVO" : "DISPONIBLE"
            }
            options={[
              { value: "DISPONIBLE", label: "Disponible" },
              { value: "INACTIVO", label: "Inactivo" },
            ]}
          />
        </div>
      </Form>
    </Modal>
  );
}
function Reserve({ vehicle, staff, initialFrom, initialTo, onClose, onDone }) {
  const [from, setFrom] = useState(initialFrom),
    [to, setTo] = useState(initialTo),
    [client, setClient] = useState("");
  const clients = useResource(staff ? "/clients" : "/categories");
  const quote = useResource(
    `/vehicles/${vehicle.id_vehiculo}/quote?from=${from}&to=${to}`,
  );
  const key = useMemo(() => newIdempotencyKey(), [from, to, client]);
  async function submit() {
    if (!quote.data?.disponible)
      throw Error("El vehículo no está disponible para esas fechas.");
    return api("/reservations", {
      method: "POST",
      headers: { "Idempotency-Key": key },
      body: {
        idVehiculo: vehicle.id_vehiculo,
        fechaInicio: from,
        fechaFin: to,
        ...(staff ? { idCliente: Number(client) } : {}),
      },
    });
  }
  return (
    <Modal
      title={`Reserva tu ${vehicle.marca} ${vehicle.modelo}`}
      subtitle={vehicle.placa}
      onClose={onClose}
    >
      <Form
        onSubmit={submit}
        onDone={onDone}
        onCancel={onClose}
        submit="Solicitar reserva"
      >
        <div className="form-grid">
          <Field
            label="Recogida"
            type="date"
            required
            min={today()}
            value={from}
            onChange={(e) => setFrom(e.target.value)}
          />
          <Field
            label="Devolución"
            type="date"
            required
            min={addDays(from || today(), 1)}
            value={to}
            onChange={(e) => setTo(e.target.value)}
          />
        </div>
        {staff && (
          <Field
            label="Cliente"
            required
            value={client}
            onChange={(e) => setClient(e.target.value)}
            options={[
              { value: "", label: "Selecciona un cliente" },
              ...(clients.data || []).map((c) => ({
                value: c.id_cliente,
                label: `${c.nombres} ${c.apellidos} · ${c.documento}`,
              })),
            ]}
          />
        )}
        {staff && clients.error && <ErrorBox>{clients.error}</ErrorBox>}
        {quote.loading ? (
          <Loading />
        ) : quote.error ? (
          <ErrorBox>{quote.error}</ErrorBox>
        ) : (
          <div className="quote">
            <p>
              {quote.data.dias} días × {money(quote.data.valor_diario)}
            </p>
            <strong>Total: {money(quote.data.total)}</strong>
            <p>
              {quote.data.disponible
                ? "Disponible para estas fechas."
                : "No disponible."}
            </p>
          </div>
        )}
      </Form>
    </Modal>
  );
}
