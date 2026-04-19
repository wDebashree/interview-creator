// backend/main.mo

import Text "mo:core/Text";
import Char "mo:core/Char";
import URLFetcher "URLFetcher";
import JobParser "JobParser";
import SkillExtractor "SkillExtractor";
import QAGenerator "QAGenerator";
import Iter "mo:base/Iter";

persistent actor class Backend(apiKey : Text) {
//  public query func http_request(req : HttpRequest) : async HttpResponse {
//    { status_code = 200; headers = [("Content-Type", "text/plain")]; body = "OK".encodeUtf8(); upgrade = ?true };
//  };

  public query func http_request(req : HttpRequest) : async HttpResponse {
    if (req.method == "OPTIONS") {
      return {
        status_code = 204;
        headers = [
          ("Access-Control-Allow-Origin", "*"),
          ("Access-Control-Allow-Methods", "POST, GET, OPTIONS"),
          ("Access-Control-Allow-Headers", "Content-Type")
        ];
        body = Text.encodeUtf8("");
        upgrade = null;
      };
    };
    { status_code = 200; headers = [("Content-Type", "text/plain")]; body = Text.encodeUtf8("OK"); upgrade = ?true };
  };

  public shared({ caller }) func http_request_update(req : HttpRequest) : async HttpResponse {
      let path = req.url;
      
      // --- ENDPOINT 1: Extract Skills ---
      if (path == "/v1/extract-skills") {
        let bodyStr = switch(Text.decodeUtf8(req.body)) { case (?b) b; case null "" };
        let urlOpt = extractStringField(bodyStr, "url");
        let textOpt = extractStringField(bodyStr, "text");
        
        var jobDescription = "";
        if (urlOpt != null) {
          let u = switch(urlOpt) { case (?v) v; case null "" };
          let fetchRes = await URLFetcher.fetch(u);
          switch(fetchRes) {
            case (#err e) return errorResponse(502, e.error, e.message);
            case (#ok payload) {
              let parseRes = JobParser.parse(#html(payload.html));
              switch(parseRes) {
                case (#err e) return errorResponse(422, e.error, e.message);
                case (#ok payload) { jobDescription := payload.jobDescription };
              };
            };
          };
        } else if (textOpt != null) {
          let t = switch(textOpt) { case (?v) v; case null "" };
          // FIXED: Pass as a proper variant using #text()
          let parseRes = JobParser.parse(#text(t));
          switch(parseRes) {
            case (#err e) return errorResponse(422, e.error, e.message);
            case (#ok payload) { jobDescription := payload.jobDescription };
          };
        } else {
           return errorResponse(400, "BAD_REQUEST", "Must provide url or text");
        };

        let skillsRes = await SkillExtractor.extract(jobDescription, apiKey);
        switch(skillsRes) {
          case (#err e) return errorResponse(422, e.error, e.message);
          case (#ok { skills }) {
            var skillsArrJson = "[";
            var idx = 0;
            let len = skills.size();
            while (idx < len) {
              skillsArrJson #= "\"" # skills[idx] # "\"";
              if (idx < len - 1) { skillsArrJson #= ", " };
              idx += 1;
            };
            skillsArrJson #= "]";
            
            let escapedJd = Text.replace(jobDescription, #text "\"", "\\\"");
            let escapedJd2 = Text.replace(escapedJd, #text "\n", "\\n");
            let escapedJd3 = Text.replace(escapedJd2, #text "\r", "\\r");
            let escapedJd4 = Text.replace(escapedJd3, #text "\t", "\\t");

            return jsonResponse(200, "{\"skills\": " # skillsArrJson # ", \"jobDescription\": \"" # escapedJd4 # "\"}");
          };
        };
      }
      
      // --- ENDPOINT 2: Generate QA (Batched) ---
      else if (path == "/v1/generate-qa") {
        let bodyStr = switch(Text.decodeUtf8(req.body)) { case (?b) b; case null "" };
        let skillsStrOpt = extractStringField(bodyStr, "skills");
        let jdOpt = extractStringField(bodyStr, "jobDescription");
        
        if (skillsStrOpt == null or jdOpt == null) {
           return errorResponse(400, "BAD_REQUEST", "Missing skills or jobDescription");
        };
        
        let skillsStr = switch(skillsStrOpt) { case (?s) s; case null "" };
        let jd = switch(jdOpt) { case (?j) j; case null "" };
        
        let skillsIter = Text.split(skillsStr, #char ',');
        let skillsArr = Iter.toArray<Text>(skillsIter);
        
        let qaRes = await QAGenerator.generate(skillsArr, jd, apiKey);
        switch(qaRes) {
          case (#err e) return errorResponse(422, e.error, e.message);
          case (#ok { qa = qaItems }) {
             // FIXED: Nested loop to handle QAGroups and their QAItems
             var qaJson = "[";
             var i = 0;
             let len = qaItems.size();
             while (i < len) {
               let group = qaItems[i];
               let sEsc1 = Text.replace(group.skill, #text "\"", "\\\"");
               let sEsc2 = Text.replace(sEsc1, #text "\n", "\\n");
               
               qaJson #= "{\"skill\": \"" # sEsc2 # "\", \"questions\": [";
               
               var j = 0;
               let qLen = group.questions.size();
               while (j < qLen) {
                 let item = group.questions[j];
                 let qEsc1 = Text.replace(item.question, #text "\"", "\\\"");
                 let qEsc2 = Text.replace(qEsc1, #text "\n", "\\n");
                 let aEsc1 = Text.replace(item.answer, #text "\"", "\\\"");
                 let aEsc2 = Text.replace(aEsc1, #text "\n", "\\n");
                 
                 qaJson #= "{\"question\": \"" # qEsc2 # "\", \"answer\": \"" # aEsc2 # "\"}";
                 if (j < qLen - 1) { qaJson #= ", " };
                 j += 1;
               };
               qaJson #= "]}";
               
               if (i < len - 1) { qaJson #= ", " };
               i += 1;
             };
             qaJson #= "]";
             return jsonResponse(200, "{\"qa\": " # qaJson # "}");
          };
        };
      };
      
      return errorResponse(404, "NOT_FOUND", "Endpoint not found");
    };

  func handleProcess(bodyText : Text) : async HttpResponse {
    let url = extractStringField(bodyText, "url");
    let text = extractStringField(bodyText, "text");

    let jobDescription : Text = switch (url, text) {
      case (?u, _) {
        if (u.size() == 0) {
          return errorResponse(400, "INVALID_INPUT", "url must not be empty");
        };
        let fetchResult = await URLFetcher.fetch(u);
        let html = switch (fetchResult) {
          case (#ok r) r.html;
          case (#err e) return errorResponse(502, e.error, e.message);
        };
        let parseResult = JobParser.parse(#html html);
        switch (parseResult) {
          case (#ok r) r.jobDescription;
          case (#err e) return errorResponse(422, e.error, e.message);
        };
      };
      case (null, ?t) {
        if (t.size() == 0) {
          return errorResponse(400, "INVALID_INPUT", "text must not be empty");
        };
        let parseResult = JobParser.parse(#text t);
        switch (parseResult) {
          case (#ok r) r.jobDescription;
          case (#err e) return errorResponse(422, e.error, e.message);
        };
      };
      case (null, null) {
        return errorResponse(400, "INVALID_INPUT", "Provide either 'url' or 'text'");
      };
    };

    let skillsResult = await SkillExtractor.extract(jobDescription, apiKey);
    let skills = switch (skillsResult) {
      case (#ok r) r.skills;
      case (#err e) return errorResponse(422, e.error, e.message);
    };

    let qaResult = await QAGenerator.generate(skills, jobDescription, apiKey);
    switch (qaResult) {
      case (#ok r) {
        let json = qaToJson(r.qa);
        jsonResponse(200, json);
      };
      case (#err e) errorResponse(422, e.error, e.message);
    };
  };

  func qaToJson(qa : [QAGenerator.QAGroup]) : Text {
    var groups = "";
    var first = true;
    for (g in qa.vals()) {
      if (not first) { groups #= "," };
      first := false;
      var items = "";
      var firstItem = true;
      for (q in g.questions.vals()) {
        if (not firstItem) { items #= "," };
        firstItem := false;
        items #= "{\"question\":" # jsonStr(q.question) # ",\"answer\":" # jsonStr(q.answer) # "}";
      };
      groups #= "{\"skill\":" # jsonStr(g.skill) # ",\"questions\":[" # items # "]}";
    };
    "{\"qa\":[" # groups # "]}";
  };

  func jsonStr(s : Text) : Text {
    let e1 = s.replace(#text "\\", "\\\\");
    let e2 = e1.replace(#text "\"", "\\\"");
    let e3 = e2.replace(#text "\n", "\\n");
    let e4 = e3.replace(#text "\r", "\\r");
    let e5 = e4.replace(#text "\t", "\\t");
    "\"" # e5 # "\"";
  };

//  func jsonResponse(status : Nat16, body : Text) : HttpResponse {
//    {
//      status_code = status;
//      headers = [("Content-Type", "application/json")];
//      body = body.encodeUtf8();
//      upgrade = null;
//    };
//  };

  func jsonResponse(status : Nat16, body : Text) : HttpResponse {
    {
      status_code = status;
      headers = [
        ("Content-Type", "application/json"),
        ("Access-Control-Allow-Origin", "*")
      ];
      body = Text.encodeUtf8(body);
      upgrade = null;
    };
  };


//  func errorResponse(status : Nat16, error : Text, message : Text) : HttpResponse {
//    jsonResponse(status, "{\"error\":" # jsonStr(error) # ",\"message\":" # jsonStr(message) # "}");
//  };

  func errorResponse(status : Nat16, error : Text, message : Text) : HttpResponse {
    {
      status_code = status;
      headers = [
        ("Content-Type", "application/json"),
        ("Access-Control-Allow-Origin", "*")
      ];
      body = Text.encodeUtf8("{\"error\":" # jsonStr(error) # ",\"message\":" # jsonStr(message) # "}");
      upgrade = null;
    };
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

  type HttpRequest = {
    method : Text;
    url : Text;
    headers : [(Text, Text)];
    body : Blob;
  };

  type HttpResponse = {
    status_code : Nat16;
    headers : [(Text, Text)];
    body : Blob;
    upgrade : ?Bool;
  };
};
