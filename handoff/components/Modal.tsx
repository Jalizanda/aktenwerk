import { useEffect, useRef } from 'react';

type Size = 'sm' | 'md' | 'lg' | 'xl';
const WIDTH: Record<Size, number> = { sm: 420, md: 640, lg: 880, xl: 1120 };

type DotColor = 'orange' | 'green' | 'amber' | 'red' | 'blue';

/**
 * Aktenwerk Modal — size-presets sm/md/lg/xl.
 * See handoff/DIALOGS.md for full spec.
 */
export function Modal({
  open,
  title,
  eyebrow,
  size = 'md',
  statusDot,
  onClose,
  children,
  footerLeft,
  footerRight,
}: {
  open: boolean;
  title: string;
  eyebrow?: string;
  size?: Size;
  statusDot?: DotColor;
  onClose: () => void;
  children: React.ReactNode;
  footerLeft?: React.ReactNode;
  footerRight?: React.ReactNode;
}) {
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    // autofocus first focusable
    requestAnimationFrame(() => {
      const el = panelRef.current?.querySelector<HTMLElement>(
        'input, select, textarea, [contenteditable="true"], button:not([aria-label="Schließen"])',
      );
      el?.focus();
    });
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [open, onClose]);

  if (!open) return null;

  const dot: Record<DotColor, string> = {
    orange: 'var(--aw-orange)',
    green: 'var(--aw-green)',
    amber: 'var(--aw-amber)',
    red: 'var(--aw-red)',
    blue: 'var(--aw-blue)',
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="aw-dlg-title"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(11, 18, 32, 0.38)',
        backdropFilter: 'blur(2px)',
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'center',
        paddingTop: 64,
        zIndex: 1000,
        animation: 'aw-modal-fade 120ms cubic-bezier(0.4,0,0.2,1)',
      }}
    >
      <div
        ref={panelRef}
        style={{
          width: WIDTH[size],
          maxWidth: 'calc(100vw - 32px)',
          maxHeight: 'calc(100vh - 96px)',
          background: 'var(--aw-white)',
          border: '1px solid var(--aw-line)',
          borderRadius: 14,
          boxShadow: 'var(--aw-shadow-lg)',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          animation: 'aw-modal-in 160ms cubic-bezier(0.4,0,0.2,1)',
        }}
      >
        <header
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            padding: '14px 20px',
            borderBottom: '1px solid var(--aw-line)',
            minHeight: 52,
          }}
        >
          {statusDot && (
            <span
              aria-hidden
              style={{
                width: 8,
                height: 8,
                borderRadius: 4,
                background: dot[statusDot],
                flexShrink: 0,
              }}
            />
          )}
          <div style={{ flex: 1, minWidth: 0 }}>
            {eyebrow && (
              <div className="aw-eyebrow" style={{ marginBottom: 2 }}>
                {eyebrow}
              </div>
            )}
            <div
              id="aw-dlg-title"
              style={{
                fontSize: 15,
                fontWeight: 600,
                color: 'var(--aw-ink)',
                letterSpacing: '-0.015em',
                lineHeight: 1.2,
              }}
            >
              {title}
            </div>
          </div>
          <button
            aria-label="Schließen"
            onClick={onClose}
            style={{
              width: 28,
              height: 28,
              border: 'none',
              background: 'transparent',
              borderRadius: 6,
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'var(--aw-mute)',
              fontSize: 14,
            }}
            onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--aw-paper)')}
            onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
          >
            ✕
          </button>
        </header>

        <div style={{ padding: '18px 20px', overflow: 'auto', flex: 1 }}>{children}</div>

        {(footerLeft || footerRight) && (
          <footer
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: '14px 20px',
              borderTop: '1px solid var(--aw-line)',
              background: 'var(--aw-paper)',
              gap: 12,
              minHeight: 64,
            }}
          >
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{footerLeft}</div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{footerRight}</div>
          </footer>
        )}
      </div>

      <style>{`
        @keyframes aw-modal-fade { from { opacity: 0 } to { opacity: 1 } }
        @keyframes aw-modal-in {
          from { opacity: 0; transform: translateY(8px) }
          to   { opacity: 1; transform: translateY(0) }
        }
      `}</style>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Form helpers                                                              */
/* -------------------------------------------------------------------------- */

export function FormGrid({ columns = 3, children }: { columns?: 1 | 2 | 3; children: React.ReactNode }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: '14px 16px' }}>
      {children}
    </div>
  );
}

export function Field({
  label,
  required,
  span,
  children,
  hint,
  error,
}: {
  label: string;
  required?: boolean;
  span?: 1 | 2 | 3 | 'full';
  children: React.ReactNode;
  hint?: string;
  error?: string;
}) {
  const gridColumn = span === 'full' ? '1 / -1' : span ? `span ${span}` : undefined;
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 4, gridColumn }}>
      <span style={{ fontSize: 11, fontWeight: 500, color: 'var(--aw-mute)', letterSpacing: '0.01em' }}>
        {label}
        {required && <span style={{ color: 'var(--aw-orange)', marginLeft: 2, fontSize: 9 }}>*</span>}
      </span>
      {children}
      {hint && !error && <span style={{ fontSize: 11, color: 'var(--aw-mute)' }}>{hint}</span>}
      {error && <span style={{ fontSize: 11, color: 'var(--aw-red)', fontWeight: 500 }}>{error}</span>}
    </label>
  );
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      style={{
        height: 34,
        padding: '0 10px',
        background: 'var(--aw-white)',
        border: '1px solid var(--aw-line-strong)',
        borderRadius: 8,
        font: "500 12.5px/1 var(--aw-font-sans)",
        color: 'var(--aw-ink)',
        outline: 'none',
        ...props.style,
      }}
      onFocus={(e) => {
        e.currentTarget.style.borderColor = 'var(--aw-orange)';
        e.currentTarget.style.boxShadow = '0 0 0 3px var(--aw-orange-soft)';
        props.onFocus?.(e);
      }}
      onBlur={(e) => {
        e.currentTarget.style.borderColor = 'var(--aw-line-strong)';
        e.currentTarget.style.boxShadow = 'none';
        props.onBlur?.(e);
      }}
    />
  );
}
