import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import type { QAGroup } from "@/types";

interface QADisplayProps {
  groups: QAGroup[];
}

export function QADisplay({ groups }: QADisplayProps) {
  if (groups.length === 0) return null;

  return (
    <div className="space-y-8" data-ocid="qa_display.section">
      <div className="flex items-center gap-3">
        <h2 className="text-lg font-semibold text-foreground">
          Interview Questions
        </h2>
        <Badge variant="secondary" className="text-xs">
          {groups.length} {groups.length === 1 ? "skill" : "skills"}
        </Badge>
      </div>

      {groups.map((group, groupIndex) => (
        <div
          key={group.skill}
          className="rounded-lg border border-border bg-card overflow-hidden"
          data-ocid={`qa_display.item.${groupIndex + 1}`}
        >
          <div className="px-5 py-3 bg-muted/40 border-b border-border">
            <h3 className="font-semibold text-foreground text-sm tracking-wide uppercase">
              {group.skill}
            </h3>
          </div>

          <div className="divide-y divide-border">
            {group.questions.map((qa, qaIndex) => (
              <div
                key={`${group.skill}-${qaIndex}`}
                className="px-5 py-4 space-y-2"
              >
                <p className="font-medium text-foreground text-sm leading-relaxed">
                  {qa.question}
                </p>
                <p className="text-muted-foreground text-sm leading-relaxed">
                  {qa.answer}
                </p>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
