import { useEffect, useId, useRef, useState } from "react";
import { AlertCircle, ChevronRight, LoaderCircle, Plus, X } from "lucide-react";
import { api } from "./api";

export function useResource(path, revision = 0) {
  const [state, setState] = useState({ data: null, loading: true, error: "" });
  useEffect(() => {
    let live = true;
    setState({ data: null, loading: true, error: "" });
    api(path)
      .then((data) => live && setState({ data, loading: false, error: "" }))
      .catch(
        (e) =>
          live && setState({ data: null, loading: false, error: e.message }),
      );
    return () => {
      live = false;
    };
  }, [path, revision]);
  return state;
}
export function Loading() {
  return (
    <div className="empty">
      <LoaderCircle className="spin" />
      <p>Cargando información…</p>
    </div>
  );
}
export function ErrorBox({ children }) {
  return (
    <div className="error" role="alert">
      <AlertCircle size={18} />
      {children}
    </div>
  );
}
export function Empty({ text = "Todavía no hay registros." }) {
  return <p className="empty muted">{text}</p>;
}
export function Badge({ value }) {
  return (
    <span
      className={
        "badge " + (["CANCELADA", "INACTIVO"].includes(value) ? "muted" : "")
      }
    >
      {String(value || "—")
        .toLowerCase()
        .replaceAll("_", " ")}
    </span>
  );
}
export function PageHead({ title, description, action }) {
  return (
    <div className="page-head">
      <div>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
}
export function AddButton({ children, onClick }) {
  return (
    <button className="button primary" onClick={onClick}>
      <Plus size={16} />
      {children}
    </button>
  );
}
export function Table({ columns, rows, onRow, empty }) {
  if (!rows?.length) return <Empty text={empty} />;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key}>{c.label}</th>
            ))}
            {onRow && <th>Detalle</th>}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={r.id_auditoria ?? r.id_reserva ?? r._id ?? i}>
              {columns.map((c) => (
                <td key={c.key}>
                  {c.render ? c.render(r) : String(r[c.key] ?? "—")}
                </td>
              ))}
              {onRow && (
                <td>
                  <button
                    className="icon-button"
                    aria-label="Ver detalle"
                    onClick={() => onRow(r)}
                  >
                    <ChevronRight size={18} />
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
export function Field({ label, name, type = "text", options, ...props }) {
  const id = useId();
  return (
    <label className="field" htmlFor={id}>
      <span>{label}</span>
      {options ? (
        <select id={id} name={name} {...props}>
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      ) : type === "textarea" ? (
        <textarea id={id} name={name} rows={3} {...props} />
      ) : (
        <input id={id} name={name} type={type} {...props} />
      )}
    </label>
  );
}
export function Modal({ title, subtitle, children, onClose }) {
  const dialog = useRef(null);
  const titleId = useId();
  useEffect(() => {
    dialog.current.showModal();
  }, []);
  return (
    <dialog
      ref={dialog}
      className="modal"
      aria-labelledby={titleId}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
    >
      <div className="modal-heading">
        <div>
          <h2 id={titleId}>{title}</h2>
          <p>{subtitle}</p>
        </div>
        <button className="icon-button" onClick={onClose} aria-label="Cerrar">
          <X size={20} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
export function Form({
  children,
  onSubmit,
  onDone,
  submit = "Guardar",
  onCancel,
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function handle(event) {
    event.preventDefault();
    if (busy) return;
    const data = Object.fromEntries(new FormData(event.currentTarget));
    setBusy(true);
    setError("");
    try {
      await onSubmit(data);
      onDone?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <form onSubmit={handle}>
      {children}
      {error && <ErrorBox>{error}</ErrorBox>}
      <div className="form-footer">
        {onCancel && (
          <button className="button secondary" type="button" onClick={onCancel}>
            Cancelar
          </button>
        )}
        <button className="button primary" type="submit" disabled={busy}>
          {busy ? "Guardando…" : submit}
        </button>
      </div>
    </form>
  );
}
