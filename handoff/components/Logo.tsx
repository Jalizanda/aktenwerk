import markUrl from '../assets/logo/aktenwerk-mark.svg';
import markLightUrl from '../assets/logo/aktenwerk-mark-light.svg';
import markMonoUrl from '../assets/logo/aktenwerk-mark-mono.svg';
import lockupUrl from '../assets/logo/aktenwerk-lockup.svg';

type LogoProps = {
  size?: number;
  variant?: 'mark' | 'mark-light' | 'mark-mono' | 'lockup';
  withWordmark?: boolean;
  subline?: boolean;
  className?: string;
};

const SRC = {
  'mark': markUrl,
  'mark-light': markLightUrl,
  'mark-mono': markMonoUrl,
  'lockup': lockupUrl,
} as const;

/**
 * Aktenwerk Logo — canonical component.
 *
 * Usage:
 *   <Logo size={32} />                                // symbol only
 *   <Logo size={32} withWordmark />                   // symbol + "Aktenwerk"
 *   <Logo size={32} withWordmark subline />           // + SACHVERSTÄNDIGEN-SUITE
 *   <Logo variant="lockup" size={56} />               // single SVG lockup (for emails/PDFs)
 */
export function Logo({
  size = 32,
  variant = 'mark',
  withWordmark = false,
  subline = false,
  className,
}: LogoProps) {
  if (variant === 'lockup' || !withWordmark) {
    return (
      <img
        src={SRC[variant]}
        alt="Aktenwerk"
        height={size}
        style={{ display: 'block', height: size, width: 'auto' }}
        className={className}
      />
    );
  }

  // Symbol + inline wordmark (lets you tune size independently and keeps
  // accessibility-friendly text for screen readers).
  return (
    <div className={className} style={{ display: 'inline-flex', alignItems: 'center', gap: 10 }}>
      <img
        src={SRC[variant]}
        alt=""
        aria-hidden
        style={{ display: 'block', height: size, width: size }}
      />
      <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1 }}>
        <span style={{
          fontFamily: "'Geist', system-ui, sans-serif",
          fontSize: Math.round(size * 0.5),
          fontWeight: 600,
          letterSpacing: '-0.025em',
          color: 'var(--aw-ink, #0B1220)',
        }}>
          Akten<span style={{ color: 'var(--aw-orange, #F25C1F)' }}>werk</span>
        </span>
        {subline && (
          <span style={{
            fontFamily: "'Geist', system-ui, sans-serif",
            fontSize: Math.max(8, Math.round(size * 0.28)),
            fontWeight: 500,
            letterSpacing: '0.16em',
            textTransform: 'uppercase',
            color: 'var(--aw-mute, rgba(11,18,32,0.55))',
            marginTop: 3,
          }}>
            Sachverständigen-Suite
          </span>
        )}
      </div>
    </div>
  );
}
