// backend/SkillExtractor.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";

module {
  public type ExtractResult = {
    #ok : { skills : [Text] };
    #err : { error : Text; message : Text };
  };

  type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [{ name : Text; value : Text }];
    body : ?Blob;
    method : { #get; #post; #head };
    transform : ?{
      function : shared query ({ response : HttpResponse; context : Blob }) -> async HttpResponse;
      context : Blob;
    };
  };

  type HttpResponse = {
    status : Nat;
    headers : [{ name : Text; value : Text }];
    body : Blob;
  };

  type IC = actor {
    http_request : HttpRequestArgs -> async HttpResponse;
  };

  let apiKey = "OPENAI_API_KEY";

  public func extract(jobDescription : Text) : async ExtractResult {
    if (jobDescription.size() == 0) {
      return #err({ error = "INVALID_INPUT"; message = "Field is required" });
    };

    let prompt = "List only the technical skills mentioned in the following job description. Return a JSON array of strings. Normalize variants (e.g. 'JS' -> 'JavaScript'). No duplicates. No explanation. Only the JSON array.\n\n" # jobDescription;

    let requestBody = "{ \"model\": \"gpt-4o-mini\", \"messages\": [{ \"role\": \"user\", \"content\": " # jsonString(prompt) # " }], \"temperature\": 0 }";

    let request : HttpRequestArgs = {
      url = "https://api.openai.com/v1/chat/completions";
      max_response_bytes = ?200_000;
      headers = [
        { name = "Content-Type"; value = "application/json" },
        { name = "Authorization"; value = "Bearer " # apiKey },
      ];
      body = ?requestBody.encodeUtf8();
      method = #post;
      transform = null;
    };

    try {
      let ic : IC = actor ("aaaaa-aa");
      let response = await ic.http_request(request);
      switch (response.body.decodeUtf8()) {
        case null #err({ error = "EXTRACT_FAILED"; message = "Could not decode AI response" });
        case (?body) {
          let skills = parseSkillsFromResponse(body);
          if (skills.size() == 0) {
            #err({ error = "EXTRACT_FAILED"; message = "No technical skills identified" });
          } else {
            #ok({ skills = skills });
          };
        };
      };
    } catch (_) {
      #err({ error = "EXTRACT_FAILED"; message = "No technical skills identified" });
    };
  };

  func jsonString(s : Text) : Text {
    let e1 = s.replace(#text "\"", "\\\"");
    let e2 = e1.replace(#text "\n", "\\n");
    "\"" # e2 # "\"";
  };

  func parseSkillsFromResponse(body : Text) : [Text] {
    let dquote = Char.fromNat32(34);
    var skills : [Text] = [];
    var current = "";
    var inString = false;
    var inArray = false;
    var escape = false;

    for (c in body.chars()) {
      if (not inArray) {
        if (c == '[') { inArray := true };
      } else if (escape) {
        current #= Text.fromChar(c);
        escape := false;
      } else if (c == '\\') {
        escape := true;
      } else if (c == dquote and not inString) {
        inString := true;
        current := "";
      } else if (c == dquote and inString) {
        inString := false;
        let trimmed = current.trim(#char ' ');
        if (trimmed.size() > 0) {
          skills := skills.concat([trimmed]);
        };
      } else if (inString) {
        current #= Text.fromChar(c);
      } else if (c == ']') {
        inArray := false;
      };
    };

    skills;
  };
};
