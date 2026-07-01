import type { ReactNode } from "react";

type Width = "narrow" | "default" | "wide";

const widthClass: Record<Width, string> = {
  narrow: "max-w-narrow",
  default: "max-w-default",
  wide: "max-w-wide",
};

export function Container({
  width = "default",
  className = "",
  children,
}: {
  width?: Width;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={`mx-auto w-full px-6 md:px-10 ${widthClass[width]} ${className}`}>
      {children}
    </div>
  );
}
