import type { ProcessRequest, ProcessResponse } from "./types";

// const BASE_URL = "/v1/process";
const BASE_URL = "http://uxrrr-q7777-77774-qaaaq-cai.localhost:4943";

// Look for the Canister ID injected by Vite/dfx during the build
const backendCanisterId = 
  import.meta.env.VITE_CANISTER_ID_BACKEND || 
  process.env.CANISTER_ID_BACKEND;

// Determine if we are on localhost or production
const isLocal = window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1";

// Construct the correct URL for the IC HTTP gateway
// const BASE_URL = isLocal
//   ? `http://${backendCanisterId}.localhost:4943/v1/process`
//   : `https://${backendCanisterId}.icp0.io/v1/process`;

export async function processJob(req: ProcessRequest): Promise<ProcessResponse> {
  // Step 1: Extract Skills
  const extractRes = await fetch(`${BASE_URL}/v1/extract-skills`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });

  const extractData = await extractRes.json();
  if (extractData.error) throw new Error(extractData.message);

  const skills: string[] = extractData.skills;
  const jobDescription: string = extractData.jobDescription;
  const allQA = [];
  const chunkSize = 3;

  // Step 2: Batch Generate in Chunks
  for (let i = 0; i < skills.length; i += chunkSize) {
    const chunk = skills.slice(i, i + chunkSize);

    const generateRes = await fetch(`${BASE_URL}/v1/generate-qa`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        skills: chunk.join(","), // Pass as a comma-separated string
        jobDescription
      }),
    });

    const generateData = await generateRes.json();
    if (generateData.error) {
       console.warn("Chunk failed, skipping:", generateData.message);
       continue; // Skip failed chunk but keep processing the rest
    }

    if (generateData.qa) {
      allQA.push(...generateData.qa);
    }
  }

  return { qa: allQA };
}
