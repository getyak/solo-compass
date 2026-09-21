import { after } from "next/server";
import type { EnqueueRefreshInput } from "@solo-compass/data";
import { getRefreshQueueRepo } from "./repos";

/** Persist refresh work after the response; never perform provider I/O here. */
export function scheduleRefreshJobs(jobs: readonly EnqueueRefreshInput[]): void {
  if (jobs.length === 0) return;
  after(async () => {
    const queue = getRefreshQueueRepo();
    const results = await Promise.allSettled(jobs.map((job) => queue.enqueue(job)));
    const failures = results.filter((result) => result.status === "rejected");
    if (failures.length > 0) {
      console.error("failed to enqueue evidence refresh jobs", failures);
    }
  });
}
