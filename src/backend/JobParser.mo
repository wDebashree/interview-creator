// backend/JobParser.mo

import Text "mo:core/Text";

module {
  public type ParseInput = {
    #html : Text;
    #text : Text;
  };

  public type ParseResult = {
    #ok : { jobDescription : Text };
    #err : { error : Text; message : Text };
  };

  public func parse(input : ParseInput) : ParseResult {
    let raw = switch (input) {
      case (#html h) stripTags(h);
      case (#text t) t;
    };

    let cleaned = normalize(raw);

    if (cleaned.size() == 0) {
      return #err({ error = "PARSE_FAILED"; message = "No job description content found" });
    };

    #ok({ jobDescription = cleaned });
  };

  func stripTags(html : Text) : Text {
    var result = "";
    var inTag = false;

    for (c in html.chars()) {
      if (c == '<') {
        inTag := true;
      } else if (c == '>') {
        inTag := false;
        result #= " ";
      } else if (not inTag) {
        result #= Text.fromChar(c);
      };
    };

    result;
  };

  func normalize(raw : Text) : Text {
    var result = "";
    var prevSpace = true;

    for (c in raw.chars()) {
      if (c == '\n' or c == '\r' or c == '\t') {
        if (not prevSpace) {
          result #= " ";
          prevSpace := true;
        };
      } else if (c == ' ') {
        if (not prevSpace) {
          result #= " ";
          prevSpace := true;
        };
      } else {
        result #= Text.fromChar(c);
        prevSpace := false;
      };
    };

    result.trimStart(#char ' ').trimEnd(#char ' ');
  };
};
