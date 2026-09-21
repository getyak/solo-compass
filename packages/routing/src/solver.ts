import type {
  EvidenceStatus,
  FeatureConstraint,
  JsonValue,
  LocalTimeWindow,
  MatrixCell,
  RouteCandidate,
  RouteFallback,
  RouteFeatureFact,
  RoutePlanResult,
  RoutePlannerOptions,
  RouteRejectionCode,
  RouteRejectionSummary,
  RouteTask,
  RouteWarning,
  ScheduledStop,
  TravelTimeMatrix,
  WorkdayPlanIntent,
} from "./types";

const SOLVER_VERSION = "workday-beam-v1";
const DEFAULT_BEAM_WIDTH = 250;
const DEFAULT_FALLBACK_EXTRA_MINUTES = 10;
const SOFT_CONSTRAINT_PENALTY = 18;
const UNKNOWN_HOURS_PENALTY = 12;
const UNKNOWN_STATUS_PENALTY = 5;

interface SearchState {
  stops: ScheduledStop[];
  usedCandidateIds: Set<string>;
  cursorNodeId: string;
  currentMinute: number;
  totalTravelMinutes: number;
  totalDistanceMeters: number;
  hasCompleteDistance: boolean;
  totalWaitMinutes: number;
  totalEstimatedSpend: number;
  spendCurrency?: string;
  hasUnknownSpend: boolean;
  score: number;
}

interface CandidateEvaluation {
  stop: ScheduledStop;
  nodeId: string;
  scoreDelta: number;
  totalTravelMinutes: number;
  totalDistanceMeters: number;
  hasCompleteDistance: boolean;
  totalWaitMinutes: number;
  totalEstimatedSpend: number;
  spendCurrency?: string;
  hasUnknownSpend: boolean;
}

interface ScheduleResult {
  arrivalMinute: number;
  startMinute: number;
  endMinute: number;
  waitMinutes: number;
  warnings: RouteWarning[];
  riskPenalty: number;
}

export function planWorkdayRoute(
  intent: WorkdayPlanIntent,
  candidates: RouteCandidate[],
  matrix: TravelTimeMatrix,
  options: RoutePlannerOptions = {},
): RoutePlanResult {
  validateInputs(intent, candidates);
  const beamWidth = options.beamWidth ?? DEFAULT_BEAM_WIDTH;
  if (!Number.isInteger(beamWidth) || beamWidth < 1) {
    throw new Error("beamWidth must be a positive integer");
  }

  const candidateById = new Map(candidates.map((candidate) => [candidate.id, candidate]));
  let states: SearchState[] = [initialState(intent)];
  let exploredStates = 0;

  for (const task of intent.tasks) {
    const nextStates: SearchState[] = [];
    const rejectionCounts = new Map<RouteRejectionCode, number>();
    const taskCandidates = allowedCandidates(task, candidates, candidateById, rejectionCounts);

    for (const state of states) {
      for (const candidate of taskCandidates) {
        exploredStates += 1;
        if (state.usedCandidateIds.has(candidate.id)) {
          addRejection(rejectionCounts, "candidate_reused");
          continue;
        }
        const evaluated = evaluateCandidate(intent, task, candidate, state, matrix);
        if ("rejection" in evaluated) {
          addRejection(rejectionCounts, evaluated.rejection);
          continue;
        }
        nextStates.push(advanceState(state, candidate, evaluated));
      }
    }

    if (nextStates.length === 0) {
      return {
        status: "unsatisfiable",
        failedTaskId: task.id,
        rejections: rejectionSummary(rejectionCounts),
        exploredStates,
      };
    }

    states = nextStates.sort(compareStates).slice(0, beamWidth);
  }

  const best = states.sort(compareStates)[0];
  if (!best) {
    const firstTask = intent.tasks[0];
    return {
      status: "unsatisfiable",
      failedTaskId: firstTask?.id ?? "unknown",
      rejections: [],
      exploredStates,
    };
  }

  const fallbacks = chooseFallbacks(intent, candidates, matrix, best);
  const warnings = best.stops.flatMap((stop) => stop.warnings);
  return {
    status: "solved",
    solution: {
      stops: best.stops,
      fallbacks,
      score: round(best.score, 3),
      totalTravelMinutes: best.totalTravelMinutes,
      ...(best.hasCompleteDistance ? { totalDistanceMeters: best.totalDistanceMeters } : {}),
      totalWaitMinutes: best.totalWaitMinutes,
      ...(!best.hasUnknownSpend && best.spendCurrency
        ? {
            totalEstimatedSpend: {
              amount: round(best.totalEstimatedSpend, 2),
              currency: best.spendCurrency,
            },
          }
        : {}),
      budgetEstimateIncomplete: best.hasUnknownSpend,
      startsAtMinute: intent.startMinute,
      endsAtMinute: best.currentMinute,
      warnings,
      solver: {
        version: SOLVER_VERSION,
        exploredStates,
        beamWidth,
        matrixMode: matrix.mode,
      },
    },
  };
}

