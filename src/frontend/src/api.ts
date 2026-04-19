import type { ProcessRequest, ProcessResponse } from "./types";

const BASE_URL = "/v1/process";

export async function processJob(
  req: ProcessRequest,
): Promise<ProcessResponse> {
  const response = await fetch(BASE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });

  const data: ProcessResponse = await response.json();
  return data;
}
