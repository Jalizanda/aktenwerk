import { Logo } from './Logo';
import { colors } from '../tokens';

/**
 * Sidebar — 232px, white bg, ink text.
 * Active item: orange-soft bg, ink text 500, orange icon, 2.5px orange bar left-outside.
 */

type NavItem = { key: string; icon: React.ReactNode; label: string; badge?: number | string };
type NavGroup = { title: string; items: NavItem[] };

export function Sidebar({ groups, active, user }: {
  groups: NavGroup[];
  active: string;
  user?: { name: string; role: string; initials: string };
}) {
  return (
    <aside style={{
      width: 232, flexShrink: 0,
      background: colors.white, borderRight: `1px solid ${colors.line}`,
      display: 'flex', flexDirection: 'column',
    }}>
      <div style={{ padding: '18px 18px 16px', borderBottom: `1px solid ${colors.line}` }}>
        <Logo size={32} withWordmark subline />
      </div>

      <nav style={{ flex: 1, padding: '12px 10px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 14 }}>
        {groups.map(g => (
          <div key={g.title}>
            <div style={{ fontSize: 10, letterSpacing: '0.12em', textTransform: 'uppercase', color: colors.muteSoft, fontWeight: 600, padding: '0 10px 6px' }}>{g.title}</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              {g.items.map(it => {
                const isActive = it.key === active;
                return (
                  <a key={it.key} style={{
                    display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', borderRadius: 6,
                    fontSize: 13, color: isActive ? colors.ink : 'rgba(11,18,32,0.72)',
                    background: isActive ? colors.orangeSoft : 'transparent',
                    fontWeight: isActive ? 500 : 400, cursor: 'pointer', position: 'relative',
                  }}>
                    {isActive && <div style={{ position: 'absolute', left: -10, top: 6, bottom: 6, width: 2.5, background: colors.orange, borderRadius: 2 }} />}
                    <span style={{ color: isActive ? colors.orange : colors.mute, display: 'flex' }}>{it.icon}</span>
                    <span>{it.label}</span>
                    {it.badge != null && <span style={{ marginLeft: 'auto', fontSize: 10.5, fontWeight: 500, color: colors.mute, background: colors.paper, padding: '2px 6px', borderRadius: 4, border: `1px solid ${colors.line}` }}>{it.badge}</span>}
                  </a>
                );
              })}
            </div>
          </div>
        ))}
      </nav>

      {user && (
        <div style={{ padding: '12px 14px', borderTop: `1px solid ${colors.line}`, display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 28, height: 28, borderRadius: 14, background: colors.orange, color: colors.white, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, fontWeight: 600 }}>{user.initials}</div>
          <div style={{ flex: 1, fontSize: 12, color: colors.ink }}>
            <div style={{ fontWeight: 500 }}>{user.name}</div>
            <div style={{ fontSize: 10, color: colors.mute }}>{user.role}</div>
          </div>
        </div>
      )}
    </aside>
  );
}