function initialState(intent: WorkdayPlanIntent): SearchState {
  return {
    stops: [],
    usedCandidateIds: new Set(),
    cursorNodeId: intent.originNodeId,
    currentMinute: intent.startMinute,
    totalTravelMinutes: 0,
    totalDistanceMeters: 0,
    hasCompleteDistance: true,
    totalWaitMinutes: 0,
    totalEstimatedSpend: 0,
    ...(intent.budget ? { spendCurrency: normalizeCurrency(intent.budget.currency) } : {}),
    hasUnknownSpend: false,
    score: 0,
  };
}

function allowedCandidates(
  task: RouteTask,
  all: RouteCandidate[],
  byId: Map<string, RouteCandidate>,
  rejections: Map<RouteRejectionCode, number>,
): RouteCandidate[] {
  if (!task.candidateIds) return all;
  const allowed: RouteCandidate[] = [];
  for (const id of task.candidateIds) {
    const candidate = byId.get(id);
    if (candidate) allowed.push(candidate);
    else addRejection(rejections, "candidate_not_allowed");
  }
  return allowed;
}

function evaluateCandidate(
  intent: WorkdayPlanIntent,
  task: RouteTask,
  candidate: RouteCandidate,
  state: SearchState,
  matrix: TravelTimeMatrix,
): CandidateEvaluation | { rejection: RouteRejectionCode } {
  if (
    candidate.operatingStatus === "temporarily_closed" ||
    candidate.operatingStatus === "permanently_closed"
  ) {
    return { rejection: "confirmed_closed" };
  }

  const constraintResult = evaluateConstraints(candidate, task.constraints ?? []);
  if (constraintResult.hardFailure) return { rejection: "hard_constraint_unmet" };

  const nodeId = candidate.nodeId ?? candidate.id;
  const leg = matrixCell(matrix, state.cursorNodeId, nodeId);
  if (!leg || leg.durationMinutes === null) return { rejection: "missing_matrix_leg" };

  const travelMinutes = normalizeDuration(leg.durationMinutes);
  const schedule = scheduleCandidate(intent, task, candidate, state.currentMinute + travelMinutes);
  if ("rejection" in schedule) return schedule;

  const totalTravelMinutes = state.totalTravelMinutes + travelMinutes;
  if (intent.maxTravelMinutes !== undefined && totalTravelMinutes > intent.maxTravelMinutes) {
    return { rejection: "travel_budget" };
  }
  const totalWaitMinutes = state.totalWaitMinutes + schedule.waitMinutes;
  if (intent.maxWaitMinutes !== undefined && totalWaitMinutes > intent.maxWaitMinutes) {
    return { rejection: "wait_budget" };
  }
  const spend = candidate.estimatedSpend;
  if (
    intent.budget !== undefined &&
    (!spend || spend.status === "unknown") &&
    !intent.allowUnknownSpend
  ) {
    return { rejection: "money_budget_unknown" };
  }
  const normalizedSpendCurrency =
    spend?.status === "known" ? normalizeCurrency(spend.currency) : undefined;
  const currencyMismatch =
    spend?.status === "known" &&
    ((intent.budget !== undefined &&
      normalizedSpendCurrency !== normalizeCurrency(intent.budget.currency)) ||
      (state.spendCurrency !== undefined && normalizedSpendCurrency !== state.spendCurrency));
  if (currencyMismatch && intent.budget !== undefined) {
    return { rejection: "money_budget_currency_mismatch" };
  }
  const knownSpend = spend?.status === "known" && !currencyMismatch ? spend.amount : 0;
  const spendUnknown = !spend || spend.status === "unknown" || currencyMismatch;
  const totalEstimatedSpend = state.totalEstimatedSpend + knownSpend;
  if (intent.budget !== undefined && totalEstimatedSpend > intent.budget.maxAmount) {
    return { rejection: "money_budget" };
  }

  const distance = leg.distanceMeters;
  const warnings = [...schedule.warnings, ...constraintResult.warnings];
  if (spendUnknown) {
    warnings.push({
      code: currencyMismatch ? "spend_currency_mismatch" : "spend_unknown",
      candidateId: candidate.id,
      message: currencyMismatch
        ? "Expected spend uses a different currency and was excluded from the total."
        : "Expected spend is unknown.",
    });
  }
  const scoreDelta =
    clamp(candidate.utility, 0, 1) * 100 -
    travelMinutes * 0.7 -
    schedule.waitMinutes * 0.2 -
    schedule.riskPenalty -
    constraintResult.penalty;
  return {
    stop: {
      taskId: task.id,
      taskKind: task.kind,
      candidateId: candidate.id,
      experienceId: candidate.experienceId,
      ...(candidate.placeId ? { placeId: candidate.placeId } : {}),
      title: candidate.title,
      arrivalMinute: schedule.arrivalMinute,
      startMinute: schedule.startMinute,
      endMinute: schedule.endMinute,
      travelFromPreviousMinutes: travelMinutes,
      ...(distance === undefined || distance === null
        ? {}
        : { distanceFromPreviousMeters: Math.max(0, Math.round(distance)) }),
      waitMinutes: schedule.waitMinutes,
      ...(spend?.status === "known"
        ? {
            estimatedSpend: {
              amount: spend.amount,
              currency: normalizedSpendCurrency!,
            },
          }
        : {}),
      warnings,
    },
    nodeId,
    scoreDelta,
    totalTravelMinutes,
    totalDistanceMeters:
      state.totalDistanceMeters +
      (distance === undefined || distance === null ? 0 : Math.round(distance)),
    hasCompleteDistance: state.hasCompleteDistance && distance !== undefined && distance !== null,
    totalWaitMinutes,
    totalEstimatedSpend,
    ...(state.spendCurrency
      ? { spendCurrency: state.spendCurrency }
      : normalizedSpendCurrency
        ? { spendCurrency: normalizedSpendCurrency }
        : {}),
    hasUnknownSpend: state.hasUnknownSpend || spendUnknown,
  };
}

