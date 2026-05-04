/**
 * Solo Score — how friendly is this place to someone alone?
 *
 * This is the product's signature label. No other travel product computes it.
 * Every existing rating system implicitly assumes "you and someone".
 *
 * Range 0–10. Sub-scores let the UI explain *why*.
 */

export interface SoloScore {
  /** 0–10. Composite, surfaced as a single badge. */
  readonly overall: number;

  readonly breakdown: {
    /** Are there single-person tables? Bar seating? */
    readonly seatingFriendly: number; // 0-10
    /** What % of typical patrons come alone? */
    readonly soloPatronRatio: number; // 0-10
    /** Will staff hover, ask "anyone joining?", check on you frequently? */
    readonly staffPressure: number; // 0-10 (high = leaves you alone, good)
    /** Can you order/consume something appropriate for one person? (no min spend, no shareable-only menus) */
    readonly soloPortioning: number; // 0-10
    /** Does the ambiance feel okay alone — or is it explicitly couples/groups? */
    readonly ambianceFit: number; // 0-10
    /** Is it safe to be there alone — at the time of day people typically go? */
    readonly safety: number; // 0-10
  };

  /** Plain-language hint shown under the score. e.g. "Order at the bar, sit upstairs." */
  readonly hint?: string;

  /** How many solo travelers contributed to this score. Visible. */
  readonly basedOnCount: number;
}
