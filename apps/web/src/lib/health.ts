import type { HealthStatus } from "@solo-compass/core";

/** Color used for the small confidence dot on each marker. */
export const healthColor: Record<HealthStatus, string> = {
  healthy: "#3FAE65",
  fading: "#E0B048",
  questioned: "#D9594C",
  may_be_gone: "#5A5A5A",
};

export const healthLabel: Record<HealthStatus, string> = {
  healthy: "fresh",
  fading: "fading",
  questioned: "questioned",
  may_be_gone: "may be gone",
};