function scheduleCandidate(
  intent: WorkdayPlanIntent,
  task: RouteTask,
  candidate: RouteCandidate,
  arrivalMinute: number,
): ScheduleResult | { rejection: RouteRejectionCode } {
  const earliest = Math.max(arrivalMinute, task.earliestStartMinute ?? intent.startMinute);
  const latestEnd = Math.min(task.latestEndMinute ?? intent.endMinute, intent.endMinute);
  const requirement = task.openingRequirement ?? "known_open";
  const warnings: RouteWarning[] = [];
  let riskPenalty = 0;
  let startMinute = earliest;

  if (requirement !== "ignore") {
    const evidence = candidate.openingHours ?? { status: "unknown" as const };
    if (evidence.status === "unknown") {
      if (requirement === "known_open" && !intent.allowUnknownOpeningHours) {
        return { rejection: "opening_hours_unknown" };
      }
      warnings.push({
        code: "opening_hours_unknown",
        candidateId: candidate.id,
        message: "Opening hours are unknown and should be verified before departure.",
      });
      riskPenalty += UNKNOWN_HOURS_PENALTY;
    } else {
      const fitting = findFittingWindow(evidence.windows, earliest, task.durationMinutes);
      if (!fitting) return { rejection: "outside_opening_window" };
      startMinute = Math.max(earliest, fitting.startMinute);
    }
  }

  const endMinute = startMinute + task.durationMinutes;
  if (task.latestEndMinute !== undefined && endMinute > task.latestEndMinute) {
    return { rejection: "task_time_window" };
  }
  if (endMinute > latestEnd) return { rejection: "day_time_window" };

  if (candidate.operatingStatus === "unknown") {
    warnings.push({
      code: "operating_status_unknown",
      candidateId: candidate.id,
      message: "The place has not been recently confirmed active.",
    });
    riskPenalty += UNKNOWN_STATUS_PENALTY;
  }

  return {
    arrivalMinute,
    startMinute,
    endMinute,
    waitMinutes: startMinute - arrivalMinute,
    warnings,
    riskPenalty,
  };
}

