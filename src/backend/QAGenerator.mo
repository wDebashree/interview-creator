// backend/QAGenerator.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";

module {
  public type QAItem = {
    question : Text;
    answer : Text;
  };

  public type QAGroup = {
    skill : Text;
    questions : [QAItem];
  };

  public type GenerateResult = {
    #ok : { qa : [QAGroup] };
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

  public func generate(skills : [Text], jobDescription : Text) : async GenerateResult {
    if (skills.size() == 0) {
      return #err({ error = "INVALID_INPUT"; message = "skills is required" });
    };
    if (jobDescription.size() == 0) {
      return #err({ error = "INVALID_INPUT"; message = "jobDescription is required" });
    };

    let skillList = skills.vals().join(", ");
    let prompt = "You are a technical interview coach. Given the job description and skills below, generate interview Q&A. Return ONLY a JSON array. Each element: {\"skill\":\"...\",\"questions\":[{\"question\":\"...\",\"answer\":\"...\"}]}. 2-3 questions per skill. Answers must be concise (1-3 sentences). No explanation. No markdown.\n\nSkills: " # skillList # "\n\nJob Description: " # jobDescription;

    let requestBody = "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":" # jsonString(prompt) # "}],\"temperature\":0}";

    let request : HttpRequestArgs = {
      url = "https://api.openai.com/v1/chat/completions";
      max_response_bytes = ?500_000;
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
        case null #err({ error = "GENERATION_FAILED"; message = "Could not decode AI response" });
        case (?body) {
          let qa = parseQAFromResponse(body);
          if (qa.size() == 0) {
            #err({ error = "GENERATION_FAILED"; message = "Q&A generation failed" });
          } else {
            #ok({ qa = qa });
          };
        };
      };
    } catch (_) {
      #err({ error = "GENERATION_FAILED"; message = "Q&A generation failed" });
    };
  };

  func jsonString(s : Text) : Text {
    let e1 = s.replace(#text "\\", "\\\\");
    let e2 = e1.replace(#text "\"", "\\\"");
    let e3 = e2.replace(#text "\n", "\\n");
    let e4 = e3.replace(#text "\r", "\\r");
    let e5 = e4.replace(#text "\t", "\\t");
    "\"" # e5 # "\"";
  };

  // Parse JSON string field from an object snippet
  func extractStringField(obj : Text, field : Text) : ?Text {
    let dquote = Char.fromNat32(34);
    let backslash = Char.fromNat32(92);
    let key = "\"" # field # "\":";

    // Find key in obj by scanning
    var found = false;
    var keyBuf = "";
    var value = "";
    var inValue = false;
    var escape = false;

    for (c in obj.chars()) {
      if (not found) {
        keyBuf #= Text.fromChar(c);
        // Check if keyBuf ends with key
        if (keyBuf.endsWith(#text key)) {
          found := true;
        };
      } else if (not inValue) {
        if (c == dquote) {
          inValue := true;
          value := "";
        };
      } else if (escape) {
        value #= Text.fromChar(c);
        escape := false;
      } else if (c == backslash) {
        escape := true;
      } else if (c == dquote) {
        return ?value;
      } else {
        value #= Text.fromChar(c);
      };
    };
    null;
  };

  // Parse the top-level JSON array of QAGroup objects
  func parseQAFromResponse(body : Text) : [QAGroup] {
    // Extract content between outermost [ and ]
    var arrayStart = false;
    var depth = 0;
    var arrayText = "";
    var collecting = false;

    for (c in body.chars()) {
      if (not arrayStart and c == '[') {
        arrayStart := true;
        collecting := true;
        depth := 1;
        arrayText := "[";
      } else if (collecting) {
        arrayText #= Text.fromChar(c);
        if (c == '[') { depth += 1 }
        else if (c == ']') {
          depth -= 1;
          if (depth == 0) { collecting := false };
        };
      };
    };

    if (not arrayStart) return [];
    parseQAArray(arrayText);
  };

  func parseQAArray(raw : Text) : [QAGroup] {
    var groups : [QAGroup] = [];
    var depth = 0;
    var objText = "";
    var collecting = false;

    for (c in raw.chars()) {
      if (not collecting and c == '{') {
        collecting := true;
        depth := 1;
        objText := "{";
      } else if (collecting) {
        objText #= Text.fromChar(c);
        if (c == '{') { depth += 1 }
        else if (c == '}') {
          depth -= 1;
          if (depth == 0) {
            collecting := false;
            switch (parseQAGroup(objText)) {
              case (?g) { groups := groups.concat([g]) };
              case null {};
            };
            objText := "";
          };
        };
      };
    };

    groups;
  };

  func parseQAGroup(obj : Text) : ?QAGroup {
    let skill = extractStringField(obj, "skill");
    let questions = extractQAItems(obj);
    switch (skill) {
      case (?s) {
        if (questions.size() == 0) null
        else ?{ skill = s; questions = questions };
      };
      case null null;
    };
  };

  func extractQAItems(obj : Text) : [QAItem] {
    // Find "questions":[ ... ] block
    let questionsKey = "\"questions\":[";
    var items : [QAItem] = [];
    var afterKey = false;
    var keyBuf = "";
    var depth = 0;
    var collecting = false;
    var itemText = "";

    for (c in obj.chars()) {
      if (not afterKey) {
        keyBuf #= Text.fromChar(c);
        if (keyBuf.endsWith(#text questionsKey)) {
          afterKey := true;
        };
      } else if (not collecting and c == '{') {
        collecting := true;
        depth := 1;
        itemText := "{";
      } else if (collecting) {
        itemText #= Text.fromChar(c);
        if (c == '{') { depth += 1 }
        else if (c == '}') {
          depth -= 1;
          if (depth == 0) {
            collecting := false;
            let q = extractStringField(itemText, "question");
            let a = extractStringField(itemText, "answer");
            switch (q, a) {
              case (?question, ?answer) {
                items := items.concat([{ question; answer }]);
              };
              case _ {};
            };
            itemText := "";
          };
        };
      };
    };

    items;
  };
};
