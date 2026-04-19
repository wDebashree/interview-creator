import { useState } from "react";
import { processJob } from "./api";
import { JobInput } from "./components/JobInput";
import { QADisplay } from "./components/QADisplay";
import { isProcessError } from "./types";
import type { QAGroup } from "./types";

export default function App() {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<QAGroup[] | null>(null);
  // NEW: State to hold the total tokens used
  const [tokensUsed, setTokensUsed] = useState<number | null>(null);

  async function handleSubmit(url: string, text: string) {
    setIsLoading(true);
    setError(null);
    setResults(null);
    setTokensUsed(null); // Reset tokens on new submission

    try {
      const req = url ? { url } : { text };
      const response = await processJob(req);

      if (isProcessError(response)) {
        setError(response.message || "An error occurred. Please try again.");
      } else {
        setResults(response.qa);
        // NEW: Capture the tokens from the successful response
        setTokensUsed(response.tokens);
      }
    } catch {
      setError("Failed to connect to the server. Please try again.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-background" data-ocid="app.page">
      <header className="bg-card border-b border-border shadow-sm">
        <div className="max-w-2xl mx-auto px-4 py-4">
          <h1 className="text-xl font-semibold text-foreground">
            Interview Prep
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Generate skill-based interview Q&amp;A from a job description
          </p>
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-4 py-8 space-y-8">
        <div className="bg-card rounded-lg border border-border p-6">
          <JobInput
            onSubmit={handleSubmit}
            isLoading={isLoading}
            error={error}
          />
        </div>

        {isLoading && (
          <div
            className="text-center py-10 text-muted-foreground text-sm"
            data-ocid="app.loading_state"
          >
            <div className="flex flex-col items-center gap-3">
              <svg
                className="animate-spin h-6 w-6 text-muted-foreground"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                />
              </svg>
              <span>Analyzing job description and generating questions…</span>
            </div>
          </div>
        )}

        {/* NEW: Token Display Banner */}
        {tokensUsed !== null && !isLoading && (
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 text-center">
            <p className="text-blue-800 text-sm font-medium flex items-center justify-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10"></circle>
                <line x1="12" y1="16" x2="12" y2="12"></line>
                <line x1="12" y1="8" x2="12.01" y2="8"></line>
              </svg>
              API Usage: {tokensUsed.toLocaleString()} tokens utilized
            </p>
          </div>
        )}

        {results && !isLoading && <QADisplay groups={results} />}
      </main>

      <footer className="bg-muted/40 border-t border-border mt-16">
        <div className="max-w-2xl mx-auto px-4 py-4 text-center text-xs text-muted-foreground">
          © {new Date().getFullYear()}. Built with love using{" "}
          <a
            href={`https://caffeine.ai?utm_source=caffeine-footer&utm_medium=referral&utm_content=${encodeURIComponent(typeof window !== "undefined" ? window.location.hostname : "")}`}
            target="_blank"
            rel="noopener noreferrer"
            className="underline underline-offset-2 hover:text-foreground transition-colors duration-200"
          >
            caffeine.ai
          </a>
        </div>
      </footer>
    </div>
  );
}