function evaluateConstraints(
  candidate: RouteCandidate,
  constraints: FeatureConstraint[],
): { hardFailure: boolean; penalty: number; warnings: RouteWarning[] } {
  let penalty = 0;
  const warnings: RouteWarning[] = [];
  for (const constraint of constraints) {
    const fact = candidate.features[constraint.featureKey];
    const acceptable = constraint.acceptableStatuses ?? ["resolved"];
    const minimumConfidence = constraint.minimumConfidence ?? 0;
    const evidenceAccepted =
      fact !== undefined &&
      acceptable.includes(fact.status) &&
      fact.confidence >= minimumConfidence;
    const valueAccepted = fact !== undefined && compareFeature(fact.value, constraint);
    if (evidenceAccepted && valueAccepted) continue;
    if (constraint.hard ?? true) return { hardFailure: true, penalty, warnings };

    penalty += SOFT_CONSTRAINT_PENALTY;
    const evidenceWarning = warningForEvidenceStatus(
      candidate.id,
      constraint.featureKey,
      fact,
      minimumConfidence,
    );
    warnings.push(
      evidenceWarning ?? {
        code: "soft_constraint_unmet",
        candidateId: candidate.id,
        featureKey: constraint.featureKey,
        message: `Soft constraint ${constraint.featureKey} is not satisfied.`,
      },
    );
  }
  return { hardFailure: false, penalty, warnings };
}

function warningForEvidenceStatus(
  candidateId: string,
  featureKey: string,
  fact: RouteFeatureFact | undefined,
  minimumConfidence: number,
): RouteWarning | undefined {
  const status: EvidenceStatus | undefined = fact?.status;
  if (status === "stale") {
    return {
      code: "stale_evidence",
      candidateId,
      featureKey,
      message: `${featureKey} is supported only by stale evidence.`,
    };
  }
  if (status === "conflicted") {
    return {
      code: "conflicted_evidence",
      candidateId,
      featureKey,
      message: `${featureKey} has conflicting evidence.`,
    };
  }
  if (fact && fact.confidence < minimumConfidence) {
    return {
      code: "low_confidence_evidence",
      candidateId,
      featureKey,
      message: `${featureKey} confidence is below the decision threshold.`,
    };
  }
  return undefined;
}

function compareFeature(actual: JsonValue, constraint: FeatureConstraint): boolean {
  switch (constraint.operator) {
    case "truthy":
      return Boolean(actual);
    case "eq":
      return JSON.stringify(actual) === JSON.stringify(constraint.expected);
    case "gte":
      return (
        typeof actual === "number" &&
        typeof constraint.expected === "number" &&
        actual >= constraint.expected
      );
    case "lte":
      return (
        typeof actual === "number" &&
        typeof constraint.expected === "number" &&
        actual <= constraint.expected
      );
    case "in":
      return (
        Array.isArray(constraint.expected) &&
        constraint.expected.some((item) => JSON.stringify(item) === JSON.stringify(actual))
      );
    case "contains":
      return (
        Array.isArray(actual) &&
        actual.some((item) => JSON.stringify(item) === JSON.stringify(constraint.expected))
      );
  }
}

function findFittingWindow(
  windows: LocalTimeWindow[],
  earliest: number,
  durationMinutes: number,
): LocalTimeWindow | undefined {
  return [...windows]
    .sort((a, b) => a.startMinute - b.startMinute || a.endMinute - b.endMinute)
    .find((window) => Math.max(earliest, window.startMinute) + durationMinutes <= window.endMinute);
}

function advanceState(
  state: SearchState,
  candidate: RouteCandidate,
  evaluated: CandidateEvaluation,
): SearchState {
  return {
    stops: [...state.stops, evaluated.stop],
    usedCandidateIds: new Set([...state.usedCandidateIds, candidate.id]),
    cursorNodeId: evaluated.nodeId,
    currentMinute: evaluated.stop.endMinute,
    totalTravelMinutes: evaluated.totalTravelMinutes,
    totalDistanceMeters: evaluated.totalDistanceMeters,
    hasCompleteDistance: evaluated.hasCompleteDistance,
    totalWaitMinutes: evaluated.totalWaitMinutes,
    totalEstimatedSpend: evaluated.totalEstimatedSpend,
    ...(evaluated.spendCurrency ? { spendCurrency: evaluated.spendCurrency } : {}),
    hasUnknownSpend: evaluated.hasUnknownSpend,
    score: state.score + evaluated.scoreDelta,
  };
}

