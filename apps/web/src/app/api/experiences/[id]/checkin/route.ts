/**
 * POST /api/experiences/[id]/checkin
 *
 * Body (optional): { rating?: 1..5 }
 *
 * Idempotent — repeated calls for the same (anon cookie, experience) update
 * the rating in place. Mints the anon cookie on first call.
 */

import { NextResponse } from "next/server";
import { z } from "zod";
import { anonCookieOptions, readOrMintAnonId } from "@/lib/anon-cookie";
import { getCompletionsRepo } from "@/lib/repos";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const BodySchema = z
  .object({
    rating: z.number().int().min(1).max(5).optional(),
  })
  .strict();

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<NextResponse> {
  const { id } = await context.params;
  if (!id || !id.startsWith("exp_")) {
    return NextResponse.json({ error: "invalid experience id" }, { status: 400 });
  }

  let body: z.infer<typeof BodySchema> = {};
  if (request.headers.get("content-length") && request.headers.get("content-length") !== "0") {
    try {
      const json = (await request.json()) as unknown;
      const parsed = BodySchema.safeParse(json);
      if (!parsed.success) {
        return NextResponse.json({ error: parsed.error.message }, { status: 400 });
      }
      body = parsed.data;
    } catch {
      return NextResponse.json({ error: "invalid JSON body" }, { status: 400 });
    }
  }

  const { id: anonId, minted } = await readOrMintAnonId();

  try {
    const repo = getCompletionsRepo();
    await repo.record({ anonUserId: anonId, experienceId: id, rating: body.rating });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error("checkin failed", err);
    return NextResponse.json({ error: "checkin failed" }, { status: 502 });
  }

  const res = NextResponse.json({ ok: true });
  if (minted) {
    res.cookies.set({ ...anonCookieOptions, value: anonId });
  }
  return res;
}
