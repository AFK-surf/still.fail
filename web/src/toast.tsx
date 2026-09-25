import { Toast } from "radix-ui";
import { createContext, useCallback, useContext, useState, type ReactNode } from "react";

const ToastContext = createContext<(message: string) => void>(() => {});

/** A short confirmation at the bottom of the screen, named after the action that happened. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<{ id: number; message: string } | null>(null);
  const show = useCallback((message: string) => setToast({ id: Date.now(), message }), []);
  return (
    <ToastContext.Provider value={show}>
      <Toast.Provider duration={2600} swipeDirection="down">
        {children}
        {toast && (
          <Toast.Root key={toast.id} className="toast" onOpenChange={(open) => { if (!open) setToast(null); }}>
            <Toast.Title>{toast.message}</Toast.Title>
          </Toast.Root>
        )}
        <Toast.Viewport className="toast-viewport" />
      </Toast.Provider>
    </ToastContext.Provider>
  );
}

export function useToast(): (message: string) => void {
  return useContext(ToastContext);
}
