// backend/QAGenerator.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";

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

  // let apiKey = "OPENAI_API_KEY";

  public func generate(skills : [Text], jobDescription : Text, apiKey : Text) : async GenerateResult {
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
      Cycles.add(6_000_000_000);
      let response = await ic.http_request(request);
      switch (response.body.decodeUtf8()) {
        case null #err({ error = "GENERATION_FAILED"; message = "Could not decode AI response" });
        case (?body) {
          Debug.print("QAGenerator Raw Response: " # body);
          let qa = parseQAFromResponse(body);
          if (qa.size() == 0) {
            #err({ error = "GENERATION_FAILED"; message = "Q&A generation failed" });
          } else {
            #ok({ qa = qa });
          };
        };
      };
    } catch (e) {
      #err({ error = "GENERATION_FAILED"; message = "System HTTP Error: " # Error.message(e) });
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
    let key = "\"" # field # "\"";
    let chars = Text.toArray(obj);
    let keyChars = Text.toArray(key);
    let keyLen = keyChars.size();
    let len = chars.size();
    var i = 0;
    while (i + keyLen <= len) {
      if (arrayEq(chars, i, keyChars)) {
        var j = i + keyLen;
        while (j < len and (chars[j] == ' ' or chars[j] == ':' or chars[j] == '\n' or chars[j] == '\r' or chars[j] == '\t')) { j += 1 };
        if (j < len and chars[j] == '\"') {
          j += 1;
          var value = "";
          var escape = false;
          while (j < len) {
            let c = chars[j];
            if (escape) {
              if (c == 'n') { value #= "\n" }
              else if (c == 't') { value #= "\t" }
              else if (c == 'r') { value #= "\r" }
              else { value #= Text.fromChar(c) };
              escape := false;
            } else if (c == '\\') {
              escape := true;
            } else if (c == '\"') {
              return ?value;
            } else {
              value #= Text.fromChar(c);
            };
            j += 1;
          };
        };
      };
      i += 1;
    };
    null;
  };


  // Parse the top-level JSON array of QAGroup objects
  func parseQAFromResponse(body : Text) : [QAGroup] {
    // 1. First, extract the actual 'content' string from OpenAI's wrapper
    let contentOpt = extractStringField(body, "content");
    switch (contentOpt) {
      case null return [];
      case (?content) {
        // 2. Now find the JSON array inside the extracted, unescaped content
        let start = findFirst(content, "[");
        let end = findLast(content, "]");
        switch (start, end) {
          case (?s, ?e) {
            if (e <= s) return [];
            parseQAArray(textSlice(content, s, e + 1));
          };
          case _ return [];
        };
      };
    };
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
    // FIXED: Use a dynamically sizing Buffer instead of an Array
    var items = Buffer.Buffer<QAItem>(8); 
    var depth = 0;
    var objStart = 0;
    var i = 0;
    var inQuestionsArray = false;
    let chars = Text.toArray(obj);
    let len = chars.size();
    let questionsKey = Text.toArray("\"questions\"");
    
    while (i + questionsKey.size() <= len) {
      if (arrayEq(chars, i, questionsKey)) { 
        inQuestionsArray := true;
        i += questionsKey.size();
      } else {
        if (inQuestionsArray) {
          let c = chars[i];
          if (c == '{') {
            if (depth == 0) { objStart := i };
            depth += 1;
          } else if (c == '}') {
            depth -= 1;
            if (depth == 0) {
              let itemObj = textSlice(obj, objStart, i + 1);
              let q = extractStringField(itemObj, "question");
              let a = extractStringField(itemObj, "answer");
              switch (q, a) {
                case (?question, ?answer) {
                  // FIXED: Safely add the item to the Buffer
                  items.add({ question; answer });
                };
                case _ {};
              };
            };
          };
        };
        i += 1;
      };
    };
    // Convert the Buffer back to a standard Array before returning
    Buffer.toArray(items);
  };

  func arrayEq(chars : [Char], offset : Nat, sub : [Char]) : Bool {
    let subLen = sub.size();
    var k = 0;
    while (k < subLen) {
      if (chars[offset + k] != sub[k]) return false;
      k += 1;
    };
    true;
  };

  // Helper to slice a text string between two indices
  func textSlice(t : Text, start : Nat, end : Nat) : Text {
    let chars = Text.toArray(t);
    if (start >= end) return "";
    let actualEnd = if (end > chars.size()) chars.size() else end;
    var res = "";
    var i = start;
    while (i < actualEnd) {
      res #= Text.fromChar(chars[i]);
      i += 1;
    };
    res;
  };

  // Helper to find the first occurrence of a substring
  func findFirst(t : Text, sub : Text) : ?Nat {
    let chars = Text.toArray(t);
    let subChars = Text.toArray(sub);
    let len = chars.size();
    let subLen = subChars.size();
    var i = 0;
    while (i + subLen <= len) {
      if (arrayEq(chars, i, subChars)) return ?i;
      i += 1;
    };
    null;
  };

  // Helper to find the last occurrence of a substring safely using Int
  func findLast(t : Text, sub : Text) : ?Nat {
    let chars = Text.toArray(t);
    let subChars = Text.toArray(sub);
    
    // Convert Nat to Int to allow safe subtraction and reverse looping
    let lenInt : Int = chars.size();
    let subLenInt : Int = subChars.size();
    
    if (lenInt < subLenInt) return null;

    var i : Int = lenInt - subLenInt;
    while (i >= 0) {
      let idx = Int.abs(i); // Convert Int back to Nat for array indexing
      if (arrayEq(chars, idx, subChars)) {
        return ?idx;
      };
      i -= 1;
    };
    null;
  };

};
