// backend/SkillExtractor.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";

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

 //  let apiKey = "OPENAI_API_KEY";

  public func extract(jobDescription : Text, apiKey : Text) : async ExtractResult {
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
      // Add 5 Billion cycles to the next call
      Cycles.add(6_000_000_000);
      let response = await ic.http_request(request);
      switch (response.body.decodeUtf8()) {
        case null #err({ error = "EXTRACT_FAILED"; message = "Could not decode AI response" });
        case (?body) {
          Debug.print("OpenAI Raw Response: " # body);
          let skills = parseSkillsFromResponse(body);
          if (skills.size() == 0) {
            #err({ error = "EXTRACT_FAILED"; message = "No technical skills identified" });
          } else {
            #ok({ skills = skills });
          };
        };
      };
    } catch (e) {
      #err({ error = "EXTRACT_FAILED"; message = "System HTTP Error: " # Error.message(e) });
    };
  };

  func jsonString(s : Text) : Text {
    let e1 = Text.replace(s, #text "\\", "\\\\");
    let e2 = Text.replace(e1, #text "\"", "\\\"");
    let e3 = Text.replace(e2, #text "\n", "\\n");
    let e4 = Text.replace(e3, #text "\r", "\\r");
    let e5 = Text.replace(e4, #text "\t", "\\t");
    "\"" # e5 # "\"";
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

  func findLast(t : Text, sub : Text) : ?Nat {
    let chars = Text.toArray(t);
    let subChars = Text.toArray(sub);
    let lenInt : Int = chars.size();
    let subLenInt : Int = subChars.size();
    if (lenInt < subLenInt) return null;
    var i : Int = lenInt - subLenInt;
    while (i >= 0) {
      let idx = Int.abs(i);
      if (arrayEq(chars, idx, subChars)) {
        return ?idx;
      };
      i -= 1;
    };
    null;
  };

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

  func extractStringArray(obj : Text) : [Text] {
    var items = Buffer.Buffer<Text>(8);
    let chars = Text.toArray(obj);
    let len = chars.size();
    var i = 0;
    var inQuotes = false;
    var currentStr = "";
    var escape = false;

    while (i < len) {
      let c = chars[i];
      if (escape) {
        if (c == 'n') { currentStr #= "\n" }
        else if (c == 't') { currentStr #= "\t" }
        else if (c == 'r') { currentStr #= "\r" }
        else { currentStr #= Text.fromChar(c) };
        escape := false;
      } else if (c == '\\') {
        escape := true;
      } else if (c == '\"') {
        if (inQuotes) {
          items.add(currentStr);
          currentStr := "";
          inQuotes := false;
        } else {
          inQuotes := true;
        };
      } else {
        if (inQuotes) {
          currentStr #= Text.fromChar(c);
        };
      };
      i += 1;
    };
    Buffer.toArray(items);
  };

  func parseSkillsFromResponse(body : Text) : [Text] {
    // 1. Extract the actual 'content' string from OpenAI's wrapper
    let contentOpt = extractStringField(body, "content");
    switch (contentOpt) {
      case null return [];
      case (?content) {
        // 2. Find the JSON array inside the extracted, unescaped content
        let start = findFirst(content, "[");
        let end = findLast(content, "]");
        switch (start, end) {
          case (?s, ?e) {
            if (e <= s) return [];
            // 3. Extract the clean strings!
            return extractStringArray(textSlice(content, s, e + 1));
          };
          case _ return [];
        };
      };
    };
  };

};
