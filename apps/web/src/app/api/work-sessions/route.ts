import { NextResponse } from "next/server";
import { z } from "zod";
import { WorkSessionRateLimitError, WorkSessionValidationError } from "@solo-compass/data";
import {
  authenticatedUserId,
  getEvidenceRepo,
  getExperiencesRepo,
  getWorkSessionRepo,
} from "@/lib/repos";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const BodySchema = z
  .object({
    idempotencyKey: z.string().trim().min(8).max(160),
    experienceId: z.string().trim().min(1).max(160),
    plannedTaskKind: z.string().trim().min(1).max(60),
    startedAt: z.string().datetime({ offset: true }),
    endedAt: z.string().datetime({ offset: true }),
    outcome: z.enum(["completed", "partially_completed", "abandoned"]),
    failureReason: z
      .enum([
        "place_closed",
        "no_seat",
        "wifi_unreliable",
        "too_noisy",
        "no_power",
        "video_call_not_allowed",
        "long_stay_pressure",
        "minimum_spend",
        "other",
      ])
      .optional(),
    placeWasOpen: z.boolean().optional(),
    wifiReliability: z.number().int().min(1).max(5).optional(),
    noiseLevel: z.number().int().min(1).max(5).optional(),
    powerAvailable: z.boolean().optional(),
    videoCallWorked: z.boolean().optional(),
    longStayAccepted: z.boolean().optional(),
    minimumSpend: z
      .object({
        amount: z.number().nonnegative(),
        currency: z.string().regex(/^[A-Za-z]{3}$/),
      })
      .optional(),
  })
  .strict();

export async function POST(
  request: Request,
): Promise<
  NextResponse<
    { sessionId: string; materializedFeatureKeys: readonly string[] } | { error: string }
  >
> {
  const userId = await authenticatedUserId(request);
  if (!userId) return NextResponse.json({ error: "authentication required" }, { status: 401 });
  const body: unknown = await request.json().catch(() => undefined);
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: parsed.error.issues
          .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
          .join("; "),
      },
      { status: 400 },
    );
  }

  try {
    const experience = await getExperiencesRepo().findById(parsed.data.experienceId);
    if (!experience) return NextResponse.json({ error: "experience not found" }, { status: 404 });
    const evidence = getEvidenceRepo();
    const snapshots = await evidence.getSnapshotsForExperiences([experience.id]);
    let placeId = snapshots.get(experience.id)?.placeId;
    if (!placeId) {
      const place = await evidence.upsertPlaceIdentity({
        provider: "experience_anchor",
        externalId: experience.id,
        canonicalName:
          experience.location.placeNameRomanized ??
          experience.location.placeNameLocal ??
          experience.title,
        coordinates: experience.location.coordinates,
        basicCategory: experience.category,
        identityConfidence: 0.6,
        metadata: { origin: "first_party_work_session" },
      });
      await evidence.linkExperience({
        experienceId: experience.id,
        placeId: place.id,
        confidence: 0.6,
        method: "first_party_session_anchor",
      });
      placeId = place.id;
    }

    const result = await getWorkSessionRepo().record({
      userId,
      experienceId: experience.id,
      placeId,
      plannedTaskKind: parsed.data.plannedTaskKind,
      startedAt: parsed.data.startedAt,
      endedAt: parsed.data.endedAt,
      outcome: parsed.data.outcome,
      ...(parsed.data.failureReason ? { failureReason: parsed.data.failureReason } : {}),
      ...(parsed.data.placeWasOpen !== undefined ? { placeWasOpen: parsed.data.placeWasOpen } : {}),
      ...(parsed.data.wifiReliability !== undefined
        ? { wifiReliability: parsed.data.wifiReliability }
        : {}),
      ...(parsed.data.noiseLevel !== undefined ? { noiseLevel: parsed.data.noiseLevel } : {}),
      ...(parsed.data.powerAvailable !== undefined
        ? { powerAvailable: parsed.data.powerAvailable }
        : {}),
      ...(parsed.data.videoCallWorked !== undefined
        ? { videoCallWorked: parsed.data.videoCallWorked }
        : {}),
      ...(parsed.data.longStayAccepted !== undefined
        ? { longStayAccepted: parsed.data.longStayAccepted }
        : {}),
      ...(parsed.data.minimumSpend ? { minimumSpend: parsed.data.minimumSpend } : {}),
      idempotencyKey: parsed.data.idempotencyKey,
    });
    return NextResponse.json(
      {
        sessionId: result.session.id,
        materializedFeatureKeys: result.materializedFeatureKeys,
      },
      { status: 201 },
    );
  } catch (error) {
    if (error instanceof WorkSessionValidationError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    if (error instanceof WorkSessionRateLimitError) {
      return NextResponse.json({ error: error.message }, { status: 429 });
    }
    console.error("work session recording failed", error);
    return NextResponse.json({ error: "work session recording failed" }, { status: 502 });
  }
}
