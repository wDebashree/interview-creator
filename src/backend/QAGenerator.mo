// backend/QAGenerator.mo

import Text "mo:core/Text";
import Array "mo:core/Array";
import Char "mo:core/Char";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Utils "Utils";
import Result "mo:base/Result";

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

  public func generate(skills: [Text], jobDescription: Text, apiKey: Text) : async Result.Result<{qa: [QAGroup]; tokens: Nat}, {error: Text; message: Text}> {
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
          // FIXED: Use 'body' instead of 'bodyStr'
          let parsedData = parseQAFromResponse(body); 
          
          // FIXED: Check the size of the 'qa' array inside the record
          if (parsedData.qa.size() == 0) {
            return #err({ error = "GENERATION_FAILED"; message = "Q&A generation failed" });
          } else {
            return #ok(parsedData);
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

// 1. Parses the inner array of actual questions
  func extractQAItems(groupStr : Text) : [QAItem] {
    var items = Buffer.Buffer<QAItem>(4);
    var depth = 0;
    var objStart = 0;
    var i = 0;
    var inQuestionsArray = false;
    let chars = Text.toArray(groupStr);
    let len = chars.size();
    let questionsKey = Text.toArray("\"questions\"");

    while (i + questionsKey.size() <= len) {
      if (Utils.arrayEq(chars, i, questionsKey)) {
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
              let itemObj = Utils.textSlice(groupStr, objStart, i + 1);
              let q = Utils.extractStringField(itemObj, "question");
              let a = Utils.extractStringField(itemObj, "answer");
              switch (q, a) {
                case (?question, ?answer) {
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
    Buffer.toArray(items);
  };

  // 2. Parses the outer array of skill groups
  func extractQAGroups(obj : Text) : [QAGroup] {
    var groups = Buffer.Buffer<QAGroup>(4);
    var depth = 0;
    var objStart = 0;
    var i = 0;
    let chars = Text.toArray(obj);
    let len = chars.size();

    while (i < len) {
      let c = chars[i];
      if (c == '{') {
        if (depth == 0) { objStart := i };
        depth += 1;
      } else if (c == '}') {
        depth -= 1;
        if (depth == 0) {
          // We found a complete skill group object!
          let groupStr = Utils.textSlice(obj, objStart, i + 1);
          let skillOpt = Utils.extractStringField(groupStr, "skill");
          let questions = extractQAItems(groupStr); // Extract the questions from inside this group
          switch (skillOpt) {
            case (?skill) {
              groups.add({ skill; questions });
            };
            case null {};
          };
        };
      };
      i += 1;
    };
    Buffer.toArray(groups);
  };

  // 3. The main entry point
  func parseQAFromResponse(body : Text) : { qa : [QAGroup]; tokens : Nat } {
    let tokens = switch(Utils.extractNatField(body, "total_tokens")) { case (?t) t; case null 0 };
    let contentOpt = Utils.extractStringField(body, "content");
    switch (contentOpt) {
      case null return { qa = []; tokens };
      case (?content) {
        let start = Utils.findFirst(content, "[");
        let end = Utils.findLast(content, "]");
        switch (start, end) {
          case (?s, ?e) {
            if (e <= s) return { qa = []; tokens };
            // FIXED: We now call extractQAGroups to return the correctly structured data
            return { qa = extractQAGroups(Utils.textSlice(content, s, e + 1)); tokens };
          };
          case _ return { qa = []; tokens };
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
    let skill = Utils.extractStringField(obj, "skill");
    let questions = extractQAItems(obj);
    switch (skill) {
      case (?s) {
        if (questions.size() == 0) null
        else ?{ skill = s; questions = questions };
      };
      case null null;
    };
  };


};
