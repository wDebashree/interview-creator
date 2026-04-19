import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { AlertCircle, Loader2 } from "lucide-react";
import { useState } from "react";

interface JobInputProps {
  onSubmit: (url: string, text: string) => void;
  isLoading: boolean;
  error: string | null;
}

export function JobInput({ onSubmit, isLoading, error }: JobInputProps) {
  const [url, setUrl] = useState("");
  const [text, setText] = useState("");
  const [validationError, setValidationError] = useState<string | null>(null);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedUrl = url.trim();
    const trimmedText = text.trim();

    if (!trimmedUrl && !trimmedText) {
      setValidationError(
        "Please provide a LinkedIn job URL or paste the job description.",
      );
      return;
    }

    setValidationError(null);
    onSubmit(trimmedUrl, trimmedText);
  }

  const displayError = validationError || error;

  return (
    <form
      onSubmit={handleSubmit}
      className="space-y-5"
      data-ocid="job_input.form"
    >
      <div className="space-y-1.5">
        <Label htmlFor="job-url" className="text-sm font-medium">
          LinkedIn Job URL
        </Label>
        <Input
          id="job-url"
          type="url"
          placeholder="https://www.linkedin.com/jobs/view/..."
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          disabled={isLoading}
          className="w-full"
          data-ocid="job_input.url_input"
        />
      </div>

      <div className="flex items-center gap-3">
        <div className="flex-1 h-px bg-border" />
        <span className="text-xs text-muted-foreground uppercase tracking-wide">
          or
        </span>
        <div className="flex-1 h-px bg-border" />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="job-text" className="text-sm font-medium">
          Or paste the job description
        </Label>
        <Textarea
          id="job-text"
          placeholder="Paste the full job description here..."
          value={text}
          onChange={(e) => setText(e.target.value)}
          disabled={isLoading}
          className="w-full min-h-[140px] resize-y"
          data-ocid="job_input.text_textarea"
        />
      </div>

      {displayError && (
        <Alert variant="destructive" data-ocid="job_input.error_state">
          <AlertCircle className="h-4 w-4" />
          <AlertDescription>{displayError}</AlertDescription>
        </Alert>
      )}

      <Button
        type="submit"
        disabled={isLoading}
        className="w-full"
        data-ocid="job_input.submit_button"
      >
        {isLoading ? (
          <>
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Generating…
          </>
        ) : (
          "Generate Interview Questions"
        )}
      </Button>
    </form>
  );
}
