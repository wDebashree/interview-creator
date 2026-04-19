export interface QAItem {
  question: string;
  answer: string;
}

export interface QAGroup {
  skill: string;
  questions: QAItem[];
}

export interface ProcessRequest {
  url?: string;
  text?: string;
}

export interface ProcessSuccess {
  qa: QAGroup[];
}

export interface ProcessError {
  error: string;
  message: string;
  field?: string;
}

export type ProcessResponse = ProcessSuccess | ProcessError;

export function isProcessError(r: ProcessResponse): r is ProcessError {
  return "error" in r;
}
