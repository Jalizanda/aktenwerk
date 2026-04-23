import { colors } from '../tokens';

type PageHeaderProps = {
  eyebrow?: string;
  title: string;
  subtitle?: string;
  actions?: React.ReactNode;
  tabs?: string[];
  activeTab?: string;
  onTabChange?: (t: string) => void;
};

export function PageHeader({ eyebrow, title, subtitle, actions, tabs, activeTab, onTabChange }: PageHeaderProps) {
  return (
    <div style={{ padding: '22px 28px 0', background: colors.white, borderBottom: tabs ? 'none' : `1px solid ${colors.line}` }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 24, paddingBottom: tabs ? 14 : 22 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          {eyebrow && <div className="aw-eyebrow" style={{ marginBottom: 6 }}>{eyebrow}</div>}
          <h1 className="aw-h1">{title}</h1>
          {subtitle && <div style={{ fontSize: 13, color: colors.mute, marginTop: 6 }}>{subtitle}</div>}
        </div>
        {actions && <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{actions}</div>}
      </div>
      {tabs && (
        <div style={{ display: 'flex', gap: 2, borderBottom: `1px solid ${colors.line}` }}>
          {tabs.map(t => {
            const isActive = t === activeTab;
            return (
              <button key={t} onClick={() => onTabChange?.(t)} style={{
                fontFamily: 'inherit', fontSize: 12.5, padding: '10px 12px', background: 'transparent', border: 'none',
                color: isActive ? colors.ink : colors.mute, fontWeight: isActive ? 500 : 400, cursor: 'pointer',
                borderBottom: `2px solid ${isActive ? colors.orange : 'transparent'}`, marginBottom: -1,
              }}>{t}</button>
            );
          })}
        </div>
      )}
    </div>
  );
}
