import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

export type ToastKind = 'success' | 'warning' | 'error';
type Toast = { id: number; kind: ToastKind; message: string };
type ToastAPI = {
 success: (message: string) => void;
 warning: (message: string) => void;
 error: (message: string) => void;
 dismiss: (id: number) => void;
};
const ToastContext = createContext<ToastAPI | null>(null);
let nextToastId = 0;
const MAX_TOASTS = 3;
const duration: Record<ToastKind, number | null> = {success: 4000, warning: 8000, error: null};

function ToastItem({item, dismiss}: {item: Toast; dismiss: (id: number) => void}) {
 useEffect(() => {
  const ms = duration[item.kind];
  if (ms === null) return;
  const handle = window.setTimeout(() => dismiss(item.id), ms);
  return () => window.clearTimeout(handle);
 }, [item.id, item.kind, dismiss]);
 const alert = item.kind === 'error';
 return (
  <section className={`warning toast ${item.kind}`} role={alert ? 'alert' : 'status'} aria-live={alert ? 'assertive' : 'polite'}>
   <span className="toast-message">{item.message}</span>
   <button type="button" aria-label="Fechar notificação" onClick={() => dismiss(item.id)}>×</button>
  </section>
 );
}

export function ToastProvider({children}: {children: ReactNode}) {
 const [items, setItems] = useState<Toast[]>([]);
 const dismiss = useCallback((id: number) => {
  setItems(prev => prev.filter(item => item.id !== id));
 }, []);
 const notify = useCallback((kind: ToastKind, message: string) => {
  if (!message.trim()) return;
  const id = ++nextToastId;
  // FIFO: on the fourth notification, remove the oldest, regardless of severity.
  setItems(prev => [...prev, {id, kind, message}].slice(-MAX_TOASTS));
 }, []);
 const api = useMemo<ToastAPI>(() => ({
  success: (message: string) => notify('success', message),
  warning: (message: string) => notify('warning', message),
  error: (message: string) => notify('error', message),
  dismiss,
 }), [notify, dismiss]);
 return <ToastContext.Provider value={api}>
  {children}
  <div className="toast-region" aria-label="Notificações" aria-live="off">
   {items.map(item => <ToastItem key={item.id} item={item} dismiss={dismiss} />)}
  </div>
 </ToastContext.Provider>;
}

export function useToast(): ToastAPI {
 const context = useContext(ToastContext);
 if (!context) throw new Error('useToast precisa de ToastProvider.');
 return context;
}
