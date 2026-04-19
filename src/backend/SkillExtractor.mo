// backend/SkillExtractor.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Utils "Utils";
import Result "mo:base/Result";

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

  public func extract(jobDescription : Text, apiKey : Text) : async Result.Result<{skills: [Text]; tokens: Nat}, {error: Text; message: Text}> {
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
          // FIXED: Use 'body' instead of 'bodyStr'
          let parsedData = parseSkillsFromResponse(body);
          
          // FIXED: Check the size of the 'skills' array inside the record
          if (parsedData.skills.size() == 0) {
            return #err({ error = "EXTRACT_FAILED"; message = "No technical skills identified" });
          } else {
            return #ok(parsedData);
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

  func parseSkillsFromResponse(body : Text) : { skills : [Text]; tokens : Nat } {
    // Extract the token count from the JSON
    let tokens = switch(Utils.extractNatField(body, "total_tokens")) { case (?t) t; case null 0 };

    let contentOpt = Utils.extractStringField(body, "content");
    switch (contentOpt) {
      case null return { skills = []; tokens }; // Return both
      case (?content) {
        let start = Utils.findFirst(content, "[");
        let end = Utils.findLast(content, "]");
        switch (start, end) {
          case (?s, ?e) {
            if (e <= s) return { skills = []; tokens };
            return { skills = Utils.extractStringArray(Utils.textSlice(content, s, e + 1)); tokens };
          };
          case _ return { skills = []; tokens };
        };
      };
    };
  };

};
