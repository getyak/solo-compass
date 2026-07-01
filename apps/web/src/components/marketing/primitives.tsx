import type { ReactNode, ButtonHTMLAttributes, AnchorHTMLAttributes } from "react";

/* ============================================================
   Button — primary / secondary / ghost
   Doc: WEB_LANDING_DESIGN.md §5.1
   ============================================================ */

type Variant = "primary" | "secondary" | "ghost";

const buttonBase =
  "inline-flex items-center justify-center h-12 px-6 rounded-full font-body text-body-md font-medium transition-all duration-fast ease-standard focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent focus-visible:outline-offset-2";

const buttonVariant: Record<Variant, string> = {
  primary:
    "bg-accent text-bg-warm hover:bg-accent-hover active:scale-[0.98] shadow-sm hover:shadow-lg hover:-translate-y-[1px]",
  secondary:
    "bg-transparent text-fg-primary border border-border-default hover:border-fg-primary hover:bg-surface-white active:scale-[0.98]",
  ghost:
    "bg-transparent text-fg-muted hover:text-fg-primary underline-offset-4 hover:underline",
};

export function Button({
  variant = "primary",
  className = "",
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return <button className={`${buttonBase} ${buttonVariant[variant]} ${className}`} {...rest} />;
}

export function ButtonLink({
  variant = "primary",
  className = "",
  ...rest
}: AnchorHTMLAttributes<HTMLAnchorElement> & { variant?: Variant }) {
  return <a className={`${buttonBase} ${buttonVariant[variant]} ${className}`} {...rest} />;
}

/* ============================================================
   Chip — eyebrow style
   ============================================================ */

type ChipTone = "sun" | "accent" | "success" | "warning";

const chipTone: Record<ChipTone, string> = {
  sun: "bg-sun-gold-soft text-sun-gold-deep border-sun-gold-soft",
  accent: "bg-accent-soft text-accent border-accent-border",
  success: "bg-success-soft text-success-text border-success-text/20",
  warning: "bg-warning-soft text-warning-text border-warning-text/20",
};

export function Chip({
  tone = "accent",
  children,
  className = "",
}: {
  tone?: ChipTone;
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 font-mono text-[11px] font-medium uppercase tracking-[0.16em] ${chipTone[tone]} ${className}`}
    >
      {children}
    </span>
  );
}

/* ============================================================
   Eyebrow — "since 2026" style · with bullet dot
   ============================================================ */

export function Eyebrow({
  dot = "sun",
  children,
  className = "",
}: {
  dot?: "sun" | "accent" | "omen" | "none";
  children: ReactNode;
  className?: string;
}) {
  const dotColor: Record<string, string> = {
    sun: "bg-sun-gold",
    accent: "bg-accent",
    omen: "bg-omen-gold",
    none: "hidden",
  };
  return (
    <span className={`inline-flex items-center gap-3 ds-eyebrow ${className}`}>
      <span className={`h-1.5 w-1.5 rounded-full ${dotColor[dot]}`} aria-hidden />
      <span>{children}</span>
    </span>
  );
}

/* ============================================================
   Section — vertical rhythm wrapper
   ============================================================ */

export function Section({
  id,
  className = "",
  style,
  children,
}: {
  id?: string;
  className?: string;
  style?: React.CSSProperties;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className={`py-section-y-sm md:py-section-y ${className}`}
      style={style}
    >
      {children}
    </section>
  );
}

/* ============================================================
   IPhoneFrame — brand-critical phone mockup
   Doc: WEB_LANDING_DESIGN.md §5.4
   ============================================================ */

export function IPhoneFrame({
  children,
  className = "",
  tilt = false,
}: {
  children: ReactNode;
  className?: string;
  tilt?: boolean;
}) {
  return (
    <div
      className={`relative ${tilt ? "rotate-[2deg]" : ""} ${className}`}
      style={{
        transformOrigin: "center",
      }}
    >
      {/* Outer bezel */}
      <div
        className="relative overflow-hidden rounded-[48px] bg-[#0e0c0a] p-[10px] shadow-2xl"
        style={{
          boxShadow:
            "0 40px 80px -20px rgba(31, 26, 20, 0.25), 0 0 0 1px rgba(31, 26, 20, 0.08), inset 0 0 0 2px rgba(255, 255, 255, 0.02)",
        }}
      >
        {/* Screen */}
        <div className="relative overflow-hidden rounded-[38px] bg-bg-warm">
          {/* Dynamic Island */}
          <div className="absolute left-1/2 top-2 z-10 h-[26px] w-[92px] -translate-x-1/2 rounded-full bg-[#0e0c0a]" />
          {children}
        </div>
      </div>
    </div>
  );
}