function chooseFallbacks(
  intent: WorkdayPlanIntent,
  candidates: RouteCandidate[],
  matrix: TravelTimeMatrix,
  state: SearchState,
): RouteFallback[] {
  const primaryIds = new Set(state.stops.map((stop) => stop.candidateId));
  const candidateById = new Map(candidates.map((candidate) => [candidate.id, candidate]));
  const taskById = new Map(intent.tasks.map((task) => [task.id, task]));
  const maxExtra = intent.fallbackMaxExtraTravelMinutes ?? DEFAULT_FALLBACK_EXTRA_MINUTES;
  const fallbacks: RouteFallback[] = [];

  for (const [index, primary] of state.stops.entries()) {
    const task = taskById.get(primary.taskId);
    const primaryCandidate = candidateById.get(primary.candidateId);
    if (!task || !primaryCandidate) continue;

    const previousStop = index === 0 ? undefined : state.stops[index - 1];
    const nextStop = state.stops[index + 1];
    const previousNode = previousStop
      ? (candidateById.get(previousStop.candidateId)?.nodeId ?? previousStop.candidateId)
      : intent.originNodeId;
    const nextNode = nextStop
      ? (candidateById.get(nextStop.candidateId)?.nodeId ?? nextStop.candidateId)
      : undefined;
    const previousEnd = previousStop?.endMinute ?? intent.startMinute;
    const primaryNode = primaryCandidate.nodeId ?? primaryCandidate.id;
    const primaryOutgoing = nextNode
      ? matrixCell(matrix, primaryNode, nextNode)?.durationMinutes
      : 0;
    if (primaryOutgoing === null || primaryOutgoing === undefined) continue;
    const primaryTravel = primary.travelFromPreviousMinutes + normalizeDuration(primaryOutgoing);

    const alternatives: Array<{ fallback: RouteFallback; score: number }> = [];
    for (const candidate of candidates) {
      if (primaryIds.has(candidate.id)) continue;
      if (task.candidateIds && !task.candidateIds.includes(candidate.id)) continue;
      if (
        candidate.operatingStatus === "temporarily_closed" ||
        candidate.operatingStatus === "permanently_closed"
      ) {
        continue;
      }
      const constraintResult = evaluateConstraints(candidate, task.constraints ?? []);
      if (constraintResult.hardFailure) continue;
      const candidateNode = candidate.nodeId ?? candidate.id;
      const incoming = matrixCell(matrix, previousNode, candidateNode)?.durationMinutes;
      const outgoing = nextNode ? matrixCell(matrix, candidateNode, nextNode)?.durationMinutes : 0;
      if (
        incoming === null ||
        incoming === undefined ||
        outgoing === null ||
        outgoing === undefined
      )
        continue;
      const incomingMinutes = normalizeDuration(incoming);
      const outgoingMinutes = normalizeDuration(outgoing);
      const extraTravelMinutes = incomingMinutes + outgoingMinutes - primaryTravel;
      if (extraTravelMinutes > maxExtra) continue;

      const scheduled = scheduleCandidate(intent, task, candidate, previousEnd + incomingMinutes);
      if ("rejection" in scheduled) continue;
      if (nextStop && scheduled.endMinute + outgoingMinutes > nextStop.startMinute) continue;

      const alternativeSpend = candidate.estimatedSpend;
      if (
        intent.budget !== undefined &&
        (!alternativeSpend || alternativeSpend.status === "unknown") &&
        !intent.allowUnknownSpend
      ) {
        continue;
      }
      if (
        alternativeSpend?.status === "known" &&
        intent.budget !== undefined &&
        normalizeCurrency(alternativeSpend.currency) !== normalizeCurrency(intent.budget.currency)
      ) {
        continue;
      }
      const replacementSpend =
        state.totalEstimatedSpend -
        (primary.estimatedSpend?.amount ?? 0) +
        (alternativeSpend?.status === "known" ? alternativeSpend.amount : 0);
      if (intent.budget !== undefined && replacementSpend > intent.budget.maxAmount) continue;
      alternatives.push({
        fallback: {
          taskId: task.id,
          primaryCandidateId: primary.candidateId,
          candidateId: candidate.id,
          experienceId: candidate.experienceId,
          ...(candidate.placeId ? { placeId: candidate.placeId } : {}),
          title: candidate.title,
          arrivalMinute: scheduled.arrivalMinute,
          startMinute: scheduled.startMinute,
          endMinute: scheduled.endMinute,
          incomingTravelMinutes: incomingMinutes,
          outgoingTravelMinutes: outgoingMinutes,
          extraTravelMinutes,
          warnings: [...scheduled.warnings, ...constraintResult.warnings],
        },
        score:
          clamp(candidate.utility, 0, 1) * 100 -
          Math.max(0, extraTravelMinutes) -
          scheduled.riskPenalty -
          constraintResult.penalty,
      });
    }

    const best = alternatives.sort(
      (a, b) => b.score - a.score || a.fallback.candidateId.localeCompare(b.fallback.candidateId),
    )[0];
    if (best) fallbacks.push(best.fallback);
  }
  return fallbacks;
}

function matrixCell(matrix: TravelTimeMatrix, from: string, to: string): MatrixCell | undefined {
  if (from === to) return { durationMinutes: 0, distanceMeters: 0 };
  return matrix.cells[from]?.[to];
}

function compareStates(a: SearchState, b: SearchState): number {
  if (a.score !== b.score) return b.score - a.score;
  if (a.currentMinute !== b.currentMinute) return a.currentMinute - b.currentMinute;
  const aIds = a.stops.map((stop) => stop.candidateId).join("\u0000");
  const bIds = b.stops.map((stop) => stop.candidateId).join("\u0000");
  return aIds.localeCompare(bIds);
}

function addRejection(counts: Map<RouteRejectionCode, number>, code: RouteRejectionCode): void {
  counts.set(code, (counts.get(code) ?? 0) + 1);
}

function rejectionSummary(counts: Map<RouteRejectionCode, number>): RouteRejectionSummary[] {
  return [...counts.entries()]
    .map(([code, count]) => ({ code, count }))
    .sort((a, b) => b.count - a.count || a.code.localeCompare(b.code));
}

function normalizeDuration(value: number): number {
  return Math.max(0, Math.ceil(value));
}

function validateInputs(intent: WorkdayPlanIntent, candidates: RouteCandidate[]): void {
  if (!intent.originNodeId) throw new Error("originNodeId is required");
  if (!Number.isFinite(intent.startMinute) || !Number.isFinite(intent.endMinute)) {
    throw new Error("startMinute and endMinute must be finite");
  }
  if (intent.startMinute < 0 || intent.endMinute > 1440 || intent.startMinute >= intent.endMinute) {
    throw new Error("plan window must be within one local day");
  }
  if (intent.budget) {
    if (!Number.isFinite(intent.budget.maxAmount) || intent.budget.maxAmount < 0) {
      throw new Error("budget maxAmount cannot be negative");
    }
    normalizeCurrency(intent.budget.currency);
  }
  const taskIds = new Set<string>();
  for (const task of intent.tasks) {
    if (!task.id || taskIds.has(task.id)) throw new Error(`task ids must be unique: ${task.id}`);
    taskIds.add(task.id);
    if (!Number.isFinite(task.durationMinutes) || task.durationMinutes <= 0) {
      throw new Error(`task ${task.id} must have a positive duration`);
    }
  }
  const candidateIds = new Set<string>();
  for (const candidate of candidates) {
    if (!candidate.id || candidateIds.has(candidate.id)) {
      throw new Error(`candidate ids must be unique: ${candidate.id}`);
    }
    candidateIds.add(candidate.id);
    if (!Number.isFinite(candidate.utility) || candidate.utility < 0 || candidate.utility > 1) {
      throw new Error(`candidate ${candidate.id} utility must be between 0 and 1`);
    }
    if (
      candidate.estimatedSpend?.status === "known" &&
      (!Number.isFinite(candidate.estimatedSpend.amount) ||
        candidate.estimatedSpend.amount < 0 ||
        !/^[A-Za-z]{3}$/.test(candidate.estimatedSpend.currency))
    ) {
      throw new Error(`candidate ${candidate.id} has an invalid estimatedSpend`);
    }
    if (candidate.openingHours?.status === "known") {
      for (const window of candidate.openingHours.windows) {
        if (
          !Number.isFinite(window.startMinute) ||
          !Number.isFinite(window.endMinute) ||
          window.startMinute < 0 ||
          window.endMinute > 1440 ||
          window.startMinute >= window.endMinute
        ) {
          throw new Error(`candidate ${candidate.id} has an invalid opening window`);
        }
      }
    }
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function normalizeCurrency(currency: string): string {
  const normalized = currency.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(normalized)) throw new Error(`invalid ISO 4217 currency: ${currency}`);
  return normalized;
}
